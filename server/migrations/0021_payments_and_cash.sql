-- Internal payment records. Manual card confirmation needs documentary evidence;
-- simulated events are explicitly labelled and are not processor settlements.
CREATE TABLE cash_registers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Z0-9_-]{1,30}$'), created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(branch_id,code), UNIQUE(id,organization_id,branch_id)
);
CREATE TABLE cash_sessions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 register_id uuid NOT NULL, cashier_id uuid NOT NULL, opening_usd numeric NOT NULL CHECK(opening_usd>=0 AND opening_usd<1000000000 AND scale(opening_usd)<=2),
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(register_id,organization_id,branch_id) REFERENCES cash_registers(id,organization_id,branch_id),
 FOREIGN KEY(cashier_id,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id), UNIQUE(id,organization_id,branch_id)
);
CREATE TABLE payment_attempts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, sale_id uuid NOT NULL,
 method text NOT NULL CHECK(method IN('cash','card')), mode text NOT NULL CHECK(mode IN('manual','simulated')),
 amount_usd numeric NOT NULL CHECK(amount_usd>0 AND amount_usd<1000000000 AND scale(amount_usd)<=2), cash_session_id uuid NOT NULL,
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(sale_id,organization_id,branch_id) REFERENCES sales(id,organization_id,branch_id),
 FOREIGN KEY(cash_session_id,organization_id,branch_id) REFERENCES cash_sessions(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(method<>'cash' OR mode='manual'),
 UNIQUE(organization_id,command_id), UNIQUE(id,organization_id,branch_id)
);
CREATE TABLE payment_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, attempt_id uuid NOT NULL,
 outcome text NOT NULL CHECK(outcome IN('confirmed','declined','unknown')), evidence_reference text,
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(attempt_id,organization_id,branch_id) REFERENCES payment_attempts(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(evidence_reference IS NULL OR length(btrim(evidence_reference)) BETWEEN 1 AND 200),
 UNIQUE(organization_id,command_id), UNIQUE(id,organization_id,branch_id)
);
CREATE UNIQUE INDEX payment_one_terminal_idx ON payment_events(attempt_id) WHERE outcome IN('confirmed','declined');
CREATE UNIQUE INDEX payment_one_unknown_idx ON payment_events(attempt_id) WHERE outcome='unknown';
-- References must identify terminal/provider + transaction, not a card number.
CREATE UNIQUE INDEX payment_confirmation_source_idx ON payment_events(organization_id,evidence_reference) WHERE outcome='confirmed' AND evidence_reference IS NOT NULL;
-- Refunds are financial corrections only: no fuel/stock movement is created.
CREATE TABLE payment_refunds (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, payment_event_id uuid NOT NULL, approval_id uuid NOT NULL UNIQUE REFERENCES approval_requests(id),
 amount_usd numeric NOT NULL CHECK(amount_usd>0 AND amount_usd<1000000000 AND scale(amount_usd)<=2), cash_session_id uuid NOT NULL, evidence_reference text,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 300),
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(payment_event_id,organization_id,branch_id) REFERENCES payment_events(id,organization_id,branch_id),
 FOREIGN KEY(cash_session_id,organization_id,branch_id) REFERENCES cash_sessions(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(evidence_reference IS NULL OR length(btrim(evidence_reference)) BETWEEN 1 AND 200),
 UNIQUE(organization_id,command_id), UNIQUE(id,organization_id,branch_id)
);
CREATE UNIQUE INDEX payment_refund_source_idx ON payment_refunds(organization_id,evidence_reference) WHERE evidence_reference IS NOT NULL;
CREATE TABLE cash_movements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, session_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN('collection','refund','deposit','cash_in','withdrawal')),
 delta_usd numeric NOT NULL CHECK(delta_usd<>0 AND abs(delta_usd)<1000000000 AND scale(delta_usd)<=2), payment_event_id uuid UNIQUE, refund_id uuid UNIQUE,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 300),
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(session_id,organization_id,branch_id) REFERENCES cash_sessions(id,organization_id,branch_id),
 FOREIGN KEY(payment_event_id,organization_id,branch_id) REFERENCES payment_events(id,organization_id,branch_id),
 FOREIGN KEY(refund_id,organization_id,branch_id) REFERENCES payment_refunds(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 CHECK((kind='collection' AND delta_usd>0 AND payment_event_id IS NOT NULL AND refund_id IS NULL)
 OR (kind='refund' AND delta_usd<0 AND refund_id IS NOT NULL AND payment_event_id IS NULL)
 OR (kind='cash_in' AND delta_usd>0 AND payment_event_id IS NULL AND refund_id IS NULL)
 OR (kind IN('deposit','withdrawal') AND delta_usd<0 AND payment_event_id IS NULL AND refund_id IS NULL)),
 UNIQUE(organization_id,command_id)
);
CREATE TABLE cash_closures (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, session_id uuid NOT NULL UNIQUE,
 counted_cash_usd numeric NOT NULL CHECK(counted_cash_usd>=0 AND counted_cash_usd<1000000000 AND scale(counted_cash_usd)<=2), expected_cash_usd numeric(18,2) NOT NULL,
 settled_card_usd numeric NOT NULL CHECK(abs(settled_card_usd)<1000000000 AND scale(settled_card_usd)<=2), expected_card_usd numeric(18,2) NOT NULL,
 variance_cash_usd numeric(18,2) NOT NULL, variance_card_usd numeric(18,2) NOT NULL,
 review_status text NOT NULL CHECK(review_status IN('balanced','pending_review')), reason text,
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(session_id,organization_id,branch_id) REFERENCES cash_sessions(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(reason IS NULL OR length(btrim(reason)) BETWEEN 1 AND 300),
 UNIQUE(organization_id,command_id)
);
CREATE INDEX cash_sessions_register_idx ON cash_sessions(register_id,created_at DESC);
CREATE INDEX payment_attempts_sale_idx ON payment_attempts(sale_id);
CREATE INDEX payment_attempts_cash_idx ON payment_attempts(cash_session_id) WHERE cash_session_id IS NOT NULL;
CREATE INDEX payment_events_attempt_idx ON payment_events(attempt_id,created_at,id);
CREATE INDEX payment_refunds_payment_idx ON payment_refunds(payment_event_id);
CREATE INDEX cash_movements_session_idx ON cash_movements(session_id,created_at,id);

CREATE FUNCTION lock_owned_open_cash(session uuid, actor uuid, org uuid, branch uuid) RETURNS void
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('cash-session:'||session::text,0));
 IF NOT EXISTS(SELECT 1 FROM cash_sessions c WHERE c.id=session AND c.organization_id=org AND c.branch_id=branch AND c.cashier_id=actor)
 OR EXISTS(SELECT 1 FROM cash_closures WHERE session_id=session) THEN
  RAISE EXCEPTION 'Cash session must be open and owned by actor' USING ERRCODE='23514';
 END IF;
