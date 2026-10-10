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
  INSERT INTO maintenance_plans(organization_id,branch_id,asset_profile_id,code,description,cadence_days,next_due_at,created_by)
   VALUES(org,branch,asset,'DAILY','Daily safety inspection',1,'2026-10-01 12:00+00',worker);
  SET LOCAL ROLE dlc_api_runtime;
  IF (SELECT count(*) FROM generate_due_maintenance_orders(org,branch,'2026-10-03 12:00+00',worker))<>3 OR
     (SELECT count(*) FROM generate_due_maintenance_orders(org,branch,'2026-10-03 12:00+00',worker))<>0 THEN
   RAISE EXCEPTION 'Preventive generation not idempotent'; END IF;
  PERFORM transition_asset_interval(org,branch,asset,worker,'available','2026-10-01 01:00+00',NULL);
  PERFORM transition_asset_interval(org,branch,asset,worker,'maintenance','2026-10-01 02:00+00',NULL);
  PERFORM transition_asset_interval(org,branch,asset,worker,'available','2026-10-01 04:00+00',NULL);
  IF (SELECT availability_pct FROM asset_availability(org,branch,asset,'2026-10-01 00:00+00','2026-10-01 05:00+00'))<>40 OR
     (SELECT unknown_seconds FROM asset_availability(org,branch,asset,'2026-10-01 00:00+00','2026-10-01 05:00+00'))<>3600 THEN
   RAISE EXCEPTION 'Missing interval confused with uptime'; END IF;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
