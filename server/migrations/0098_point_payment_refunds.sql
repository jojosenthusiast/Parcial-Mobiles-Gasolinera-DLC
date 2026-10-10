BEGIN;
CREATE TABLE customer_point_refund_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 payment_id uuid NOT NULL REFERENCES customer_point_payments(id),points bigint NOT NULL CHECK(points>0),
 requested_by uuid NOT NULL REFERENCES users(id),command_id uuid NOT NULL,reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 8 AND 500),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(organization_id,command_id)
);
CREATE INDEX point_refund_payment_idx ON customer_point_refund_requests(payment_id);
CREATE TABLE customer_point_refund_decisions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 request_id uuid NOT NULL UNIQUE REFERENCES customer_point_refund_requests(id),decision text NOT NULL CHECK(decision IN('approved','rejected')),
 decided_by uuid NOT NULL REFERENCES users(id),command_id uuid NOT NULL,reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 8 AND 500),
 amount_usd numeric(18,2) NOT NULL DEFAULT 0 CHECK(amount_usd>=0),created_at timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(organization_id,command_id)
);
CREATE FUNCTION validate_point_refund_request() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE p customer_point_payments%ROWTYPE; occupied bigint;
BEGIN
 SELECT * INTO p FROM customer_point_payments WHERE id=NEW.payment_id FOR UPDATE;
 IF p.id IS NULL OR p.organization_id<>NEW.organization_id OR p.branch_id<>NEW.branch_id
 OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.requested_by AND organization_id=p.organization_id AND status='active') THEN
  RAISE EXCEPTION 'Point refund request scope mismatch' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(r.points),0) INTO occupied FROM customer_point_refund_requests r LEFT JOIN customer_point_refund_decisions d ON d.request_id=r.id
  WHERE r.payment_id=p.id AND (d.id IS NULL OR d.decision='approved');
 IF NEW.points>p.points-occupied THEN RAISE EXCEPTION 'Point refund exceeds unreserved points' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE FUNCTION validate_point_refund_decision() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE r customer_point_refund_requests%ROWTYPE; p customer_point_payments%ROWTYPE; returned bigint; paid_back numeric;
BEGIN
 SELECT * INTO r FROM customer_point_refund_requests WHERE id=NEW.request_id FOR UPDATE;
 SELECT * INTO p FROM customer_point_payments WHERE id=r.payment_id FOR UPDATE;
 IF r.id IS NULL OR r.organization_id<>NEW.organization_id OR r.branch_id<>NEW.branch_id OR r.requested_by=NEW.decided_by
 OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.decided_by AND organization_id=r.organization_id AND status='active') THEN
  RAISE EXCEPTION 'Independent point refund decision required' USING ERRCODE='23514'; END IF;
 NEW.amount_usd:=0;
 IF NEW.decision='approved' THEN
  SELECT coalesce(sum(x.points),0),coalesce(sum(d.amount_usd),0) INTO returned,paid_back
   FROM customer_point_refund_requests x JOIN customer_point_refund_decisions d ON d.request_id=x.id
   WHERE x.payment_id=p.id AND d.decision='approved';
  IF returned+r.points>p.points THEN RAISE EXCEPTION 'Point refund exceeds original tender' USING ERRCODE='23514'; END IF;
  -- Cumulative rounding ensures the final refund returns the exact original cents.
  NEW.amount_usd:=floor(p.amount_usd*(returned+r.points)::numeric/p.points*100)/100-paid_back;
 END IF;
 RETURN NEW;
END; $$;
CREATE FUNCTION restore_refunded_point_tender() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE r customer_point_refund_requests%ROWTYPE; p customer_point_payments%ROWTYPE;
BEGIN
 IF NEW.decision<>'approved' THEN RETURN NEW; END IF;
 SELECT * INTO r FROM customer_point_refund_requests WHERE id=NEW.request_id;
 SELECT * INTO p FROM customer_point_payments WHERE id=r.payment_id;
 INSERT INTO customer_points_ledger(organization_id,customer_id,program_id,event_type,points_delta,source_type,source_id,command_id,reason,created_by)
 VALUES(p.organization_id,p.customer_id,p.program_id,'release',r.points,'sale_point_refund',NEW.id,NEW.command_id,NEW.reason,NEW.decided_by);
 RETURN NEW;
