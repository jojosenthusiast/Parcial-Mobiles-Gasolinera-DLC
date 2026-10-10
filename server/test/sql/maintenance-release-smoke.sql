DO $test$
DECLARE org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); worker uuid:=gen_random_uuid(); verifier uuid:=gen_random_uuid(); releaser uuid:=gen_random_uuid();
 product uuid:=gen_random_uuid(); dispenser uuid:=gen_random_uuid(); nozzle uuid:=gen_random_uuid(); asset uuid:=gen_random_uuid();
 block1 uuid:=gen_random_uuid(); block2 uuid:=gen_random_uuid(); work uuid:=gen_random_uuid(); work2 uuid:=gen_random_uuid(); result record;
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(org,'Maintenance transient');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(branch,org,'MAINT','Maintenance','central','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status)
   VALUES(worker,org,worker::text||'@example.invalid','Worker','NOT_A_LOGIN_HASH','active'),
         (verifier,org,verifier::text||'@example.invalid','Verifier','NOT_A_LOGIN_HASH','active'),
         (releaser,org,releaser::text||'@example.invalid','Releaser','NOT_A_LOGIN_HASH','active');
  INSERT INTO fuel_products(id,organization_id,sku,display_name,family) VALUES(product,org,'DIE','Diesel','diesel');
  INSERT INTO branch_fuel_offers(organization_id,branch_id,fuel_product_id,created_by) VALUES(org,branch,product,worker);
  INSERT INTO dispensers(id,organization_id,branch_id,code) VALUES(dispenser,org,branch,'D1');
  INSERT INTO nozzles(id,organization_id,branch_id,dispenser_id,code,product_code,fuel_product_id,service_mode,physical_status)
   VALUES(nozzle,org,branch,dispenser,'N1','DIE',product,'full_service','maintenance');
  INSERT INTO maintenance_asset_profiles(id,organization_id,branch_id,asset_type,asset_id,criticality,created_by)
   VALUES(asset,org,branch,'nozzle',nozzle,'high',worker);
  INSERT INTO asset_blocks(id,organization_id,branch_id,asset_type,asset_id,block_type,reason_code,reason,created_by)
   VALUES(block1,org,branch,'nozzle',nozzle,'technical','hose','Hose repair',worker),
         (block2,org,branch,'nozzle',nozzle,'safety','calibration','Calibration pending',worker);
  INSERT INTO maintenance_work_orders(id,organization_id,branch_id,asset_profile_id,target_block_id,kind,due_key,description,created_by)
   VALUES(work,org,branch,asset,block1,'corrective','hose-001','Replace damaged hose',worker),
         (work2,org,branch,asset,block2,'inspection','calibration-001','Verify calibration',worker);
  SET LOCAL ROLE dlc_api_runtime;
  BEGIN UPDATE asset_blocks SET resolved_by=worker,resolved_at=clock_timestamp(),resolution='shortcut' WHERE id=block1;
   RAISE EXCEPTION 'Technical block bypassed verified order'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN UPDATE nozzles SET physical_status='active' WHERE id=nozzle;
   RAISE EXCEPTION 'Blocked nozzle activated directly'; EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM * FROM advance_work_order(org,branch,work,worker,1,'in_progress',NULL);
  INSERT INTO maintenance_order_tasks(organization_id,branch_id,order_id,description,result,completed_by)
   VALUES(org,branch,work,'Replace hose','Replacement fitted',worker);
  PERFORM * FROM advance_work_order(org,branch,work,worker,2,'completed','Replaced torn hose');
  BEGIN PERFORM * FROM advance_work_order(org,branch,work,worker,3,'verified',NULL);
   RAISE EXCEPTION 'Worker self-verified'; EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM * FROM advance_work_order(org,branch,work,verifier,3,'verified',NULL);
  SELECT * INTO result FROM release_maintenance_block(org,branch,work,block1,releaser,'Technical verification and hose pressure test passed');
  IF result.remaining_blocks<>1 OR result.can_operate OR (SELECT physical_status FROM nozzles WHERE id=nozzle)<>'maintenance' THEN
   RAISE EXCEPTION 'Remaining block was ignored'; END IF;
  PERFORM * FROM advance_work_order(org,branch,work2,worker,1,'in_progress',NULL);
  INSERT INTO maintenance_order_tasks(organization_id,branch_id,order_id,description,result,completed_by)
   VALUES(org,branch,work2,'Verify nozzle calibration','Calibration within tolerance',worker);
  PERFORM * FROM advance_work_order(org,branch,work2,worker,2,'completed','Calibration verified');
  PERFORM * FROM advance_work_order(org,branch,work2,verifier,3,'verified',NULL);
  SELECT * INTO result FROM release_maintenance_block(org,branch,work2,block2,releaser,'Second independent clearance with calibration evidence');
  IF result.remaining_blocks<>0 OR NOT result.can_operate OR (SELECT physical_status FROM nozzles WHERE id=nozzle)<>'active' THEN
   RAISE EXCEPTION 'Asset was not cleared after all blocks resolved'; END IF;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
