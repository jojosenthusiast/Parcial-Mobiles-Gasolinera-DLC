-- Explicit opt-in commercial accounts. A credit charge references an existing sale,
-- and an installment never creates another sale.
CREATE TABLE commercial_customers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL REFERENCES organizations(id),
 code text NOT NULL CHECK(code~'^[A-Z0-9_-]{2,30}$'),legal_name text NOT NULL CHECK(length(btrim(legal_name)) BETWEEN 3 AND 160),
 tax_reference text,credit_limit_usd numeric(18,2) NOT NULL CHECK(credit_limit_usd>0),
 terms_days integer NOT NULL CHECK(terms_days BETWEEN 1 AND 120),
 active boolean NOT NULL DEFAULT false,created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,code),UNIQUE(id,organization_id)
);
CREATE TABLE commercial_customer_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,customer_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN('activate','suspend','limit','terms')),
 new_limit_usd numeric(18,2),new_terms_days integer,reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 changed_by uuid NOT NULL,changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(customer_id,organization_id) REFERENCES commercial_customers(id,organization_id),
 FOREIGN KEY(changed_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id)
);
CREATE TABLE commercial_authorized_buyers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,customer_id uuid NOT NULL,
 buyer_code text NOT NULL CHECK(buyer_code~'^[A-Z0-9_-]{2,30}$'),
 full_name text NOT NULL CHECK(length(btrim(full_name)) BETWEEN 3 AND 160),
 active boolean NOT NULL DEFAULT true,created_by uuid NOT NULL,
 FOREIGN KEY(customer_id,organization_id) REFERENCES commercial_customers(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(customer_id,buyer_code),UNIQUE(id,customer_id)
);
CREATE TABLE commercial_credit_charges (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 customer_id uuid NOT NULL,buyer_id uuid NOT NULL,sale_id uuid NOT NULL UNIQUE,
 amount_usd numeric(18,2) NOT NULL CHECK(amount_usd>0),due_on date NOT NULL,
 buyer_evidence text NOT NULL CHECK(length(btrim(buyer_evidence)) BETWEEN 5 AND 200),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 charged_by uuid NOT NULL,charged_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(customer_id,organization_id) REFERENCES commercial_customers(id,organization_id),
 FOREIGN KEY(buyer_id,customer_id) REFERENCES commercial_authorized_buyers(id,customer_id),
 FOREIGN KEY(sale_id,organization_id,branch_id) REFERENCES sales(id,organization_id,branch_id),
 FOREIGN KEY(charged_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id),UNIQUE(id,organization_id,branch_id)
);
CREATE TABLE commercial_credit_receipts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 charge_id uuid NOT NULL,amount_usd numeric(18,2) NOT NULL CHECK(amount_usd>0),
 method text NOT NULL CHECK(method IN('cash','bank_reported')),cash_session_id uuid,
 evidence_reference text NOT NULL CHECK(length(btrim(evidence_reference)) BETWEEN 5 AND 200),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 recorded_by uuid NOT NULL,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(charge_id,organization_id,branch_id) REFERENCES commercial_credit_charges(id,organization_id,branch_id),
 FOREIGN KEY(cash_session_id,organization_id,branch_id) REFERENCES cash_sessions(id,organization_id,branch_id),
 FOREIGN KEY(recorded_by,organization_id) REFERENCES users(id,organization_id),
 CHECK((method='cash' AND cash_session_id IS NOT NULL) OR (method='bank_reported' AND cash_session_id IS NULL)),
 UNIQUE(organization_id,command_id),UNIQUE(organization_id,evidence_reference),UNIQUE(id,organization_id,branch_id)
);
CREATE FUNCTION apply_commercial_customer_event() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE c commercial_customers%ROWTYPE; outstanding numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('commercial-customer:'||NEW.customer_id,0));
 SELECT * INTO c FROM commercial_customers WHERE id=NEW.customer_id;
 IF c.id IS NULL OR c.organization_id<>NEW.organization_id OR c.created_by=NEW.changed_by
  OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.changed_by AND organization_id=NEW.organization_id AND status='active')
 THEN RAISE EXCEPTION 'Independent account configuration required' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(s.outstanding_usd),0) INTO outstanding FROM commercial_account_statement s WHERE s.customer_id=c.id;
 IF NEW.kind='activate' THEN
  IF c.active OR NEW.new_limit_usd IS NOT NULL OR NEW.new_terms_days IS NOT NULL THEN RAISE EXCEPTION 'Invalid activation' USING ERRCODE='23514'; END IF;
  UPDATE commercial_customers SET active=true WHERE id=c.id;
 ELSIF NEW.kind='suspend' THEN
  IF NOT c.active OR NEW.new_limit_usd IS NOT NULL OR NEW.new_terms_days IS NOT NULL THEN RAISE EXCEPTION 'Invalid suspension' USING ERRCODE='23514'; END IF;
  UPDATE commercial_customers SET active=false WHERE id=c.id;
 ELSIF NEW.kind='limit' THEN
  IF NEW.new_limit_usd IS NULL OR NEW.new_limit_usd<=0 OR NEW.new_limit_usd<outstanding OR NEW.new_terms_days IS NOT NULL
  THEN RAISE EXCEPTION 'Limit below outstanding balance' USING ERRCODE='23514'; END IF;
  UPDATE commercial_customers SET credit_limit_usd=NEW.new_limit_usd WHERE id=c.id;
 ELSE
  IF NEW.new_terms_days NOT BETWEEN 1 AND 120 OR NEW.new_limit_usd IS NOT NULL THEN RAISE EXCEPTION 'Invalid terms' USING ERRCODE='23514'; END IF;
  UPDATE commercial_customers SET terms_days=NEW.new_terms_days WHERE id=c.id;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER commercial_customer_event_apply BEFORE INSERT ON commercial_customer_events
 FOR EACH ROW EXECUTE FUNCTION apply_commercial_customer_event();