END; $$;

CREATE FUNCTION validate_payment_attempt() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE total numeric; occupied numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||NEW.sale_id::text,0));
 SELECT total_usd INTO total FROM sales WHERE id=NEW.sale_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 -- Pending/unknown attempts reserve the amount. Declined attempts release it;
 -- refunds do not reopen debt or authorize collecting the same sale again.
 SELECT coalesce(sum(a.amount_usd),0) INTO occupied FROM payment_attempts a WHERE a.sale_id=NEW.sale_id
  AND NOT EXISTS(SELECT 1 FROM payment_events e WHERE e.attempt_id=a.id AND e.outcome='declined');
 IF total IS NULL OR NEW.amount_usd>total-occupied THEN RAISE EXCEPTION 'Payment exceeds unreserved sale balance' USING ERRCODE='23514'; END IF;
 PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
 RETURN NEW;
END; $$;
CREATE TRIGGER payment_attempt_guard BEFORE INSERT ON payment_attempts FOR EACH ROW EXECUTE FUNCTION validate_payment_attempt();

CREATE FUNCTION validate_payment_event() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a payment_attempts%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('payment-attempt:'||NEW.attempt_id::text,0));
 SELECT * INTO a FROM payment_attempts WHERE id=NEW.attempt_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 IF a.id IS NULL OR a.created_by<>NEW.created_by OR EXISTS(SELECT 1 FROM payment_events WHERE attempt_id=a.id AND outcome IN('confirmed','declined')) THEN
  RAISE EXCEPTION 'Payment attempt is terminal, absent or belongs to another actor' USING ERRCODE='23514';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||a.sale_id::text,0));
 PERFORM lock_owned_open_cash(a.cash_session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
 IF a.method='cash' THEN
  IF NEW.outcome<>'confirmed' THEN RAISE EXCEPTION 'Cash must be confirmed by its cashier' USING ERRCODE='23514'; END IF;
 ELSIF NEW.outcome IN('confirmed','declined') AND NEW.evidence_reference IS NULL THEN
  RAISE EXCEPTION 'Card terminal result requires evidence' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER payment_event_guard BEFORE INSERT ON payment_events FOR EACH ROW EXECUTE FUNCTION validate_payment_event();

CREATE FUNCTION validate_payment_refund() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE e payment_events%ROWTYPE; a payment_attempts%ROWTYPE; refunded numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('refund-payment:'||NEW.payment_event_id::text,0));
 SELECT * INTO e FROM payment_events WHERE id=NEW.payment_event_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id AND outcome='confirmed';
 SELECT * INTO a FROM payment_attempts WHERE id=e.attempt_id;
 SELECT coalesce(sum(amount_usd),0) INTO refunded FROM payment_refunds WHERE payment_event_id=e.id;
 IF e.id IS NULL OR NEW.amount_usd>a.amount_usd-refunded THEN RAISE EXCEPTION 'Refund exceeds original net payment' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM approval_requests q WHERE q.id=NEW.approval_id AND q.organization_id=NEW.organization_id AND q.branch_id=NEW.branch_id
  AND q.action='sale.refund.approve' AND q.entity_type='payment_refund' AND q.entity_id=NEW.payment_event_id::text AND q.status='approved'
  AND q.requested_by=NEW.created_by AND q.decided_by<>NEW.created_by
  AND q.payload->>'amountUsd'=NEW.amount_usd::text AND q.payload->>'reason'=NEW.reason) THEN
  RAISE EXCEPTION 'Refund needs matching approval from another actor' USING ERRCODE='23514'; END IF;
 PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
 IF a.method='card' AND NEW.evidence_reference IS NULL THEN RAISE EXCEPTION 'Card refund requires original-method evidence, not cash' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER payment_refund_guard BEFORE INSERT ON payment_refunds FOR EACH ROW EXECUTE FUNCTION validate_payment_refund();

