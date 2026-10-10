BEGIN;

CREATE TABLE customer_point_payment_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  sale_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  cash_session_id uuid NOT NULL,
  program_id uuid NOT NULL,
  points bigint NOT NULL CHECK(points > 0),
  amount_usd numeric(18,2) NOT NULL CHECK(amount_usd > 0),
  redemption_usd_per_point numeric(12,6) NOT NULL CHECK(redemption_usd_per_point > 0),
  status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','confirmed','declined','expired')),
  expires_at timestamptz NOT NULL,
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
  requested_by uuid NOT NULL,
  decision_command_id uuid,
  decision_hash char(64) CHECK(decision_hash IS NULL OR decision_hash ~ '^[0-9a-f]{64}$'),
  decided_by_customer_id uuid,
  confirmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(sale_id,organization_id,branch_id) REFERENCES sales(id,organization_id,branch_id),
  FOREIGN KEY(customer_id,organization_id) REFERENCES customer_accounts(id,organization_id),
  FOREIGN KEY(cash_session_id,organization_id,branch_id) REFERENCES cash_sessions(id,organization_id,branch_id),
  FOREIGN KEY(program_id,organization_id) REFERENCES customer_loyalty_programs(id,organization_id),
  FOREIGN KEY(requested_by,organization_id) REFERENCES users(id,organization_id),
  FOREIGN KEY(decided_by_customer_id,organization_id) REFERENCES customer_accounts(id,organization_id),
  UNIQUE(organization_id,command_id),
  UNIQUE(id,organization_id,branch_id),
  CHECK((status='confirmed')=(confirmed_at IS NOT NULL)),
  CHECK((decision_command_id IS NULL)=(decision_hash IS NULL))
);
CREATE UNIQUE INDEX customer_point_quote_one_pending_sale_idx
  ON customer_point_payment_quotes(organization_id,sale_id) WHERE status='pending';
CREATE INDEX customer_point_quote_customer_pending_idx
  ON customer_point_payment_quotes(organization_id,customer_id,expires_at,id) WHERE status='pending';

CREATE FUNCTION validate_customer_point_payment_quote() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE rate numeric; computed numeric; available_points bigint;
BEGIN
  IF NEW.status<>'pending' OR NEW.confirmed_at IS NOT NULL OR NEW.decision_command_id IS NOT NULL
    OR NEW.decision_hash IS NOT NULL OR NEW.decided_by_customer_id IS NOT NULL
    OR NEW.expires_at<=clock_timestamp() OR NEW.expires_at>clock_timestamp()+interval '120 seconds' THEN
    RAISE EXCEPTION 'New point payment quote must be pending with a short expiry' USING ERRCODE='23514';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM sales s JOIN customer_sale_links l
      ON l.sale_id=s.id AND l.organization_id=s.organization_id AND l.branch_id=s.branch_id
      WHERE s.id=NEW.sale_id AND s.organization_id=NEW.organization_id AND s.branch_id=NEW.branch_id
        AND l.customer_id=NEW.customer_id) THEN
    RAISE EXCEPTION 'Quote requires the customer linked to this sale' USING ERRCODE='23514';
  END IF;
  SELECT redemption_usd_per_point INTO rate FROM customer_loyalty_programs
    WHERE id=NEW.program_id AND organization_id=NEW.organization_id AND status='active';
  IF rate IS NULL OR rate<=0 OR rate<>NEW.redemption_usd_per_point THEN
    RAISE EXCEPTION 'Quote requires the active point redemption policy' USING ERRCODE='23514';
  END IF;
  computed:=floor(NEW.points::numeric*rate*100)/100;
  IF computed<=0 OR computed<>NEW.amount_usd THEN
    RAISE EXCEPTION 'Quote amount does not match points and approved conversion' USING ERRCODE='23514';
  END IF;
  SELECT coalesce(sum(points_delta),0) INTO available_points FROM customer_points_ledger
    WHERE organization_id=NEW.organization_id AND customer_id=NEW.customer_id;
  IF NEW.points>available_points THEN RAISE EXCEPTION 'Quote exceeds available point balance' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM commercial_credit_charges WHERE sale_id=NEW.sale_id) THEN
    RAISE EXCEPTION 'Points cannot be quoted for a commercial credit sale' USING ERRCODE='23514';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM sale_collection_balances b WHERE b.id=NEW.sale_id
      AND b.organization_id=NEW.organization_id AND b.branch_id=NEW.branch_id
      AND b.outstanding_usd-b.reserved_usd>=NEW.amount_usd) THEN
    RAISE EXCEPTION 'Point quote exceeds the available sale balance' USING ERRCODE='23514';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM cash_sessions cs WHERE cs.id=NEW.cash_session_id
      AND cs.organization_id=NEW.organization_id AND cs.branch_id=NEW.branch_id
      AND cs.cashier_id=NEW.requested_by AND NOT EXISTS(
        SELECT 1 FROM cash_closures cc WHERE cc.session_id=cs.id)) THEN
    RAISE EXCEPTION 'Quote requires the requesting cashier open session' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER customer_point_payment_quote_insert_guard BEFORE INSERT ON customer_point_payment_quotes
  FOR EACH ROW EXECUTE FUNCTION validate_customer_point_payment_quote();

