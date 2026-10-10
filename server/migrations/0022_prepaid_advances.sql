-- Pre-dispatch advances are separate from sale-scoped payment attempts.
CREATE TABLE prepayment_advances (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 authorization_id uuid NOT NULL, method text NOT NULL CHECK(method IN('cash','card')), mode text NOT NULL CHECK(mode IN('manual','simulated')),
 tender_kind text NOT NULL CHECK(tender_kind IN('captured','authorization_hold')),
 outcome text NOT NULL CHECK(outcome IN('confirmed','declined','unknown')),
 amount_usd numeric NOT NULL CHECK(amount_usd>0 AND amount_usd<1000000000 AND scale(amount_usd)<=2), currency text NOT NULL DEFAULT 'USD' CHECK(currency='USD'),
 cash_session_id uuid NOT NULL, evidence_reference text,
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(authorization_id,organization_id,branch_id) REFERENCES dispense_authorizations(id,organization_id,branch_id),
 FOREIGN KEY(cash_session_id,organization_id,branch_id) REFERENCES cash_sessions(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(mode='manual'),
 CHECK(method<>'cash' OR mode='manual'),
 CHECK(tender_kind<>'authorization_hold' OR (method='card' AND mode='manual' AND (outcome='unknown' OR evidence_reference IS NOT NULL))),
 CHECK(evidence_reference IS NULL OR length(btrim(evidence_reference)) BETWEEN 1 AND 200),
 UNIQUE(organization_id,command_id), UNIQUE(id,organization_id,branch_id)
);
CREATE UNIQUE INDEX prepayment_advance_source_idx ON prepayment_advances(organization_id,evidence_reference)
 WHERE method='card' AND mode='manual' AND evidence_reference IS NOT NULL;

CREATE TABLE prepayment_allocations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 advance_id uuid NOT NULL, sale_id uuid NOT NULL, payment_event_id uuid,
 amount_usd numeric NOT NULL CHECK(amount_usd>0 AND amount_usd<1000000000 AND scale(amount_usd)<=2),
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(advance_id,organization_id,branch_id) REFERENCES prepayment_advances(id,organization_id,branch_id),
 FOREIGN KEY(sale_id,organization_id,branch_id) REFERENCES sales(id,organization_id,branch_id),
 FOREIGN KEY(payment_event_id,organization_id,branch_id) REFERENCES payment_events(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id), UNIQUE(advance_id,sale_id), UNIQUE(id,organization_id,branch_id)
);

CREATE TABLE prepayment_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 advance_id uuid NOT NULL, allocation_id uuid, event_type text NOT NULL
  CHECK(event_type IN('received','allocated','refundPending','refunded','released','outcomeResolved')),
 outcome text CHECK(outcome IS NULL OR outcome IN('confirmed','declined','unknown')),
 outcome_reference text,
 disposition text CHECK(disposition IS NULL OR disposition IN('refund','release')),
 amount_usd numeric CHECK(amount_usd IS NULL OR (amount_usd>0 AND amount_usd<1000000000 AND scale(amount_usd)<=2)),
 confirmation_reference text,
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(advance_id,organization_id,branch_id) REFERENCES prepayment_advances(id,organization_id,branch_id),
 FOREIGN KEY(allocation_id,organization_id,branch_id) REFERENCES prepayment_allocations(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(confirmation_reference IS NULL OR length(btrim(confirmation_reference)) BETWEEN 1 AND 200),
 CHECK(outcome_reference IS NULL OR length(btrim(outcome_reference)) BETWEEN 1 AND 200),
 CHECK((event_type='refundPending' AND disposition IS NOT NULL AND amount_usd IS NOT NULL AND confirmation_reference IS NULL AND outcome IS NULL AND outcome_reference IS NULL)
    OR (event_type IN('refunded','released') AND disposition IS NOT NULL AND amount_usd IS NOT NULL AND confirmation_reference IS NOT NULL AND outcome IS NULL AND outcome_reference IS NULL)
    OR (event_type IN('received','allocated') AND disposition IS NULL AND confirmation_reference IS NULL AND outcome IS NULL AND outcome_reference IS NULL)
    OR (event_type='outcomeResolved' AND outcome IS NOT NULL AND outcome IN('confirmed','declined') AND outcome_reference IS NOT NULL AND disposition IS NULL AND amount_usd IS NULL AND confirmation_reference IS NULL)), 
 CHECK(event_type<>'refunded' OR disposition='refund'),
 CHECK(event_type<>'released' OR disposition='release'),
 UNIQUE(organization_id,command_id), UNIQUE(id,organization_id,branch_id)
);
CREATE UNIQUE INDEX prepayment_one_receipt_event_idx ON prepayment_events(advance_id) WHERE event_type='received';
CREATE UNIQUE INDEX prepayment_one_allocation_event_idx ON prepayment_events(allocation_id) WHERE event_type='allocated';
CREATE UNIQUE INDEX prepayment_allocation_payment_event_idx ON prepayment_allocations(payment_event_id) WHERE payment_event_id IS NOT NULL;
CREATE UNIQUE INDEX prepayment_one_disposition_event_idx ON prepayment_events(advance_id) WHERE event_type='refundPending';
CREATE UNIQUE INDEX prepayment_one_terminal_event_idx ON prepayment_events(advance_id)
 WHERE event_type IN('refunded','released');
