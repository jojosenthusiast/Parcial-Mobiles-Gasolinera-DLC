DO $test$
DECLARE org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); other_branch uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid();
 product uuid:=gen_random_uuid(); dispenser uuid:=gen_random_uuid(); nozzle uuid:=gen_random_uuid(); incident uuid:=gen_random_uuid(); tank uuid:=gen_random_uuid(); assessment record;
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
  INSERT INTO tanks(id,organization_id,branch_id,code,name,fuel_product_id,nominal_capacity_l,safe_fill_limit_l)
   VALUES(tank,org,branch,'T1','Fuel tank',product,10000,9500);
  INSERT INTO inventory_movements(organization_id,branch_id,tank_id,fuel_product_id,movement_type,command_id,request_hash,source_type,
   quantity_entered,unit_entered,conversion_factor_to_l,observed_l,delta_l,volume_basis,valuation_quality,
   before_quantity_l,after_quantity_l,actor_user_id,occurred_at,correlation_id)
   VALUES(org,branch,tank,product,'opening',gen_random_uuid(),repeat('c',64),'opening_balance',9000,'liter',1,9000,9000,'nominal','unknown',0,9000,actor,'2026-10-06 11:00+00',gen_random_uuid());
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO incidents(id,organization_id,branch_id,code,category,severity,asset_type,asset_id,description,occurred_at,reported_by,command_id,request_hash)
   VALUES(incident,org,branch,'INC-HOSE','equipment_damage','high','nozzle',nozzle,
    'Vehicle pulled away with the hose; no fuel spill has been verified','2026-10-06 12:00+00',actor,gen_random_uuid(),repeat('a',64));
  IF (SELECT count(*) FROM inventory_movements WHERE branch_id=branch)<>1 OR
   (SELECT count(*) FROM incident_events WHERE incident_id=incident)<>0 THEN
   RAISE EXCEPTION 'Incident created a fictitious fuel loss or event'; END IF;
  BEGIN
   INSERT INTO incidents(organization_id,branch_id,code,category,severity,asset_type,asset_id,description,occurred_at,reported_by,command_id,request_hash)
   VALUES(org,other_branch,'WRONG','equipment_damage','high','nozzle',nozzle,'Cross-branch resource must be rejected',now(),actor,gen_random_uuid(),repeat('b',64));
   RAISE EXCEPTION 'Cross-branch incident accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  SELECT * INTO assessment FROM assess_incident_impact(org,branch,incident,actor,'repair',NULL,NULL,NULL,75,'Replacement hose and installation estimate');
  IF assessment.cost_quality<>'unknown' OR assessment.historical_cost_usd IS NOT NULL THEN
   RAISE EXCEPTION 'Repair estimate invented fuel cost'; END IF;
  SELECT * INTO assessment FROM assess_incident_impact(org,branch,incident,actor,'fuel_loss',tank,10,'full_service',NULL,
   'Explicit measured ten-liter spill; cost source unknown');
  IF assessment.historical_cost_usd IS NOT NULL OR assessment.commercial_reference_usd IS NOT NULL THEN
   RAISE EXCEPTION 'Unknown cost and absent price should not be fabricated'; END IF;
  INSERT INTO asset_blocks(organization_id,branch_id,asset_type,asset_id,block_type,reason_code,reason,created_by,incident_id)
   VALUES(org,branch,'nozzle',nozzle,'safety','incident_reported','Inspect torn hose',actor,incident);
  PERFORM * FROM advance_incident(org,branch,incident,actor,1,'assessed',actor,now()+interval '1 day','Damage inspected on site');
  BEGIN PERFORM * FROM advance_incident(org,branch,incident,actor,1,'resolved',actor,NULL,'Cannot skip steps');
   RAISE EXCEPTION 'Stale transition succeeded'; EXCEPTION WHEN serialization_failure THEN NULL; END;
  PERFORM * FROM advance_incident(org,branch,incident,actor,2,'in_progress',actor,NULL,'Repair assigned to technician');
  PERFORM * FROM advance_incident(org,branch,incident,actor,3,'resolved',NULL,NULL,'Hose repaired and inspected');
  PERFORM * FROM advance_incident(org,branch,incident,actor,4,'closed',NULL,NULL,'Incident documentation closed');
  IF (SELECT count(*) FROM incident_events WHERE incident_id=incident)<>4 OR
    (SELECT count(*) FROM asset_blocks WHERE incident_id=incident AND resolved_at IS NULL)<>1 OR
    (SELECT count(*) FROM inventory_movements WHERE branch_id=branch)<>1 THEN
   RAISE EXCEPTION 'Incident lifecycle corrupted loss or safety block'; END IF;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE'  USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
