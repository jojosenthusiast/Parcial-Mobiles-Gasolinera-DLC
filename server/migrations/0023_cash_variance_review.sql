-- A cash close stays immutable. Its variance is reviewed in a separate approval record.
INSERT INTO permissions(code,description) VALUES('cash.variance.approve','Aprobar o rechazar diferencias de caja')
ON CONFLICT(code) DO NOTHING;

CREATE UNIQUE INDEX cash_variance_one_review_idx ON approval_requests(organization_id,entity_id)
 WHERE action='cash.variance.approve' AND entity_type='cash_closure';

CREATE FUNCTION queue_cash_variance_review() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.review_status='pending_review' THEN
  INSERT INTO approval_requests(organization_id,branch_id,action,entity_type,entity_id,requested_by,payload)
  VALUES(NEW.organization_id,NEW.branch_id,'cash.variance.approve','cash_closure',NEW.id::text,NEW.created_by,
   jsonb_build_object('expectedCashUsd',NEW.expected_cash_usd::text,'countedCashUsd',NEW.counted_cash_usd::text,
    'varianceCashUsd',NEW.variance_cash_usd::text,'expectedCardUsd',NEW.expected_card_usd::text,
    'settledCardUsd',NEW.settled_card_usd::text,'varianceCardUsd',NEW.variance_card_usd::text,
    'cashierReason',NEW.reason));
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER cash_variance_queue AFTER INSERT ON cash_closures
 FOR EACH ROW EXECUTE FUNCTION queue_cash_variance_review();

CREATE FUNCTION guard_cash_variance_decision() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE closure cash_closures%ROWTYPE;
BEGIN
 IF OLD.action='cash.variance.approve' AND OLD.entity_type='cash_closure' THEN
  IF OLD.status<>'pending' OR NEW.status NOT IN('approved','rejected') OR NEW.decided_by IS NULL
   OR NEW.decided_by=OLD.requested_by OR NEW.decided_at IS NULL OR
   NEW.reason IS NULL OR length(btrim(NEW.reason))<3 OR
   (NEW.id,NEW.organization_id,NEW.branch_id,NEW.action,NEW.entity_type,NEW.entity_id,NEW.requested_by,NEW.payload)
     IS DISTINCT FROM (OLD.id,OLD.organization_id,OLD.branch_id,OLD.action,OLD.entity_type,OLD.entity_id,OLD.requested_by,OLD.payload) THEN
   RAISE EXCEPTION 'Cash variance needs one different-actor decision with reason' USING ERRCODE='23514';
  END IF;
  SELECT * INTO closure FROM cash_closures WHERE id=OLD.entity_id::uuid
   AND organization_id=OLD.organization_id AND branch_id=OLD.branch_id;
  IF closure.id IS NULL OR closure.review_status<>'pending_review' OR closure.created_by<>OLD.requested_by THEN
   RAISE EXCEPTION 'Cash variance review must reference its original closure' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER cash_variance_decision_guard BEFORE UPDATE ON approval_requests
 FOR EACH ROW EXECUTE FUNCTION guard_cash_variance_decision();

CREATE VIEW cash_closure_reviews WITH(security_invoker=true) AS
 SELECT c.id AS closure_id,c.organization_id,c.branch_id,c.session_id,c.created_by AS cashier_id,
  c.created_at AS closed_at,c.expected_cash_usd,c.counted_cash_usd,c.variance_cash_usd,
  c.expected_card_usd,c.settled_card_usd,c.variance_card_usd,c.reason AS cashier_reason,
  q.id AS approval_id,coalesce(q.status,'balanced') AS status,q.decided_by,q.decided_at,q.reason AS decision_reason
 FROM cash_closures c LEFT JOIN approval_requests q ON q.organization_id=c.organization_id
  AND q.branch_id=c.branch_id AND q.action='cash.variance.approve'
  AND q.entity_type='cash_closure' AND q.entity_id=c.id::text;
REVOKE ALL ON cash_closure_reviews FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON cash_closure_reviews TO dlc_api_runtime;
REVOKE ALL ON FUNCTION queue_cash_variance_review(),guard_cash_variance_decision() FROM PUBLIC,anon,authenticated,service_role;