CREATE UNIQUE INDEX prepayment_one_outcome_resolution_idx ON prepayment_events(advance_id) WHERE event_type='outcomeResolved';
CREATE UNIQUE INDEX prepayment_terminal_evidence_idx ON prepayment_events(organization_id,confirmation_reference)
 WHERE event_type IN('refunded','released') AND confirmation_reference IS NOT NULL;
CREATE INDEX prepayment_event_history_idx ON prepayment_events(advance_id,created_at,id);

CREATE FUNCTION prepayment_current_outcome(advance uuid) RETURNS text LANGUAGE sql STABLE SET search_path=public,pg_temp AS $$
 SELECT coalesce((SELECT e.outcome FROM prepayment_events e WHERE e.advance_id=a.id AND e.event_type='outcomeResolved'
  ORDER BY e.created_at DESC,e.id DESC LIMIT 1),a.outcome)
 FROM prepayment_advances a WHERE a.id=advance;
$$;
REVOKE ALL ON FUNCTION prepayment_current_outcome(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Include previously captured advances in the same sale cap as payment attempts.
CREATE OR REPLACE FUNCTION validate_payment_attempt() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE total numeric; occupied numeric; captured_allocated numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||NEW.sale_id::text,0));
 SELECT total_usd INTO total FROM sales WHERE id=NEW.sale_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 SELECT coalesce(sum(a.amount_usd),0) INTO occupied FROM payment_attempts a WHERE a.sale_id=NEW.sale_id
  AND NOT EXISTS(SELECT 1 FROM payment_events e WHERE e.attempt_id=a.id AND e.outcome='declined');
 SELECT coalesce(sum(al.amount_usd),0) INTO captured_allocated FROM prepayment_allocations al
  JOIN prepayment_advances adv ON adv.id=al.advance_id
  WHERE al.sale_id=NEW.sale_id AND adv.tender_kind='captured' AND prepayment_current_outcome(adv.id)='confirmed';
 IF total IS NULL OR NEW.amount_usd>total-occupied-captured_allocated THEN
  RAISE EXCEPTION 'Payment exceeds unreserved sale balance including captured advances' USING ERRCODE='23514';
 END IF;
 PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
 RETURN NEW;
END; $$;