END; $$;
CREATE TRIGGER point_refund_request_guard BEFORE INSERT ON customer_point_refund_requests FOR EACH ROW EXECUTE FUNCTION validate_point_refund_request();
CREATE TRIGGER point_refund_decision_guard BEFORE INSERT ON customer_point_refund_decisions FOR EACH ROW EXECUTE FUNCTION validate_point_refund_decision();
CREATE TRIGGER point_refund_ledger AFTER INSERT ON customer_point_refund_decisions FOR EACH ROW EXECUTE FUNCTION restore_refunded_point_tender();
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['customer_point_refund_requests','customer_point_refund_decisions'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
  EXECUTE format('CREATE TRIGGER immutable_guard BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',t);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION validate_point_refund_request(),validate_point_refund_decision(),restore_refunded_point_tender() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE VIEW sale_collection_balances WITH(security_invoker=true) AS
 SELECT s.id,s.organization_id,s.branch_id,
  CASE WHEN coalesce(p.collected,0)>=s.total_usd OR cc.id IS NOT NULL AND st.outstanding_usd=0 THEN 'paid'
   WHEN cc.id IS NOT NULL THEN 'on_credit' ELSE 'pending_collection' END AS collection_status,
  coalesce(p.collected,0) AS collected_usd,coalesce(p.reserved,0) AS reserved_usd,
  greatest(s.total_usd-coalesce(p.collected,0)-coalesce(cc.amount_usd,0),0) AS outstanding_usd,
  coalesce(r.refunded,0) AS refunded_usd,
  CASE WHEN coalesce(r.refunded,0)=0 THEN 'none' WHEN r.refunded>=p.collected THEN 'refunded' ELSE 'partial' END AS refund_status
 FROM sales s LEFT JOIN LATERAL(
  SELECT coalesce(sum(a.amount_usd) FILTER(WHERE e.outcome='confirmed'),0)+coalesce((
    SELECT sum(al.amount_usd) FROM prepayment_allocations al JOIN prepayment_advances adv ON adv.id=al.advance_id
    WHERE al.sale_id=s.id AND adv.tender_kind='captured' AND prepayment_current_outcome(adv.id)='confirmed'),0)
    +coalesce((SELECT sum(cp.amount_usd) FROM customer_point_payments cp WHERE cp.sale_id=s.id),0) AS collected,
   sum(a.amount_usd) FILTER(WHERE e.outcome IS NULL OR e.outcome='unknown') AS reserved
  FROM payment_attempts a LEFT JOIN LATERAL(SELECT outcome FROM payment_events WHERE attempt_id=a.id
   ORDER BY (outcome<>'unknown') DESC,created_at DESC,id DESC LIMIT 1)e ON true
  WHERE a.sale_id=s.id AND a.mode='manual'
 )p ON true LEFT JOIN LATERAL(
  SELECT coalesce((SELECT sum(pd.amount_usd) FROM customer_point_refund_decisions pd JOIN customer_point_refund_requests pr ON pr.id=pd.request_id JOIN customer_point_payments pp ON pp.id=pr.payment_id WHERE pp.sale_id=s.id AND pd.decision='approved'),0)+coalesce(sum(rr.amount_usd),0) AS refunded FROM payment_refunds rr JOIN payment_events e ON e.id=rr.payment_event_id
   JOIN payment_attempts a ON a.id=e.attempt_id WHERE a.sale_id=s.id AND a.mode='manual'
 )r ON true LEFT JOIN commercial_credit_charges cc ON cc.sale_id=s.id
 LEFT JOIN commercial_account_statement st ON st.id=cc.id;


COMMIT;
