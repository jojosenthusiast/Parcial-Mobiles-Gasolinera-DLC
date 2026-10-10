DO $test$
DECLARE org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); product uuid:=gen_random_uuid();
 tank uuid:=gen_random_uuid(); d1 uuid:=gen_random_uuid(); d2 uuid:=gen_random_uuid(); n1 uuid:=gen_random_uuid(); n2 uuid:=gen_random_uuid(); cut uuid; next_cut uuid; baseline uuid:=gen_random_uuid(); final_one uuid:=gen_random_uuid(); final_two uuid:=gen_random_uuid(); summary record;
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
  SELECT cut_id INTO next_cut FROM generate_operational_cuts(org,branch,'2026-10-07') WHERE slot=2;
  INSERT INTO nozzle_meter_readings(id,organization_id,branch_id,nozzle_id,command_id,request_hash,reading_type,value,unit,source,captured_by,correlation_id,captured_at)
   VALUES(baseline,org,branch,n1,gen_random_uuid(),repeat('a',64),'baseline',100,'gallon_us','manual',actor,gen_random_uuid(),'2026-10-07 11:59+00');
  INSERT INTO nozzle_meter_readings(id,organization_id,branch_id,nozzle_id,command_id,request_hash,reading_type,value,unit,prior_value,prior_reading_id,source,captured_by,correlation_id,captured_at)
   VALUES(final_one,org,branch,n1,gen_random_uuid(),repeat('b',64),'regular',110,'gallon_us',100,baseline,'manual',actor,gen_random_uuid(),'2026-10-07 19:59+00'),
         (final_two,org,branch,n1,gen_random_uuid(),repeat('c',64),'regular',120,'gallon_us',110,final_one,'manual',actor,gen_random_uuid(),'2026-10-08 03:00+00');
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
  SELECT * INTO summary FROM capture_cut_meter(org,branch,cut,n1,final_one,actor,2);
  IF summary.version<>3 OR summary.measured_l<>37.854117840 THEN RAISE EXCEPTION 'Meter conversion/reading failed: %',row_to_json(summary); END IF;
  SELECT * INTO summary FROM record_cut_tank_measurement(org,branch,cut,tank,actor,3,9000,0,25,'2026-10-07 20:00+00','manual','dip-sheet-001');
  IF summary.version<>4 OR summary.measured_l<>9000 THEN RAISE EXCEPTION 'Tank reading was not recorded'; END IF;
  BEGIN PERFORM * FROM capture_cut_meter(org,branch,cut,n2,final_two,actor,4);
   RAISE EXCEPTION 'Excused nozzle accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN PERFORM * FROM record_cut_tank_measurement(org,branch,cut,tank,actor,4,11000,0,25,'2026-10-07 20:00+00','manual',NULL);
   RAISE EXCEPTION 'Over-capacity measurement accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM * FROM open_operational_cut(org,branch,next_cut,actor,1);
  SELECT * INTO summary FROM capture_cut_meter(org,branch,next_cut,n1,final_two,actor,2);
  IF summary.opening_value<>110 OR summary.closing_value<>120 OR summary.measured_l<>37.854117840 THEN
   RAISE EXCEPTION 'Second cut did not continue the prior reading'; END IF;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE'  USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