CREATE TABLE customer_point_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  sale_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  quote_id uuid NOT NULL UNIQUE,
  program_id uuid NOT NULL,
  points bigint NOT NULL CHECK(points > 0),
  amount_usd numeric(18,2) NOT NULL CHECK(amount_usd > 0),
  redemption_usd_per_point numeric(12,6) NOT NULL CHECK(redemption_usd_per_point > 0),
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
  confirmed_by_customer boolean NOT NULL DEFAULT true CHECK(confirmed_by_customer),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(sale_id,organization_id,branch_id) REFERENCES sales(id,organization_id,branch_id),
  FOREIGN KEY(customer_id,organization_id) REFERENCES customer_accounts(id,organization_id),
  FOREIGN KEY(quote_id,organization_id,branch_id) REFERENCES customer_point_payment_quotes(id,organization_id,branch_id),
  FOREIGN KEY(program_id,organization_id) REFERENCES customer_loyalty_programs(id,organization_id),
  UNIQUE(organization_id,command_id),
  UNIQUE(id,organization_id,branch_id)
);
CREATE INDEX customer_point_payments_sale_idx ON customer_point_payments(sale_id,created_at,id);

CREATE FUNCTION protect_customer_point_payment_quote() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id OR OLD.branch_id IS DISTINCT FROM NEW.branch_id
    OR OLD.sale_id IS DISTINCT FROM NEW.sale_id OR OLD.customer_id IS DISTINCT FROM NEW.customer_id
    OR OLD.cash_session_id IS DISTINCT FROM NEW.cash_session_id OR OLD.program_id IS DISTINCT FROM NEW.program_id
    OR OLD.points IS DISTINCT FROM NEW.points OR OLD.amount_usd IS DISTINCT FROM NEW.amount_usd
    OR OLD.redemption_usd_per_point IS DISTINCT FROM NEW.redemption_usd_per_point
    OR OLD.expires_at IS DISTINCT FROM NEW.expires_at OR OLD.command_id IS DISTINCT FROM NEW.command_id
    OR OLD.request_hash IS DISTINCT FROM NEW.request_hash OR OLD.requested_by IS DISTINCT FROM NEW.requested_by THEN
    RAISE EXCEPTION 'Point payment quote facts are immutable' USING ERRCODE='55000';
  END IF;
  IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
    OLD.status='pending' AND NEW.status IN('confirmed','declined','expired')
  ) THEN RAISE EXCEPTION 'Invalid point payment quote transition' USING ERRCODE='23514'; END IF;
  IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
      (NEW.status='expired' AND NEW.expires_at<=clock_timestamp() AND NEW.decision_command_id IS NULL
        AND NEW.decision_hash IS NULL AND NEW.decided_by_customer_id IS NULL)
      OR (NEW.status IN('confirmed','declined') AND NEW.decision_command_id IS NOT NULL AND NEW.decision_hash IS NOT NULL
        AND NEW.decided_by_customer_id IS DISTINCT FROM OLD.customer_id)) THEN
    RAISE EXCEPTION 'Point quote decision must be idempotent and made by its customer' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER customer_point_payment_quote_guard BEFORE UPDATE ON customer_point_payment_quotes
  FOR EACH ROW EXECUTE FUNCTION protect_customer_point_payment_quote();