-- An allocation must use the original completed dispense and fit both ledgers.
CREATE FUNCTION validate_prepayment_allocation() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE adv prepayment_advances%ROWTYPE; s sales%ROWTYPE; a dispense_authorizations%ROWTYPE; allocated numeric; active_payments numeric; captured_allocated numeric; sale_allocated numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('prepayment:'||NEW.advance_id::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||NEW.sale_id::text,0));
 SELECT * INTO adv FROM prepayment_advances WHERE id=NEW.advance_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 SELECT * INTO s FROM sales WHERE id=NEW.sale_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 SELECT * INTO a FROM dispense_authorizations WHERE id=adv.authorization_id AND organization_id=adv.organization_id AND branch_id=adv.branch_id;
 SELECT coalesce(sum(amount_usd),0) INTO allocated FROM prepayment_allocations WHERE advance_id=adv.id;
 SELECT coalesce(sum(pa.amount_usd),0) INTO active_payments FROM payment_attempts pa WHERE pa.sale_id=s.id
  AND NOT EXISTS(SELECT 1 FROM payment_events pe WHERE pe.attempt_id=pa.id AND pe.outcome='declined');
 SELECT coalesce(sum(al.amount_usd),0) INTO captured_allocated FROM prepayment_allocations al
  JOIN prepayment_advances prev ON prev.id=al.advance_id
  WHERE al.sale_id=s.id AND prev.tender_kind='captured' AND prepayment_current_outcome(prev.id)='confirmed';
 sale_allocated:=active_payments+captured_allocated;
 IF adv.id IS NULL OR s.id IS NULL OR a.status IS DISTINCT FROM 'completed' OR s.authorization_id IS DISTINCT FROM a.id
  OR NEW.amount_usd>adv.amount_usd-allocated THEN
  RAISE EXCEPTION 'Prepayment allocation exceeds advance/sale or lacks its completed original dispatch' USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM prepayment_events WHERE advance_id=adv.id AND event_type='refundPending') THEN
  RAISE EXCEPTION 'Allocation is locked after a residual disposition is selected' USING ERRCODE='23514';
 END IF;
 IF adv.tender_kind='captured' THEN
  IF prepayment_current_outcome(adv.id)<>'confirmed' OR NEW.payment_event_id IS NOT NULL OR
     NEW.amount_usd>s.total_usd-sale_allocated THEN
   RAISE EXCEPTION 'Only confirmed captured advances within the unreserved sale balance allocate directly' USING ERRCODE='23514';
  END IF;
 ELSIF prepayment_current_outcome(adv.id)<>'confirmed' OR NOT EXISTS(
  SELECT 1 FROM payment_events e JOIN payment_attempts pa ON pa.id=e.attempt_id
  WHERE e.id=NEW.payment_event_id AND e.organization_id=NEW.organization_id AND e.branch_id=NEW.branch_id
   AND e.outcome='confirmed' AND pa.sale_id=s.id AND pa.organization_id=s.organization_id AND pa.branch_id=s.branch_id
   AND pa.amount_usd=NEW.amount_usd AND pa.method='card' AND pa.mode='manual'
 ) THEN RAISE EXCEPTION 'Hold allocation must link the confirmed sale payment for its exact real amount' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER prepayment_allocation_guard BEFORE INSERT ON prepayment_allocations FOR EACH ROW EXECUTE FUNCTION validate_prepayment_allocation();

CREATE FUNCTION validate_prepayment_advance() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM dispense_authorizations WHERE id=NEW.authorization_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id) THEN
  RAISE EXCEPTION 'Advance requires its original dispense authorization' USING ERRCODE='23514';
 END IF;
 IF NEW.method='card' AND NEW.mode='manual' AND NEW.outcome<>'unknown' AND NEW.evidence_reference IS NULL THEN
  RAISE EXCEPTION 'Known manual card advance requires documentary evidence' USING ERRCODE='23514';
 END IF;
 PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
 RETURN NEW;
END; $$;
CREATE TRIGGER prepayment_advance_guard BEFORE INSERT ON prepayment_advances FOR EACH ROW EXECUTE FUNCTION validate_prepayment_advance();

