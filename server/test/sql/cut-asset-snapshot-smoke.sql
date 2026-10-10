DO $test$
DECLARE org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); product uuid:=gen_random_uuid();
 tank uuid:=gen_random_uuid(); d1 uuid:=gen_random_uuid(); d2 uuid:=gen_random_uuid(); n1 uuid:=gen_random_uuid(); n2 uuid:=gen_random_uuid(); cut uuid; summary record;
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(org,'Snapshot transient');
  INSERT INTO branches(id,organization_id,code,name,zone,status,timezone) VALUES(branch,org,'CUTASSET','Snapshot','central','active','America/El_Salvador');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status)
   VALUES(actor,org,actor::text||'@example.invalid','Operator','NOT_A_LOGIN_HASH','active');
  INSERT INTO fuel_products(id,organization_id,sku,display_name,family) VALUES(product,org,'REG','Regular','regular');
  INSERT INTO branch_fuel_offers(organization_id,branch_id,fuel_product_id,created_by) VALUES(org,branch,product,actor);
  INSERT INTO tanks(id,organization_id,branch_id,code,name,fuel_product_id,nominal_capacity_l,safe_fill_limit_l)
   VALUES(tank,org,branch,'T1','Tank',product,10000,9500);
  INSERT INTO dispensers(id,organization_id,branch_id,code,physical_status) VALUES
    (d1,org,branch,'D1','active'),(d2,org,branch,'D2','maintenance');
  INSERT INTO nozzles(id,organization_id,branch_id,dispenser_id,code,product_code,fuel_product_id,service_mode)
   VALUES(n1,org,branch,d1,'N1','REG',product,'full_service'),(n2,org,branch,d2,'N1','REG',product,'self_service');
  INSERT INTO nozzle_tank_connections(organization_id,branch_id,nozzle_id,tank_id,fuel_product_id,created_by,reason)
   VALUES(org,branch,n1,tank,product,actor,'setup'),(org,branch,n2,tank,product,actor,'setup');
  INSERT INTO operational_cut_profiles(organization_id,branch_id,effective_date,day_start,split_at,timezone,created_by)
   VALUES(org,branch,'2026-10-07','06:00','14:00','America/El_Salvador',actor);
  SELECT cut_id INTO cut FROM generate_operational_cuts(org,branch,'2026-10-07') WHERE slot=1;
  SET LOCAL ROLE dlc_api_runtime;
  SELECT * INTO summary FROM open_operational_cut(org,branch,cut,actor,1);
  IF summary.version<>2 OR summary.expected_dispenser_count<>2 OR summary.expected_nozzle_count<>1 OR summary.excused_nozzle_count<>1 THEN
   RAISE EXCEPTION 'Incorrect dynamic snapshot: %',row_to_json(summary);
  END IF;
  IF (SELECT exclusion_reason FROM operational_cut_nozzles WHERE cut_id=cut AND nozzle_id=n2)<>'dispensador: maintenance' THEN
   RAISE EXCEPTION 'Unavailable dispenser lacks reason'; END IF;
  BEGIN PERFORM * FROM open_operational_cut(org,branch,cut,actor,1); RAISE EXCEPTION 'Replay succeeded';
   EXCEPTION WHEN serialization_failure THEN NULL; END;
  BEGIN UPDATE operational_cut_nozzles SET participation='expected' WHERE cut_id=cut AND nozzle_id=n2;
   RAISE EXCEPTION 'Snapshot mutated'; EXCEPTION WHEN object_not_in_prerequisite_state OR insufficient_privilege THEN NULL; END;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