CREATE FUNCTION validate_cash_entry() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c cash_sessions%ROWTYPE; p record; r record; expected numeric; card_expected numeric;
BEGIN
 IF TG_TABLE_NAME='cash_sessions' THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('cash-register:'||NEW.register_id::text,0));
  IF EXISTS(SELECT 1 FROM cash_sessions s WHERE s.register_id=NEW.register_id AND NOT EXISTS(SELECT 1 FROM cash_closures WHERE session_id=s.id)) THEN
   RAISE EXCEPTION 'Register already has an open session' USING ERRCODE='23514';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM branches WHERE id=NEW.branch_id AND organization_id=NEW.organization_id AND status='active') THEN
   RAISE EXCEPTION 'Cash requires an active branch' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
 END IF;
 PERFORM lock_owned_open_cash(NEW.session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
 SELECT * INTO c FROM cash_sessions WHERE id=NEW.session_id;
 SELECT c.opening_usd+coalesce(sum(delta_usd),0) INTO expected FROM cash_movements WHERE session_id=c.id;
 IF TG_TABLE_NAME='cash_movements' THEN
  IF NEW.kind='collection' THEN
   SELECT a.*,e.outcome,e.created_by AS event_actor INTO p FROM payment_events e JOIN payment_attempts a ON a.id=e.attempt_id WHERE e.id=NEW.payment_event_id;
   IF p.outcome IS DISTINCT FROM 'confirmed' OR p.method IS DISTINCT FROM 'cash' OR p.cash_session_id IS DISTINCT FROM c.id
    OR NEW.delta_usd IS DISTINCT FROM p.amount_usd OR NEW.created_by IS DISTINCT FROM p.event_actor THEN
    RAISE EXCEPTION 'Cash collection must match confirmed payment' USING ERRCODE='23514'; END IF;
  ELSIF NEW.kind='refund' THEN
   SELECT r0.*,a.method INTO r FROM payment_refunds r0 JOIN payment_events e ON e.id=r0.payment_event_id JOIN payment_attempts a ON a.id=e.attempt_id WHERE r0.id=NEW.refund_id;
   IF r.method IS DISTINCT FROM 'cash' OR r.cash_session_id IS DISTINCT FROM c.id OR NEW.delta_usd IS DISTINCT FROM -r.amount_usd OR NEW.created_by IS DISTINCT FROM r.created_by THEN
    RAISE EXCEPTION 'Cash refund must match original refund' USING ERRCODE='23514'; END IF;
  END IF;
  IF expected+NEW.delta_usd<0 THEN RAISE EXCEPTION 'Cash outflow exceeds expected cash' USING ERRCODE='23514'; END IF;
 ELSE
  -- Only real manual card confirmations collected by this cashier during this
  -- session. Simulator traffic is never treated as settled money.
  SELECT coalesce(sum(a.amount_usd),0) INTO card_expected FROM payment_events e JOIN payment_attempts a ON a.id=e.attempt_id
  WHERE e.outcome='confirmed' AND a.method='card' AND a.mode='manual' AND a.cash_session_id=c.id;
  card_expected:=card_expected-(SELECT coalesce(sum(rr.amount_usd),0) FROM payment_refunds rr
   JOIN payment_events e ON e.id=rr.payment_event_id JOIN payment_attempts a ON a.id=e.attempt_id
   WHERE rr.cash_session_id=c.id AND a.method='card' AND a.mode='manual');
  NEW.expected_cash_usd:=expected; NEW.expected_card_usd:=card_expected;
  NEW.variance_cash_usd:=NEW.counted_cash_usd-expected; NEW.variance_card_usd:=NEW.settled_card_usd-card_expected;
  NEW.review_status:=CASE WHEN NEW.variance_cash_usd=0 AND NEW.variance_card_usd=0 THEN 'balanced' ELSE 'pending_review' END;
  IF NEW.review_status='pending_review' AND NEW.reason IS NULL THEN RAISE EXCEPTION 'Discrepancy needs a reason and review' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM payment_attempts a WHERE a.cash_session_id=c.id AND NOT EXISTS(SELECT 1 FROM payment_events WHERE attempt_id=a.id AND outcome IN('confirmed','declined'))) THEN
   RAISE EXCEPTION 'Resolve pending cash attempts before closure' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER cash_session_guard BEFORE INSERT ON cash_sessions FOR EACH ROW EXECUTE FUNCTION validate_cash_entry();