CREATE FUNCTION validate_prepayment_event() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE adv prepayment_advances%ROWTYPE; allocation prepayment_allocations%ROWTYPE; pending prepayment_events%ROWTYPE; remaining numeric; refunded numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('prepayment:'||NEW.advance_id::text,0));
 SELECT * INTO adv FROM prepayment_advances WHERE id=NEW.advance_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 IF adv.id IS NULL THEN RAISE EXCEPTION 'Prepayment event requires its advance' USING ERRCODE='23514'; END IF;
 IF NEW.event_type='outcomeResolved' THEN
  IF adv.outcome<>'unknown' OR prepayment_current_outcome(adv.id)<>'unknown' OR
     NEW.outcome IS NULL OR NEW.outcome NOT IN('confirmed','declined') OR NEW.outcome_reference IS NULL THEN
   RAISE EXCEPTION 'Only an unknown advance outcome can be resolved once with evidence' USING ERRCODE='23514';
  END IF;
  PERFORM lock_owned_open_cash(adv.cash_session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
  RETURN NEW;
 END IF;
 IF NEW.event_type='received' AND (NEW.created_by<>adv.created_by OR NEW.amount_usd IS DISTINCT FROM adv.amount_usd) THEN
  RAISE EXCEPTION 'Receipt must match the original advance and actor' USING ERRCODE='23514';
 END IF;
 IF NEW.event_type='allocated' THEN
  SELECT * INTO allocation FROM prepayment_allocations WHERE id=NEW.allocation_id AND advance_id=NEW.advance_id
   AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
  IF allocation.id IS NULL OR NEW.amount_usd IS DISTINCT FROM allocation.amount_usd THEN
   RAISE EXCEPTION 'Allocation event must match its immutable allocation' USING ERRCODE='23514';
  END IF;
 END IF;
 IF NEW.event_type='refundPending' THEN
  IF NOT (adv.tender_kind='captured' AND prepayment_current_outcome(adv.id)='confirmed' AND NEW.disposition='refund') AND NOT
     (adv.tender_kind='authorization_hold' AND prepayment_current_outcome(adv.id)='confirmed' AND adv.method='card' AND adv.mode='manual' AND NEW.disposition='release') THEN
   RAISE EXCEPTION 'Disposition does not match confirmed advance tender' USING ERRCODE='23514';
  END IF;
  SELECT adv.amount_usd-coalesce(sum(amount_usd),0) INTO remaining FROM prepayment_allocations WHERE advance_id=adv.id;
  IF NEW.amount_usd IS DISTINCT FROM remaining OR remaining<=0 THEN
   RAISE EXCEPTION 'Pending disposition must cover the positive unallocated remainder' USING ERRCODE='23514';
  END IF;
 END IF;
 IF NEW.event_type IN('refunded','released') THEN
  IF NEW.confirmation_reference IS NULL THEN
   RAISE EXCEPTION 'Terminal prepayment disposition requires confirmation evidence' USING ERRCODE='23514';
  END IF;
  IF adv.tender_kind='captured' AND NOT (prepayment_current_outcome(adv.id)='confirmed' AND NEW.event_type='refunded' AND NEW.disposition='refund') OR
     adv.tender_kind='authorization_hold' AND NOT (prepayment_current_outcome(adv.id)='confirmed' AND adv.method='card' AND adv.mode='manual' AND NEW.event_type='released' AND NEW.disposition='release' AND NEW.confirmation_reference IS NOT NULL) THEN
   RAISE EXCEPTION 'Terminal disposition does not match confirmed advance tender' USING ERRCODE='23514';
  END IF;
  SELECT * INTO pending FROM prepayment_events WHERE advance_id=adv.id AND event_type='refundPending' AND disposition=NEW.disposition;
  IF pending.id IS NULL OR pending.amount_usd IS DISTINCT FROM NEW.amount_usd THEN
   RAISE EXCEPTION 'Terminal confirmation must match the selected disposition and remainder' USING ERRCODE='23514';
  END IF;
  IF NEW.event_type='refunded' THEN
   SELECT coalesce(sum(amount_usd),0) INTO refunded FROM payment_refunds WHERE advance_id=adv.id;
   IF refunded IS DISTINCT FROM pending.amount_usd THEN
    RAISE EXCEPTION 'Refund confirmation must match the confirmed refund total' USING ERRCODE='23514';
   END IF;
  ELSIF EXISTS(SELECT 1 FROM payment_refunds WHERE advance_id=adv.id) THEN
   RAISE EXCEPTION 'An advance with refunds cannot be released' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER prepayment_event_guard BEFORE INSERT ON prepayment_events FOR EACH ROW EXECUTE FUNCTION validate_prepayment_event();

-- Derive residual state from immutable events; no method-based disposition is inferred.
CREATE VIEW prepayment_residuals WITH(security_invoker=true) AS
 SELECT a.id AS advance_id,a.organization_id,a.branch_id,a.amount_usd,a.tender_kind,
  coalesce(x.allocated_usd,0) AS allocated_usd,
  prepayment_current_outcome(a.id) AS tender_outcome,
  CASE WHEN prepayment_current_outcome(a.id)='declined' THEN 0
       ELSE greatest(a.amount_usd-coalesce(x.allocated_usd,0),0) END AS remaining_usd,
  CASE WHEN prepayment_current_outcome(a.id)='declined' OR greatest(a.amount_usd-coalesce(x.allocated_usd,0),0)=0 THEN NULL
       ELSE coalesce(t.event_type,'refundPending') END AS residual_state
 FROM prepayment_advances a
 LEFT JOIN LATERAL(SELECT sum(amount_usd) AS allocated_usd FROM prepayment_allocations WHERE advance_id=a.id)x ON true
 LEFT JOIN LATERAL(SELECT event_type FROM prepayment_events WHERE advance_id=a.id AND event_type IN('refunded','released')
  ORDER BY created_at DESC,id DESC LIMIT 1)t ON true;

-- Refunds retain exactly one original source. Existing sale-refund rows and their
-- validation path remain unchanged; advances use the same approval/cash controls.
ALTER TABLE payment_refunds ALTER COLUMN payment_event_id DROP NOT NULL;
ALTER TABLE payment_refunds ADD COLUMN advance_id uuid;
ALTER TABLE payment_refunds ADD CONSTRAINT payment_refunds_advance_fk
 FOREIGN KEY(advance_id,organization_id,branch_id) REFERENCES prepayment_advances(id,organization_id,branch_id);
ALTER TABLE payment_refunds ADD CONSTRAINT payment_refunds_one_source_check
 CHECK((payment_event_id IS NOT NULL AND advance_id IS NULL) OR (advance_id IS NOT NULL AND payment_event_id IS NULL));
CREATE INDEX payment_refunds_advance_idx ON payment_refunds(advance_id) WHERE advance_id IS NOT NULL;

CREATE OR REPLACE FUNCTION validate_payment_refund() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE e payment_events%ROWTYPE; a payment_attempts%ROWTYPE; adv prepayment_advances%ROWTYPE; refunded numeric; allocated numeric; approval_entity text;
BEGIN
 IF (NEW.payment_event_id IS NOT NULL)=(NEW.advance_id IS NOT NULL) THEN
  RAISE EXCEPTION 'Refund must reference exactly one original source' USING ERRCODE='23514';
 END IF;
 IF NEW.payment_event_id IS NOT NULL THEN
  -- Preserve the original sale-refund amount, approval, cash and method checks.
  PERFORM pg_advisory_xact_lock(hashtextextended('refund-payment:'||NEW.payment_event_id::text,0));
  SELECT * INTO e FROM payment_events WHERE id=NEW.payment_event_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id AND outcome='confirmed';
  SELECT * INTO a FROM payment_attempts WHERE id=e.attempt_id;
  SELECT coalesce(sum(amount_usd),0) INTO refunded FROM payment_refunds WHERE payment_event_id=e.id;
  IF e.id IS NULL OR NEW.amount_usd>a.amount_usd-refunded THEN RAISE EXCEPTION 'Refund exceeds original net payment' USING ERRCODE='23514'; END IF;
  approval_entity:=NEW.payment_event_id::text;
  IF a.method='card' AND NEW.evidence_reference IS NULL THEN RAISE EXCEPTION 'Card refund requires original-method evidence, not cash' USING ERRCODE='23514'; END IF;
 ELSE
  PERFORM pg_advisory_xact_lock(hashtextextended('prepayment:'||NEW.advance_id::text,0));
  SELECT * INTO adv FROM prepayment_advances WHERE id=NEW.advance_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
  SELECT coalesce(sum(amount_usd),0) INTO allocated FROM prepayment_allocations WHERE advance_id=adv.id;
  SELECT coalesce(sum(amount_usd),0) INTO refunded FROM payment_refunds WHERE advance_id=adv.id;
  IF adv.id IS NULL OR NEW.amount_usd>adv.amount_usd-allocated-refunded THEN RAISE EXCEPTION 'Refund exceeds unallocated advance balance' USING ERRCODE='23514'; END IF;
  IF adv.tender_kind<>'captured' OR prepayment_current_outcome(adv.id)<>'confirmed' OR NOT EXISTS(
   SELECT 1 FROM prepayment_events WHERE advance_id=adv.id AND event_type='refundPending' AND disposition='refund'
  ) THEN
   RAISE EXCEPTION 'Only a confirmed captured advance with an explicit refund disposition can be refunded' USING ERRCODE='23514';
  END IF;
  IF adv.method='card' AND NEW.evidence_reference IS NULL THEN RAISE EXCEPTION 'Card refund requires original-method evidence, not cash' USING ERRCODE='23514'; END IF;
  approval_entity:=NEW.advance_id::text;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM approval_requests q WHERE q.id=NEW.approval_id AND q.organization_id=NEW.organization_id AND q.branch_id=NEW.branch_id
  AND q.action='sale.refund.approve' AND q.entity_type='payment_refund' AND q.entity_id=approval_entity AND q.status='approved'
  AND q.requested_by=NEW.created_by AND q.decided_by<>NEW.created_by
  AND q.payload->>'amountUsd'=NEW.amount_usd::text AND q.payload->>'reason'=NEW.reason) THEN
  RAISE EXCEPTION 'Refund needs matching approval from another actor' USING ERRCODE='23514';
 END IF;
 PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
 RETURN NEW;
