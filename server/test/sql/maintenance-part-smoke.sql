DO $test$
DECLARE org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); worker uuid:=gen_random_uuid(); verifier uuid:=gen_random_uuid(); releaser uuid:=gen_random_uuid();
 product uuid:=gen_random_uuid(); dispenser uuid:=gen_random_uuid(); nozzle uuid:=gen_random_uuid(); asset uuid:=gen_random_uuid();
 block1 uuid:=gen_random_uuid(); block2 uuid:=gen_random_uuid(); work uuid:=gen_random_uuid(); work2 uuid:=gen_random_uuid(); result record; store_product uuid:=gen_random_uuid(); catalog uuid:=gen_random_uuid(); store_lot uuid:=gen_random_uuid();
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
  INSERT INTO store_catalog_products(id,organization_id,sku,kind,category,presentation,unit,created_by)
   VALUES(catalog,org,'HOSE','part','Repuestos','Manguera','unit',worker);
  INSERT INTO pos_products(id,organization_id,branch_id,sku,kind,expiry_required,created_by)
   VALUES(store_product,org,branch,'HOSE','store',false,worker);
  INSERT INTO branch_assortments(organization_id,branch_id,catalog_product_id,pos_product_id,created_by)
   VALUES(org,branch,catalog,store_product,worker);
  INSERT INTO pos_offer_versions(organization_id,branch_id,product_id,version,description,active,price_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,store_product,1,'Manguera',true,10,gen_random_uuid(),repeat('a',64),worker,gen_random_uuid());
  INSERT INTO pos_stock_lots(id,organization_id,branch_id,product_id,lot_code,quantity_received,unit_cost_usd,source_reference,command_id,request_hash,received_by,correlation_id)
   VALUES(store_lot,org,branch,store_product,'HOSE-1',3,7,'PURCHASE-1',gen_random_uuid(),repeat('b',64),worker,gen_random_uuid());
  SET LOCAL ROLE dlc_api_runtime;
  BEGIN UPDATE asset_blocks SET resolved_by=worker,resolved_at=clock_timestamp(),resolution='shortcut' WHERE id=block1;
   RAISE EXCEPTION 'Technical block bypassed verified order'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN UPDATE nozzles SET physical_status='active' WHERE id=nozzle;
   RAISE EXCEPTION 'Blocked nozzle activated directly'; EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM * FROM advance_work_order(org,branch,work,worker,1,'in_progress',NULL);
  PERFORM use_maintenance_part(org,branch,worker,work,store_lot,1,'Replace hose from stock',gen_random_uuid(),repeat('c',64),gen_random_uuid());
  IF (SELECT sum(delta_units) FROM pos_stock_movements WHERE lot_id=store_lot)<>2
   OR (SELECT cost_usd FROM maintenance_part_consumptions WHERE lot_id=store_lot)<>7 THEN RAISE EXCEPTION 'Part consumption wrong'; END IF;
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
