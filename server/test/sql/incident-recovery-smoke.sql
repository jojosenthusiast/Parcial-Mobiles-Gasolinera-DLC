DO $test$
DECLARE org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); other_branch uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid();
 product uuid:=gen_random_uuid(); dispenser uuid:=gen_random_uuid(); nozzle uuid:=gen_random_uuid(); incident uuid:=gen_random_uuid(); claim uuid:=gen_random_uuid();
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(org,'Incident transient');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES
   (branch,org,'INC1','Incident branch','central','active'),(other_branch,org,'INC2','Other branch','central','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status)
   VALUES(actor,org,actor::text||'@example.invalid','Reporter','NOT_A_LOGIN_HASH','active');
  INSERT INTO fuel_products(id,organization_id,sku,display_name,family) VALUES(product,org,'REG','Regular','regular');
  INSERT INTO branch_fuel_offers(organization_id,branch_id,fuel_product_id,created_by) VALUES(org,branch,product,actor);
  INSERT INTO dispensers(id,organization_id,branch_id,code) VALUES(dispenser,org,branch,'D1');
  INSERT INTO nozzles(id,organization_id,branch_id,dispenser_id,code,product_code,fuel_product_id,service_mode)
   VALUES(nozzle,org,branch,dispenser,'N1','REG',product,'full_service');
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO incidents(id,organization_id,branch_id,code,category,severity,asset_type,asset_id,description,occurred_at,reported_by,command_id,request_hash)
   VALUES(incident,org,branch,'INC-HOSE','equipment_damage','high','nozzle',nozzle,
    'Vehicle pulled away with the hose; no fuel spill has been verified','2026-10-06 12:00+00',actor,gen_random_uuid(),repeat('a',64));
  IF (SELECT count(*) FROM inventory_movements WHERE branch_id=branch)<>0 OR
   (SELECT count(*) FROM incident_events WHERE incident_id=incident)<>0 THEN
   RAISE EXCEPTION 'Incident created a fictitious fuel loss or event'; END IF;
  BEGIN
   INSERT INTO incidents(organization_id,branch_id,code,category,severity,asset_type,asset_id,description,occurred_at,reported_by,command_id,request_hash)
   VALUES(org,other_branch,'WRONG','equipment_damage','high','nozzle',nozzle,'Cross-branch resource must be rejected',now(),actor,gen_random_uuid(),repeat('b',64));
   RAISE EXCEPTION 'Cross-branch incident accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO incident_recovery_claims(id,organization_id,branch_id,incident_id,counterparty_type,counterparty_name,reference,claimed_usd,filed_by)
   VALUES(claim,org,branch,incident,'third_party','Vehicle owner','INC-HOSE-CLAIM',100,actor);
  INSERT INTO incident_recovery_receipts(organization_id,branch_id,claim_id,amount_usd,method,evidence_reference,command_id,received_by)
   VALUES(org,branch,claim,30,'bank_transfer','bank-reference-001',gen_random_uuid(),actor),
         (org,branch,claim,20,'cash','signed-receipt-001',gen_random_uuid(),actor);
  IF (SELECT outstanding_usd FROM incident_recovery_balances WHERE claim_id=claim)<>50 THEN
   RAISE EXCEPTION 'Recovery balance wrong'; END IF;
  BEGIN INSERT INTO incident_recovery_receipts(organization_id,branch_id,claim_id,amount_usd,method,evidence_reference,command_id,received_by)
    VALUES(org,branch,claim,51,'cash','signed-receipt-002',gen_random_uuid(),actor);
   RAISE EXCEPTION 'Over recovery accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE'  USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