END; $$;

-- Cash movements can identify either the existing payment event or an advance.
ALTER TABLE cash_movements ADD COLUMN advance_id uuid UNIQUE;
ALTER TABLE cash_movements ADD CONSTRAINT cash_movements_advance_fk
 FOREIGN KEY(advance_id,organization_id,branch_id) REFERENCES prepayment_advances(id,organization_id,branch_id);
ALTER TABLE cash_movements DROP CONSTRAINT cash_movements_check;
ALTER TABLE cash_movements ADD CONSTRAINT cash_movements_check CHECK(
 (kind='collection' AND delta_usd>0 AND refund_id IS NULL AND
   ((payment_event_id IS NOT NULL AND advance_id IS NULL) OR (payment_event_id IS NULL AND advance_id IS NOT NULL)))
 OR (kind='refund' AND delta_usd<0 AND refund_id IS NOT NULL AND payment_event_id IS NULL AND advance_id IS NULL)
 OR (kind='cash_in' AND delta_usd>0 AND payment_event_id IS NULL AND advance_id IS NULL AND refund_id IS NULL)
 OR (kind IN('deposit','withdrawal') AND delta_usd<0 AND payment_event_id IS NULL AND advance_id IS NULL AND refund_id IS NULL));

CREATE OR REPLACE FUNCTION validate_cash_entry() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c cash_sessions%ROWTYPE; p record; r record; expected numeric; card_expected numeric;
BEGIN
 IF TG_TABLE_NAME='cash_sessions' THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('cash-register:'||NEW.register_id::text,0));
  IF EXISTS(SELECT 1 FROM cash_sessions s WHERE s.register_id=NEW.register_id AND NOT EXISTS(SELECT 1 FROM cash_closures WHERE session_id=s.id)) THEN
   RAISE EXCEPTION 'Register already has an open session' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS(SELECT 1 FROM branches WHERE id=NEW.branch_id AND organization_id=NEW.organization_id AND status='active') THEN
   RAISE EXCEPTION 'Cash requires an active branch' USING ERRCODE='23514'; END IF;
  RETURN NEW;
 END IF;
 PERFORM lock_owned_open_cash(NEW.session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
 SELECT * INTO c FROM cash_sessions WHERE id=NEW.session_id;
 SELECT c.opening_usd+coalesce(sum(delta_usd),0) INTO expected FROM cash_movements WHERE session_id=c.id;
 IF TG_TABLE_NAME='cash_movements' THEN
  IF NEW.kind='collection' THEN
   IF NEW.advance_id IS NULL THEN
    SELECT a.*,e.outcome,e.created_by AS event_actor INTO p FROM payment_events e JOIN payment_attempts a ON a.id=e.attempt_id WHERE e.id=NEW.payment_event_id;
    IF p.outcome IS DISTINCT FROM 'confirmed' OR p.method IS DISTINCT FROM 'cash' OR p.cash_session_id IS DISTINCT FROM c.id
     OR NEW.delta_usd IS DISTINCT FROM p.amount_usd OR NEW.created_by IS DISTINCT FROM p.event_actor THEN
     RAISE EXCEPTION 'Cash collection must match confirmed payment' USING ERRCODE='23514'; END IF;
   ELSE
    SELECT a0.*,CASE WHEN e.event_type='outcomeResolved' THEN e.outcome ELSE prepayment_current_outcome(a0.id) END AS effective_outcome,e.created_by AS event_actor INTO p
     FROM prepayment_advances a0 JOIN prepayment_events e ON e.advance_id=a0.id AND e.id=NEW.command_id
      AND e.event_type IN('received','outcomeResolved') WHERE a0.id=NEW.advance_id;
    IF p.method IS DISTINCT FROM 'cash' OR p.mode IS DISTINCT FROM 'manual' OR p.tender_kind IS DISTINCT FROM 'captured' OR p.effective_outcome IS DISTINCT FROM 'confirmed' OR p.cash_session_id IS DISTINCT FROM c.id
     OR NEW.delta_usd IS DISTINCT FROM p.amount_usd OR NEW.created_by IS DISTINCT FROM p.event_actor THEN
     RAISE EXCEPTION 'Cash collection must match confirmed advance' USING ERRCODE='23514'; END IF;
   END IF;
  ELSIF NEW.kind='refund' THEN
   SELECT r0.*,coalesce(a.method,adv.method) AS method INTO r FROM payment_refunds r0
    LEFT JOIN payment_events e ON e.id=r0.payment_event_id LEFT JOIN payment_attempts a ON a.id=e.attempt_id
    LEFT JOIN prepayment_advances adv ON adv.id=r0.advance_id WHERE r0.id=NEW.refund_id;
   IF r.method IS DISTINCT FROM 'cash' OR r.cash_session_id IS DISTINCT FROM c.id OR NEW.delta_usd IS DISTINCT FROM -r.amount_usd OR NEW.created_by IS DISTINCT FROM r.created_by THEN
    RAISE EXCEPTION 'Cash refund must match original refund' USING ERRCODE='23514'; END IF;
  END IF;
  IF expected+NEW.delta_usd<0 THEN RAISE EXCEPTION 'Cash outflow exceeds expected cash' USING ERRCODE='23514'; END IF;
 ELSE
  SELECT coalesce(sum(a.amount_usd),0) INTO card_expected FROM payment_events e JOIN payment_attempts a ON a.id=e.attempt_id
  WHERE e.outcome='confirmed' AND a.method='card' AND a.mode='manual' AND a.cash_session_id=c.id;
  card_expected:=card_expected+(SELECT coalesce(sum(a.amount_usd),0) FROM prepayment_advances a
   WHERE a.method='card' AND a.mode='manual' AND a.tender_kind='captured' AND prepayment_current_outcome(a.id)='confirmed' AND a.cash_session_id=c.id);
  card_expected:=card_expected-(SELECT coalesce(sum(rr.amount_usd),0) FROM payment_refunds rr
   JOIN payment_events e ON e.id=rr.payment_event_id JOIN payment_attempts a ON a.id=e.attempt_id
   WHERE rr.cash_session_id=c.id AND a.method='card' AND a.mode='manual');
  card_expected:=card_expected-(SELECT coalesce(sum(rr.amount_usd),0) FROM payment_refunds rr
   JOIN prepayment_advances a ON a.id=rr.advance_id
   WHERE rr.cash_session_id=c.id AND a.method='card' AND a.mode='manual');
  NEW.expected_cash_usd:=expected; NEW.expected_card_usd:=card_expected;
  NEW.variance_cash_usd:=NEW.counted_cash_usd-expected; NEW.variance_card_usd:=NEW.settled_card_usd-card_expected;
  NEW.review_status:=CASE WHEN NEW.variance_cash_usd=0 AND NEW.variance_card_usd=0 THEN 'balanced' ELSE 'pending_review' END;
  IF NEW.review_status='pending_review' AND NEW.reason IS NULL THEN RAISE EXCEPTION 'Discrepancy needs a reason and review' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM payment_attempts a WHERE a.cash_session_id=c.id AND NOT EXISTS(SELECT 1 FROM payment_events WHERE attempt_id=a.id AND outcome IN('confirmed','declined'))) THEN
   RAISE EXCEPTION 'Resolve pending cash attempts before closure' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM prepayment_advances a WHERE prepayment_current_outcome(a.id)='unknown' AND a.cash_session_id=c.id) THEN
   RAISE EXCEPTION 'Resolve unknown prepayment tenders before closure' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION post_payment_cash_movement() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a payment_attempts%ROWTYPE; adv prepayment_advances%ROWTYPE;
