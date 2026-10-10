-- A reported transfer is evidence, not settled money until a second person verifies it.
CREATE TABLE commercial_bank_verifications (
 receipt_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 outcome text NOT NULL CHECK(outcome IN('confirmed','rejected')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 verified_by uuid NOT NULL,verified_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(receipt_id,organization_id,branch_id) REFERENCES commercial_credit_receipts(id,organization_id,branch_id),
 FOREIGN KEY(verified_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id)
);
CREATE FUNCTION guard_commercial_bank_verification() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE r commercial_credit_receipts%ROWTYPE;
BEGIN
 SELECT * INTO r FROM commercial_credit_receipts WHERE id=NEW.receipt_id;
 IF r.id IS NULL OR r.organization_id<>NEW.organization_id OR r.branch_id<>NEW.branch_id
  OR r.method<>'bank_reported' OR r.recorded_by=NEW.verified_by
  OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.verified_by AND organization_id=NEW.organization_id AND status='active')
 THEN RAISE EXCEPTION 'Independent transfer verification required' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER commercial_bank_guard BEFORE INSERT ON commercial_bank_verifications
 FOR EACH ROW EXECUTE FUNCTION guard_commercial_bank_verification();
CREATE OR REPLACE FUNCTION guard_credit_receipt() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE charge commercial_credit_charges%ROWTYPE; paid numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('credit-charge:'||NEW.charge_id,0));
 SELECT * INTO charge FROM commercial_credit_charges WHERE id=NEW.charge_id;
 SELECT coalesce(sum(r.amount_usd) FILTER(WHERE v.outcome IS DISTINCT FROM 'rejected'),0) INTO paid
 FROM commercial_credit_receipts r LEFT JOIN commercial_bank_verifications v ON v.receipt_id=r.id
 WHERE r.charge_id=NEW.charge_id;
 IF charge.id IS NULL OR charge.organization_id<>NEW.organization_id OR charge.branch_id<>NEW.branch_id
  OR NEW.amount_usd>charge.amount_usd-paid THEN RAISE EXCEPTION 'Credit receipt exceeds outstanding or pending balance' USING ERRCODE='23514'; END IF;
 IF NEW.method='cash' THEN PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.recorded_by,NEW.organization_id,NEW.branch_id); END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE VIEW commercial_account_statement WITH(security_invoker=true) AS
 SELECT c.id,c.organization_id,c.branch_id,c.customer_id,c.sale_id,c.amount_usd,c.due_on,c.charged_at,
  coalesce(sum(r.amount_usd) FILTER(WHERE r.method='cash' OR v.outcome='confirmed'),0)::numeric(18,2) AS received_usd,
  (c.amount_usd-coalesce(sum(r.amount_usd) FILTER(WHERE r.method='cash' OR v.outcome='confirmed'),0))::numeric(18,2) AS outstanding_usd,
  coalesce(sum(r.amount_usd) FILTER(WHERE r.method='bank_reported' AND v.receipt_id IS NULL),0)::numeric(18,2) AS pending_bank_usd
 FROM commercial_credit_charges c LEFT JOIN commercial_credit_receipts r ON r.charge_id=c.id
 LEFT JOIN commercial_bank_verifications v ON v.receipt_id=r.id GROUP BY c.id;
CREATE OR REPLACE VIEW sale_collection_balances WITH(security_invoker=true) AS
 SELECT s.id,s.organization_id,s.branch_id,
  CASE WHEN coalesce(p.collected,0)>=s.total_usd OR cc.id IS NOT NULL AND st.outstanding_usd=0 THEN 'paid'
   WHEN cc.id IS NOT NULL THEN 'on_credit' ELSE 'pending_collection' END AS collection_status,
  coalesce(p.collected,0) AS collected_usd,coalesce(p.reserved,0) AS reserved_usd,
  greatest(s.total_usd-coalesce(p.collected,0)-coalesce(cc.amount_usd,0),0) AS outstanding_usd,
  coalesce(r.refunded,0) AS refunded_usd,
  CASE WHEN coalesce(r.refunded,0)=0 THEN 'none' WHEN r.refunded>=p.collected THEN 'refunded' ELSE 'partial' END AS refund_status
 FROM sales s LEFT JOIN LATERAL(
  SELECT sum(a.amount_usd) FILTER(WHERE e.outcome='confirmed') AS collected,
   sum(a.amount_usd) FILTER(WHERE e.outcome IS NULL OR e.outcome='unknown') AS reserved
  FROM payment_attempts a LEFT JOIN LATERAL(SELECT outcome FROM payment_events WHERE attempt_id=a.id
   ORDER BY (outcome<>'unknown') DESC,created_at DESC,id DESC LIMIT 1)e ON true
  WHERE a.sale_id=s.id AND a.mode='manual'
 ) p ON true LEFT JOIN LATERAL(
  SELECT sum(rr.amount_usd) AS refunded FROM payment_refunds rr JOIN payment_events e ON e.id=rr.payment_event_id
   JOIN payment_attempts a ON a.id=e.attempt_id WHERE a.sale_id=s.id AND a.mode='manual'
 )r ON true LEFT JOIN commercial_credit_charges cc ON cc.sale_id=s.id
 LEFT JOIN commercial_account_statement st ON st.id=cc.id;
ALTER TABLE commercial_bank_verifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON commercial_bank_verifications FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON commercial_bank_verifications TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON commercial_bank_verifications FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON commercial_bank_verifications FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE TRIGGER credit_fact_immutable BEFORE UPDATE OR DELETE ON commercial_bank_verifications
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION guard_commercial_bank_verification() FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO permissions(code,description) VALUES('credit.bank.verify','Confirmar o rechazar transferencia comercial') ON CONFLICT(code) DO NOTHING;
