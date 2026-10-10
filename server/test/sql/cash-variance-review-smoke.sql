DO $test$
<<fixture>>
DECLARE org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); cashier uuid:=gen_random_uuid(); reviewer uuid:=gen_random_uuid();
 register_id uuid:=gen_random_uuid(); session_id uuid:=gen_random_uuid(); closure_id uuid:=gen_random_uuid(); approval_id uuid;
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(org,'Review transient');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(branch,org,'REVIEW','Review','occidental','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash) VALUES
   (cashier,org,cashier::text||'@example.invalid','Cashier','NOT_A_LOGIN_HASH'),
   (reviewer,org,reviewer::text||'@example.invalid','Reviewer','NOT_A_LOGIN_HASH');
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO cash_registers(id,organization_id,branch_id,code,created_by) VALUES(register_id,org,branch,'REG1',cashier);
  INSERT INTO cash_sessions(id,organization_id,branch_id,register_id,cashier_id,opening_usd,command_id,request_hash,correlation_id)
   VALUES(session_id,org,branch,register_id,cashier,100,gen_random_uuid(),repeat('a',64),gen_random_uuid());
  INSERT INTO cash_closures(id,organization_id,branch_id,session_id,counted_cash_usd,settled_card_usd,expected_cash_usd,expected_card_usd,variance_cash_usd,variance_card_usd,review_status,reason,command_id,request_hash,created_by,correlation_id)
   VALUES(closure_id,org,branch,session_id,95,0,0,0,0,0,'balanced','Faltan cinco dólares',gen_random_uuid(),repeat('b',64),cashier,gen_random_uuid());
  SELECT q.id INTO approval_id FROM approval_requests q WHERE q.organization_id=org AND q.entity_id=closure_id::text AND q.action='cash.variance.approve';
  IF approval_id IS NULL OR (SELECT v.status FROM cash_closure_reviews v WHERE v.closure_id=fixture.closure_id)<>'pending' THEN
   RAISE EXCEPTION 'The discrepancy was not queued';
  END IF;
  BEGIN
   UPDATE approval_requests SET status='approved',decided_by=cashier,decided_at=now(),reason='Conforme' WHERE id=approval_id;
   RAISE EXCEPTION 'Cashier approved own variance';
  EXCEPTION WHEN check_violation THEN NULL; END;
  UPDATE approval_requests SET status='approved',decided_by=reviewer,decided_at=now(),reason='Revisión documentada' WHERE id=approval_id;
  IF (SELECT v.status FROM cash_closure_reviews v WHERE v.closure_id=fixture.closure_id)<>'approved' OR
     (SELECT c.review_status FROM cash_closures c WHERE c.id=closure_id)<>'pending_review' THEN
   RAISE EXCEPTION 'Decision did not preserve immutable original closure';
  END IF;
  BEGIN
   UPDATE approval_requests SET status='rejected',decided_by=reviewer WHERE id=approval_id;
   RAISE EXCEPTION 'Resolved variance changed again';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