BEGIN
 IF TG_TABLE_NAME='payment_events' THEN
  SELECT * INTO a FROM payment_attempts WHERE id=NEW.attempt_id;
  IF NEW.outcome='confirmed' AND a.method='cash' THEN
   INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,payment_event_id,reason,command_id,request_hash,created_by,correlation_id)
   VALUES(NEW.organization_id,NEW.branch_id,a.cash_session_id,'collection',a.amount_usd,NEW.id,'Cobro de venta',NEW.id,NEW.request_hash,NEW.created_by,NEW.correlation_id);
  END IF;
 ELSIF TG_TABLE_NAME='prepayment_events' THEN
  SELECT * INTO adv FROM prepayment_advances WHERE id=NEW.advance_id;
  IF ((NEW.event_type='received' AND adv.outcome='confirmed') OR
      (NEW.event_type='outcomeResolved' AND NEW.outcome='confirmed'))
     AND adv.tender_kind='captured' AND adv.method='cash' THEN
   INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,advance_id,reason,command_id,request_hash,created_by,correlation_id)
   VALUES(NEW.organization_id,NEW.branch_id,adv.cash_session_id,'collection',adv.amount_usd,adv.id,'Cobro de anticipo',NEW.id,NEW.request_hash,NEW.created_by,NEW.correlation_id);
  END IF;
 ELSE
  IF NEW.payment_event_id IS NOT NULL THEN
   SELECT a0.* INTO a FROM payment_events e JOIN payment_attempts a0 ON a0.id=e.attempt_id WHERE e.id=NEW.payment_event_id;
   IF a.method='cash' THEN
    INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,refund_id,reason,command_id,request_hash,created_by,correlation_id)
    VALUES(NEW.organization_id,NEW.branch_id,NEW.cash_session_id,'refund',-NEW.amount_usd,NEW.id,NEW.reason,NEW.id,NEW.request_hash,NEW.created_by,NEW.correlation_id);
   END IF;
  ELSE
   SELECT * INTO adv FROM prepayment_advances WHERE id=NEW.advance_id;
   IF adv.method='cash' THEN
    INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,refund_id,reason,command_id,request_hash,created_by,correlation_id)
    VALUES(NEW.organization_id,NEW.branch_id,NEW.cash_session_id,'refund',-NEW.amount_usd,NEW.id,NEW.reason,NEW.id,NEW.request_hash,NEW.created_by,NEW.correlation_id);
   END IF;
  END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER prepayment_cash_post AFTER INSERT ON prepayment_events FOR EACH ROW EXECUTE FUNCTION post_payment_cash_movement();