CREATE TRIGGER cash_movement_guard BEFORE INSERT ON cash_movements FOR EACH ROW EXECUTE FUNCTION validate_cash_entry();
CREATE TRIGGER cash_closure_guard BEFORE INSERT ON cash_closures FOR EACH ROW EXECUTE FUNCTION validate_cash_entry();

CREATE FUNCTION post_payment_cash_movement() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a payment_attempts%ROWTYPE;
BEGIN
 IF TG_TABLE_NAME='payment_events' THEN
  SELECT * INTO a FROM payment_attempts WHERE id=NEW.attempt_id;
  IF NEW.outcome='confirmed' AND a.method='cash' THEN
   INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,payment_event_id,reason,command_id,request_hash,created_by,correlation_id)
   VALUES(NEW.organization_id,NEW.branch_id,a.cash_session_id,'collection',a.amount_usd,NEW.id,'Cobro de venta',NEW.id,NEW.request_hash,NEW.created_by,NEW.correlation_id);
  END IF;
 ELSE
  SELECT a0.* INTO a FROM payment_events e JOIN payment_attempts a0 ON a0.id=e.attempt_id WHERE e.id=NEW.payment_event_id;
  IF a.method='cash' THEN
  INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,refund_id,reason,command_id,request_hash,created_by,correlation_id)
  VALUES(NEW.organization_id,NEW.branch_id,NEW.cash_session_id,'refund',-NEW.amount_usd,NEW.id,NEW.reason,NEW.id,NEW.request_hash,NEW.created_by,NEW.correlation_id);
  END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER payment_cash_post AFTER INSERT ON payment_events FOR EACH ROW EXECUTE FUNCTION post_payment_cash_movement();