CREATE FUNCTION guard_credit_charge() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE customer commercial_customers%ROWTYPE; sale sales%ROWTYPE; outstanding numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||NEW.sale_id,0));
 PERFORM pg_advisory_xact_lock(hashtextextended('commercial-customer:'||NEW.customer_id,0));
 SELECT * INTO customer FROM commercial_customers WHERE id=NEW.customer_id;
 SELECT * INTO sale FROM sales WHERE id=NEW.sale_id;
 IF customer.id IS NULL OR customer.organization_id<>NEW.organization_id OR NOT customer.active
  OR sale.id IS NULL OR sale.organization_id<>NEW.organization_id OR sale.branch_id<>NEW.branch_id
  OR sale.total_usd IS DISTINCT FROM NEW.amount_usd
  OR NOT EXISTS(SELECT 1 FROM commercial_authorized_buyers b WHERE b.id=NEW.buyer_id
     AND b.customer_id=customer.id AND b.active)
  OR EXISTS(SELECT 1 FROM payment_attempts WHERE sale_id=NEW.sale_id)
  OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.charged_by AND organization_id=NEW.organization_id AND status='active')
 THEN RAISE EXCEPTION 'Credit requires active customer, authorized buyer and unpaid sale' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(x.amount_usd-coalesce(r.paid,0)),0) INTO outstanding
 FROM commercial_credit_charges x LEFT JOIN LATERAL
  (SELECT sum(amount_usd) AS paid FROM commercial_credit_receipts WHERE charge_id=x.id) r ON true
 WHERE x.customer_id=customer.id;
 IF outstanding+NEW.amount_usd>customer.credit_limit_usd
  OR NEW.due_on<>(sale.occurred_at AT TIME ZONE 'America/El_Salvador')::date+customer.terms_days
 THEN RAISE EXCEPTION 'Credit limit or due date exceeded' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER credit_charge_guard BEFORE INSERT ON commercial_credit_charges FOR EACH ROW EXECUTE FUNCTION guard_credit_charge();
CREATE FUNCTION guard_credit_receipt() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE charge commercial_credit_charges%ROWTYPE; paid numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('credit-charge:'||NEW.charge_id,0));
 SELECT * INTO charge FROM commercial_credit_charges WHERE id=NEW.charge_id;
 SELECT coalesce(sum(amount_usd),0) INTO paid FROM commercial_credit_receipts WHERE charge_id=NEW.charge_id;
 IF charge.id IS NULL OR charge.organization_id<>NEW.organization_id OR charge.branch_id<>NEW.branch_id
  OR NEW.amount_usd>charge.amount_usd-paid THEN RAISE EXCEPTION 'Credit receipt exceeds outstanding balance' USING ERRCODE='23514'; END IF;
 IF NEW.method='cash' THEN PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.recorded_by,NEW.organization_id,NEW.branch_id); END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER credit_receipt_guard BEFORE INSERT ON commercial_credit_receipts FOR EACH ROW EXECUTE FUNCTION guard_credit_receipt();