-- Check after ordinary AFTER triggers have posted any confirmed cash movement.
CREATE FUNCTION assert_prepayment_cash_receipt() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE checked_advance_id uuid; adv prepayment_advances%ROWTYPE; effective_outcome text; movement_count bigint;
BEGIN
 IF TG_TABLE_NAME='prepayment_advances' THEN
  checked_advance_id:=NEW.id;
 ELSE
  checked_advance_id:=NEW.advance_id;
 END IF;
 SELECT * INTO adv FROM prepayment_advances WHERE id=checked_advance_id;
 IF adv.id IS NULL THEN RETURN NULL; END IF;
 effective_outcome:=prepayment_current_outcome(adv.id);
 SELECT count(*) INTO movement_count FROM cash_movements WHERE advance_id=adv.id;
 IF adv.tender_kind='captured' AND adv.method='cash' AND effective_outcome='confirmed' THEN
  IF movement_count<>1 THEN
   RAISE EXCEPTION 'Confirmed captured cash advance must have exactly one cash movement' USING ERRCODE='23514';
  END IF;
 ELSIF movement_count<>0 THEN
  RAISE EXCEPTION 'Unknown, declined or authorization-hold advance cannot have a cash movement' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER prepayment_cash_receipt_guard
 AFTER INSERT ON prepayment_advances DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION assert_prepayment_cash_receipt();