CREATE FUNCTION validate_customer_point_payment() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE q customer_point_payment_quotes%ROWTYPE; s sales%ROWTYPE; balance bigint; available numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||NEW.sale_id::text,0));
  SELECT * INTO q FROM customer_point_payment_quotes WHERE id=NEW.quote_id
    AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id FOR UPDATE;
  SELECT * INTO s FROM sales WHERE id=NEW.sale_id AND organization_id=NEW.organization_id
    AND branch_id=NEW.branch_id FOR UPDATE;
  IF q.id IS NULL OR s.id IS NULL OR q.status<>'pending' OR q.expires_at<=clock_timestamp()
    OR q.sale_id<>NEW.sale_id OR q.customer_id<>NEW.customer_id OR q.program_id<>NEW.program_id
    OR q.points<>NEW.points OR q.amount_usd<>NEW.amount_usd
    OR q.redemption_usd_per_point<>NEW.redemption_usd_per_point THEN
    RAISE EXCEPTION 'Point payment quote is invalid, expired or already used' USING ERRCODE='23514';
  END IF;
  PERFORM 1 FROM customer_accounts WHERE id=NEW.customer_id AND organization_id=NEW.organization_id
    AND status='active' FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM customer_sale_links WHERE sale_id=NEW.sale_id
      AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id AND customer_id=NEW.customer_id) THEN
    RAISE EXCEPTION 'An active linked customer is required' USING ERRCODE='23514';
  END IF;
  SELECT coalesce(sum(points_delta),0) INTO balance FROM customer_points_ledger
    WHERE organization_id=NEW.organization_id AND customer_id=NEW.customer_id;
  IF NEW.points>balance THEN RAISE EXCEPTION 'Insufficient available points' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS(SELECT 1 FROM customer_loyalty_programs WHERE id=NEW.program_id
      AND organization_id=NEW.organization_id AND status='active'
      AND redemption_usd_per_point=NEW.redemption_usd_per_point AND redemption_usd_per_point>0) THEN
    RAISE EXCEPTION 'The approved point redemption policy is no longer active' USING ERRCODE='23514';
  END IF;
  IF EXISTS(SELECT 1 FROM commercial_credit_charges WHERE sale_id=NEW.sale_id) THEN
    RAISE EXCEPTION 'Points cannot be applied to a commercial credit sale' USING ERRCODE='23514';
  END IF;
  SELECT greatest(s.total_usd-coalesce(p.collected,0)-coalesce(p.reserved,0),0) INTO available
    FROM sales s LEFT JOIN LATERAL(
      SELECT coalesce(sum(a.amount_usd) FILTER(WHERE e.outcome='confirmed'),0)
        + coalesce((SELECT sum(al.amount_usd) FROM prepayment_allocations al
          JOIN prepayment_advances adv ON adv.id=al.advance_id
          WHERE al.sale_id=s.id AND adv.tender_kind='captured' AND prepayment_current_outcome(adv.id)='confirmed'),0)
        + coalesce((SELECT sum(cp.amount_usd) FROM customer_point_payments cp WHERE cp.sale_id=s.id),0) AS collected,
        coalesce(sum(a.amount_usd) FILTER(WHERE e.outcome IS NULL OR e.outcome='unknown'),0) AS reserved
      FROM payment_attempts a LEFT JOIN LATERAL(SELECT outcome FROM payment_events WHERE attempt_id=a.id
        ORDER BY (outcome<>'unknown') DESC,created_at DESC,id DESC LIMIT 1)e ON true
      WHERE a.sale_id=s.id AND a.mode='manual'
    )p ON true WHERE s.id=NEW.sale_id;
  IF available IS NULL OR NEW.amount_usd>available THEN
    RAISE EXCEPTION 'Point tender exceeds the sale balance' USING ERRCODE='23514';
  END IF;
  PERFORM 1 FROM cash_sessions cs WHERE cs.id=q.cash_session_id AND cs.organization_id=NEW.organization_id
    AND cs.branch_id=NEW.branch_id AND NOT EXISTS(SELECT 1 FROM cash_closures cc WHERE cc.session_id=cs.id)
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'The cashier session is already closed' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER customer_point_payment_guard BEFORE INSERT ON customer_point_payments
  FOR EACH ROW EXECUTE FUNCTION validate_customer_point_payment();