CREATE TRIGGER refund_cash_post AFTER INSERT ON payment_refunds FOR EACH ROW EXECUTE FUNCTION post_payment_cash_movement();

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['cash_registers','cash_sessions','payment_attempts','payment_events','payment_refunds','cash_movements','cash_closures'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
  EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',t||'_immutable',t);
 END LOOP;
END; $$;
REVOKE ALL ON FUNCTION lock_owned_open_cash(uuid,uuid,uuid,uuid),validate_payment_attempt(),validate_payment_event(),validate_payment_refund(),validate_cash_entry(),post_payment_cash_movement() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION lock_owned_open_cash(uuid,uuid,uuid,uuid) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES('payment.collect','Registrar cobro autorizado'),('payment.read','Consultar cobros'),('payment.resolve','Conciliar cobro con evidencia'),
 ('payment.refund','Ejecutar devolución autorizada de pago'),('cash.read','Consultar caja'),('cash.register.manage','Crear cajas'),('cash.move','Registrar entrada, retiro y depósito') ON CONFLICT(code) DO NOTHING;

CREATE VIEW sale_collection_balances WITH(security_invoker=true) AS
 SELECT s.id,s.organization_id,s.branch_id,
  CASE WHEN coalesce(p.collected,0)>=s.total_usd THEN 'paid' ELSE 'pending_collection' END AS collection_status,
  coalesce(p.collected,0) AS collected_usd,coalesce(p.reserved,0) AS reserved_usd,
  greatest(s.total_usd-coalesce(p.collected,0),0) AS outstanding_usd,
  coalesce(r.refunded,0) AS refunded_usd,
  CASE WHEN coalesce(r.refunded,0)=0 THEN 'none' WHEN r.refunded>=p.collected THEN 'refunded' ELSE 'partial' END AS refund_status
 FROM sales s LEFT JOIN LATERAL(
  SELECT sum(a.amount_usd) FILTER(WHERE e.outcome='confirmed') AS collected,
   sum(a.amount_usd) FILTER(WHERE e.outcome IS NULL OR e.outcome='unknown') AS reserved
  FROM payment_attempts a LEFT JOIN LATERAL(SELECT outcome FROM payment_events WHERE attempt_id=a.id
   ORDER BY (outcome<>'unknown') DESC,created_at DESC,id DESC LIMIT 1)e ON true
  WHERE a.sale_id=s.id AND a.mode='manual'
 ) p ON true LEFT JOIN LATERAL(
  SELECT sum(r.amount_usd) AS refunded FROM payment_refunds r JOIN payment_events e ON e.id=r.payment_event_id
   JOIN payment_attempts a ON a.id=e.attempt_id WHERE a.sale_id=s.id AND a.mode='manual'
 )r ON true;
REVOKE ALL ON sale_collection_balances FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON sale_collection_balances TO dlc_api_runtime;