CREATE CONSTRAINT TRIGGER prepayment_cash_outcome_guard
 AFTER INSERT ON prepayment_events DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION assert_prepayment_cash_receipt();

-- Preserve the established sale-balance columns. Captured advances contribute
-- through allocations only; holds contribute solely through their sale payment event.
CREATE OR REPLACE VIEW sale_collection_balances WITH(security_invoker=true) AS
 SELECT s.id,s.organization_id,s.branch_id,
  CASE WHEN coalesce(p.collected,0)>=s.total_usd THEN 'paid' ELSE 'pending_collection' END AS collection_status,
  coalesce(p.collected,0) AS collected_usd,coalesce(p.reserved,0) AS reserved_usd,
  greatest(s.total_usd-coalesce(p.collected,0),0) AS outstanding_usd,
  coalesce(r.refunded,0) AS refunded_usd,
  CASE WHEN coalesce(r.refunded,0)=0 THEN 'none' WHEN r.refunded>=p.collected THEN 'refunded' ELSE 'partial' END AS refund_status
 FROM sales s LEFT JOIN LATERAL(
  SELECT coalesce(sum(a.amount_usd) FILTER(WHERE e.outcome='confirmed'),0) + coalesce((
    SELECT sum(al.amount_usd) FROM prepayment_allocations al JOIN prepayment_advances adv ON adv.id=al.advance_id
    WHERE al.sale_id=s.id AND adv.tender_kind='captured' AND prepayment_current_outcome(adv.id)='confirmed'
  ),0) AS collected,
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

-- Event, allocation and tender records are append-only and backend-only.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['prepayment_advances','prepayment_allocations','prepayment_events'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
  EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',t||'_immutable',t);
 END LOOP;
END; $$;
REVOKE ALL ON prepayment_residuals FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON prepayment_residuals TO dlc_api_runtime;
REVOKE ALL ON FUNCTION prepayment_current_outcome(uuid),validate_prepayment_allocation(),validate_prepayment_advance(),validate_prepayment_event() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION prepayment_current_outcome(uuid) TO dlc_api_runtime;
REVOKE ALL ON FUNCTION validate_payment_refund(),validate_cash_entry(),post_payment_cash_movement(),assert_prepayment_cash_receipt() FROM PUBLIC,anon,authenticated,service_role;