ALTER TABLE cash_movements ADD COLUMN credit_receipt_id uuid UNIQUE,
 ADD CONSTRAINT cash_credit_receipt_fk FOREIGN KEY(credit_receipt_id,organization_id,branch_id)
  REFERENCES commercial_credit_receipts(id,organization_id,branch_id),
 ADD CONSTRAINT cash_credit_receipt_kind CHECK(credit_receipt_id IS NULL OR (kind='cash_in' AND payment_event_id IS NULL AND refund_id IS NULL));
CREATE FUNCTION post_credit_cash() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.method='cash' THEN
  INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,reason,command_id,request_hash,created_by,correlation_id,credit_receipt_id)
  VALUES(NEW.organization_id,NEW.branch_id,NEW.cash_session_id,'cash_in',NEW.amount_usd,
   'Abono de cuenta comercial '||NEW.charge_id,gen_random_uuid(),NEW.request_hash,NEW.recorded_by,NEW.correlation_id,NEW.id);
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER credit_cash_post AFTER INSERT ON commercial_credit_receipts FOR EACH ROW EXECUTE FUNCTION post_credit_cash();
-- The normal POS collection endpoint must not collect an invoice already assigned to credit.
CREATE OR REPLACE FUNCTION validate_payment_attempt() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE total numeric; occupied numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||NEW.sale_id::text,0));
 IF EXISTS(SELECT 1 FROM commercial_credit_charges WHERE sale_id=NEW.sale_id) THEN
  RAISE EXCEPTION 'Collect commercial credit through account statement' USING ERRCODE='23514'; END IF;
 SELECT total_usd INTO total FROM sales WHERE id=NEW.sale_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 SELECT coalesce(sum(a.amount_usd),0) INTO occupied FROM payment_attempts a WHERE a.sale_id=NEW.sale_id
  AND NOT EXISTS(SELECT 1 FROM payment_events e WHERE e.attempt_id=a.id AND e.outcome='declined');
 IF total IS NULL OR NEW.amount_usd>total-occupied THEN RAISE EXCEPTION 'Payment exceeds unreserved sale balance' USING ERRCODE='23514'; END IF;
 PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
 RETURN NEW;
END $$;
CREATE OR REPLACE VIEW sale_collection_balances WITH(security_invoker=true) AS
 SELECT s.id,s.organization_id,s.branch_id,
  CASE WHEN coalesce(p.collected,0)>=s.total_usd THEN 'paid'
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
 )r ON true LEFT JOIN commercial_credit_charges cc ON cc.sale_id=s.id;
CREATE VIEW commercial_account_statement WITH(security_invoker=true) AS
 SELECT c.id,c.organization_id,c.branch_id,c.customer_id,c.sale_id,c.amount_usd,c.due_on,c.charged_at,
  coalesce(sum(r.amount_usd),0)::numeric(18,2) AS received_usd,
  (c.amount_usd-coalesce(sum(r.amount_usd),0))::numeric(18,2) AS outstanding_usd
 FROM commercial_credit_charges c LEFT JOIN commercial_credit_receipts r ON r.charge_id=c.id GROUP BY c.id;
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['commercial_customers','commercial_customer_events','commercial_authorized_buyers','commercial_credit_charges','commercial_credit_receipts'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('REVOKE ALL ON %I FROM PUBLIC,anon,authenticated,service_role',tab);
  EXECUTE format('GRANT SELECT,INSERT ON %I TO dlc_api_runtime',tab);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',tab);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',tab);
  IF tab<>'commercial_customers' THEN
   EXECUTE format('CREATE TRIGGER credit_fact_immutable BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',tab);
  END IF;
 END LOOP;
END $$;
REVOKE ALL ON commercial_account_statement FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON commercial_account_statement TO dlc_api_runtime;
REVOKE ALL ON FUNCTION apply_commercial_customer_event(),guard_credit_charge(),guard_credit_receipt(),post_credit_cash() FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO permissions(code,description) VALUES
 ('credit.customer.manage','Administrar cuentas comerciales'),
 ('credit.sale.charge','Cargar venta a cuenta'),
 ('credit.receipt.record','Registrar abonos comerciales'),
 ('credit.statement.read','Consultar saldos comerciales') ON CONFLICT(code) DO NOTHING;