CREATE FUNCTION protect_customer_point_payment_facts() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'Customer point payment facts are immutable' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER customer_point_payment_immutable BEFORE UPDATE OR DELETE ON customer_point_payments
  FOR EACH ROW EXECUTE FUNCTION protect_customer_point_payment_facts();

CREATE OR REPLACE FUNCTION validate_payment_attempt() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE total numeric; occupied numeric; captured_allocated numeric; points_paid numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||NEW.sale_id::text,0));
  IF EXISTS(SELECT 1 FROM commercial_credit_charges WHERE sale_id=NEW.sale_id) THEN
    RAISE EXCEPTION 'Collect commercial credit through account statement' USING ERRCODE='23514';
  END IF;
  SELECT total_usd INTO total FROM sales WHERE id=NEW.sale_id
    AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
  SELECT coalesce(sum(a.amount_usd),0) INTO occupied FROM payment_attempts a WHERE a.sale_id=NEW.sale_id
    AND NOT EXISTS(SELECT 1 FROM payment_events e WHERE e.attempt_id=a.id AND e.outcome='declined');
  SELECT coalesce(sum(al.amount_usd),0) INTO captured_allocated FROM prepayment_allocations al
    JOIN prepayment_advances adv ON adv.id=al.advance_id WHERE al.sale_id=NEW.sale_id
    AND adv.tender_kind='captured' AND prepayment_current_outcome(adv.id)='confirmed';
  SELECT coalesce(sum(amount_usd),0) INTO points_paid FROM customer_point_payments WHERE sale_id=NEW.sale_id;
  IF total IS NULL OR NEW.amount_usd>total-occupied-captured_allocated-points_paid THEN
    RAISE EXCEPTION 'Payment exceeds unreserved sale balance including points and captured advances' USING ERRCODE='23514';
  END IF;
  PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
  RETURN NEW;
END; $$;

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
  SELECT sum(rr.amount_usd) AS refunded FROM payment_refunds rr JOIN payment_events e ON e.id=rr.payment_event_id
   JOIN payment_attempts a ON a.id=e.attempt_id WHERE a.sale_id=s.id AND a.mode='manual'
 )r ON true LEFT JOIN commercial_credit_charges cc ON cc.sale_id=s.id
 LEFT JOIN commercial_account_statement st ON st.id=cc.id;

CREATE OR REPLACE FUNCTION award_points_for_paid_customer_sale() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE sale_row record; program_row customer_loyalty_programs%ROWTYPE; eligible numeric; points bigint; ledger_command uuid; actor uuid;
BEGIN
  IF TG_TABLE_NAME='payment_events' AND NEW.outcome<>'confirmed' THEN RETURN NEW; END IF;
  IF TG_TABLE_NAME='payment_events' THEN
    SELECT s.id,s.organization_id,s.total_usd,l.customer_id,b.collection_status
      INTO sale_row FROM payment_attempts a JOIN sales s ON s.id=a.sale_id AND s.organization_id=a.organization_id AND s.branch_id=a.branch_id
      JOIN sale_collection_balances b ON b.id=s.id AND b.organization_id=s.organization_id AND b.branch_id=s.branch_id
      JOIN customer_sale_links l ON l.sale_id=s.id AND l.organization_id=s.organization_id AND l.branch_id=s.branch_id
      WHERE a.id=NEW.attempt_id AND a.organization_id=NEW.organization_id AND a.branch_id=NEW.branch_id;
  ELSE
    SELECT s.id,s.organization_id,s.total_usd,l.customer_id,b.collection_status
      INTO sale_row FROM sales s JOIN sale_collection_balances b ON b.id=s.id AND b.organization_id=s.organization_id AND b.branch_id=s.branch_id
      JOIN customer_sale_links l ON l.sale_id=s.id AND l.organization_id=s.organization_id AND l.branch_id=s.branch_id
      WHERE s.id=NEW.sale_id AND s.organization_id=NEW.organization_id AND s.branch_id=NEW.branch_id;
  END IF;
  IF sale_row.id IS NULL OR sale_row.collection_status<>'paid' THEN RETURN NEW; END IF;
  SELECT * INTO program_row FROM customer_loyalty_programs
   WHERE organization_id=sale_row.organization_id AND status='active' ORDER BY version DESC LIMIT 1;
  IF program_row.id IS NULL THEN RETURN NEW; END IF;
  SELECT coalesce(sum(a.amount_usd),0)+coalesce((SELECT sum(al.amount_usd)
    FROM prepayment_allocations al JOIN prepayment_advances adv ON adv.id=al.advance_id
    WHERE al.sale_id=sale_row.id AND adv.tender_kind='captured'
      AND prepayment_current_outcome(adv.id)='confirmed'),0) INTO eligible
    FROM payment_events e JOIN payment_attempts a ON a.id=e.attempt_id
    WHERE a.sale_id=sale_row.id AND a.organization_id=sale_row.organization_id
      AND a.branch_id=sale_row.branch_id AND a.mode='manual' AND a.method IN('cash','card') AND e.outcome='confirmed';
  IF eligible<program_row.minimum_eligible_usd THEN RETURN NEW; END IF;
  points:=floor(eligible*program_row.points_per_eligible_usd)::bigint;
  IF points<=0 THEN RETURN NEW; END IF;
  IF TG_TABLE_NAME='payment_events' THEN
    ledger_command:=NEW.command_id;
    actor:=NEW.created_by;
  ELSE
    ledger_command:=gen_random_uuid();
    actor:=NULL;
  END IF;
  INSERT INTO customer_points_ledger(organization_id,customer_id,program_id,event_type,points_delta,
    source_type,source_id,command_id,reason,expires_at,created_by)
  VALUES(sale_row.organization_id,sale_row.customer_id,program_row.id,'earn',points,'sale',sale_row.id,
    ledger_command,'Puntos por porción pagada en efectivo/tarjeta de una venta',
    CASE WHEN program_row.points_expire_after_days IS NULL THEN NULL ELSE now()+(program_row.points_expire_after_days::text||' days')::interval END,
    actor)
  ON CONFLICT(organization_id,source_type,source_id,event_type) DO NOTHING;
  RETURN NEW;
END; $$;
DROP TRIGGER customer_sale_points_award ON payment_events;
CREATE TRIGGER customer_sale_points_award AFTER INSERT ON payment_events
  FOR EACH ROW EXECUTE FUNCTION award_points_for_paid_customer_sale();
CREATE TRIGGER customer_sale_points_award_from_points AFTER INSERT ON customer_point_payments
  FOR EACH ROW EXECUTE FUNCTION award_points_for_paid_customer_sale();

ALTER TABLE customer_point_payment_quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_point_payments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE customer_point_payment_quotes,customer_point_payments FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT,UPDATE ON TABLE customer_point_payment_quotes TO dlc_api_runtime;
GRANT SELECT,INSERT ON TABLE customer_point_payments,customer_points_ledger TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON customer_point_payment_quotes FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON customer_point_payment_quotes FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_update ON customer_point_payment_quotes FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
CREATE POLICY dlc_api_select ON customer_point_payments FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON customer_point_payments FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_insert ON customer_points_ledger FOR INSERT TO dlc_api_runtime WITH CHECK(true);
GRANT EXECUTE ON FUNCTION validate_payment_attempt(),validate_customer_point_payment(),
  award_points_for_paid_customer_sale() TO dlc_api_runtime;
REVOKE ALL ON FUNCTION protect_customer_point_payment_facts() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION protect_customer_point_payment_quote() FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
