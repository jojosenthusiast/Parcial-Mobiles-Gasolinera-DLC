DO $test$
DECLARE org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); legacy uuid:=gen_random_uuid(); bad uuid:=gen_random_uuid();
 actor uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); tank uuid:=gen_random_uuid(); d1 uuid:=gen_random_uuid(); n1 uuid:=gen_random_uuid();
 profile uuid:=gen_random_uuid(); morning uuid; evening uuid; next_morning uuid; next_evening uuid; summary record;
 baseline uuid:=gen_random_uuid(); r1 uuid:=gen_random_uuid(); r2 uuid:=gen_random_uuid(); r3 uuid:=gen_random_uuid();
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(org,'Evening window transient');
  INSERT INTO branches(id,organization_id,code,name,zone,status,timezone) VALUES
   (branch,org,'EVEWIN','Evening','central','active','America/El_Salvador'),
   (legacy,org,'LEGWIN','Legacy','central','active','America/El_Salvador'),
   (bad,org,'BADWIN','Bad','central','active','America/El_Salvador');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status)
   VALUES(actor,org,actor::text||'@example.invalid','Operator','NOT_A_LOGIN_HASH','active');
  INSERT INTO fuel_products(id,organization_id,sku,display_name,family) VALUES(product,org,'REG','Regular','regular');
  INSERT INTO branch_fuel_offers(organization_id,branch_id,fuel_product_id,created_by) VALUES(org,branch,product,actor);
  INSERT INTO tanks(id,organization_id,branch_id,code,name,fuel_product_id,nominal_capacity_l,safe_fill_limit_l)
   VALUES(tank,org,branch,'T1','Tank',product,10000,9900);
  INSERT INTO dispensers(id,organization_id,branch_id,code,physical_status) VALUES(d1,org,branch,'D1','active');
  INSERT INTO nozzles(id,organization_id,branch_id,dispenser_id,code,product_code,fuel_product_id,service_mode)
   VALUES(n1,org,branch,d1,'N1','REG',product,'full_service');
  INSERT INTO nozzle_tank_connections(organization_id,branch_id,nozzle_id,tank_id,fuel_product_id,created_by,reason)
   VALUES(org,branch,n1,tank,product,actor,'setup');
  SET LOCAL ROLE dlc_api_runtime;

  -- The declared evening end must fall after the split inside one 24-hour day, and differ from both anchors.
  BEGIN
   INSERT INTO operational_cut_profiles(organization_id,branch_id,effective_date,day_start,split_at,day_end,timezone,created_by)
    VALUES(org,bad,'2026-10-01','06:00','14:00','10:00','America/El_Salvador',actor);
   RAISE EXCEPTION 'An evening end before the split was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
   INSERT INTO operational_cut_profiles(organization_id,branch_id,effective_date,day_start,split_at,day_end,timezone,created_by)
    VALUES(org,bad,'2026-10-01','06:00','14:00','14:00','America/El_Salvador',actor);
   RAISE EXCEPTION 'An evening end equal to the split was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- Academic template: morning 06:00-14:00 and evening 14:00-22:00 local, 22:00-06:00 is not a cut.
  INSERT INTO operational_cut_profiles(id,organization_id,branch_id,effective_date,day_start,split_at,day_end,timezone,created_by)
   VALUES(profile,org,branch,'2026-10-01','06:00','14:00','22:00','America/El_Salvador',actor);
  SELECT cut_id INTO morning FROM generate_operational_cuts(org,branch,'2026-10-01') WHERE slot=1;
  SELECT cut_id INTO evening FROM generate_operational_cuts(org,branch,'2026-10-01') WHERE slot=2;
  PERFORM * FROM generate_operational_cuts(org,branch,'2026-10-01');
  SELECT cut_id INTO next_morning FROM generate_operational_cuts(org,branch,'2026-10-02') WHERE slot=1;
  SELECT cut_id INTO next_evening FROM generate_operational_cuts(org,branch,'2026-10-02') WHERE slot=2;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF (SELECT count(*) FROM operational_cuts WHERE branch_id=branch)<>4 THEN RAISE EXCEPTION 'Replay created extra cuts'; END IF;
  IF NOT EXISTS(SELECT 1 FROM operational_cuts WHERE id=morning AND starts_at='2026-10-01 12:00+00' AND ends_at='2026-10-01 20:00+00')
   OR NOT EXISTS(SELECT 1 FROM operational_cuts WHERE id=evening AND starts_at='2026-10-01 20:00+00' AND ends_at='2026-10-02 04:00+00')
   OR NOT EXISTS(SELECT 1 FROM operational_cuts WHERE id=next_morning AND starts_at='2026-10-02 12:00+00' AND ends_at='2026-10-02 20:00+00') THEN
   RAISE EXCEPTION 'Windows are not 06-14 and 14-22 local time';
  END IF;
  IF EXISTS(SELECT 1 FROM operational_cuts WHERE branch_id=branch AND starts_at<'2026-10-02 12:00+00' AND ends_at>'2026-10-02 04:00+00') THEN
   RAISE EXCEPTION 'The 22:00-06:00 period is covered by a cut';
  END IF;
  IF previous_operational_cut(morning) IS NOT NULL OR previous_operational_cut(evening)<>morning
   OR previous_operational_cut(next_morning)<>evening OR previous_operational_cut(next_evening)<>next_morning THEN
   RAISE EXCEPTION 'Previous-cut chain is broken across the non-cut period';
  END IF;

  -- No overlapping windows, even for a hand-built, internally contiguous day.
  BEGIN
   INSERT INTO operational_cuts(organization_id,branch_id,operational_date,slot,profile_id,starts_at,ends_at) VALUES
    (org,branch,'2026-10-09',1,profile,'2026-10-01 18:00+00','2026-10-01 19:00+00'),
    (org,branch,'2026-10-09',2,profile,'2026-10-01 19:00+00','2026-10-01 20:00+00');
   SET CONSTRAINTS ALL IMMEDIATE;
   RAISE EXCEPTION 'Overlapping windows were accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- A branch without a declared non-cut period still cannot leave an undeclared gap between days.
  INSERT INTO operational_cut_profiles(organization_id,branch_id,effective_date,day_start,split_at,timezone,created_by)
   VALUES(org,legacy,'2026-10-01','06:00','14:00','America/El_Salvador',actor),
         (org,legacy,'2026-10-02','08:00','14:00','America/El_Salvador',actor);
  PERFORM * FROM generate_operational_cuts(org,legacy,'2026-10-01');
  IF (SELECT ends_at-starts_at FROM operational_cuts WHERE branch_id=legacy AND slot=2)<>interval '16 hours' THEN
   RAISE EXCEPTION 'Legacy profile must keep its 06-14 and 14-06 windows'; END IF;
  BEGIN PERFORM * FROM generate_operational_cuts(org,legacy,'2026-10-02');
   RAISE EXCEPTION 'Undeclared gap accepted'; EXCEPTION WHEN check_violation THEN NULL; END;

  -- Meter continuity survives the non-cut period: the next morning continues the previous evening reading.
  RESET ROLE;
  INSERT INTO nozzle_meter_readings(id,organization_id,branch_id,nozzle_id,command_id,request_hash,reading_type,value,unit,source,captured_by,correlation_id,captured_at)
   VALUES(baseline,org,branch,n1,gen_random_uuid(),repeat('a',64),'baseline',100,'gallon_us','manual',actor,gen_random_uuid(),'2026-10-01 11:59+00');
  INSERT INTO nozzle_meter_readings(id,organization_id,branch_id,nozzle_id,command_id,request_hash,reading_type,value,unit,prior_value,prior_reading_id,source,captured_by,correlation_id,captured_at)
   VALUES(r1,org,branch,n1,gen_random_uuid(),repeat('b',64),'regular',110,'gallon_us',100,baseline,'manual',actor,gen_random_uuid(),'2026-10-01 19:59+00'),
         (r2,org,branch,n1,gen_random_uuid(),repeat('c',64),'regular',120,'gallon_us',110,r1,'manual',actor,gen_random_uuid(),'2026-10-02 03:59+00'),
         (r3,org,branch,n1,gen_random_uuid(),repeat('d',64),'regular',135,'gallon_us',120,r2,'manual',actor,gen_random_uuid(),'2026-10-02 19:59+00');
  INSERT INTO operational_cut_reconciliation_policies(organization_id,branch_id,effective_date,meter_tolerance_l,tank_tolerance_l,collection_tolerance_usd,created_by)
   VALUES(org,branch,'2026-10-01',1000,10,0.01,actor);
  INSERT INTO inventory_movements(organization_id,branch_id,tank_id,fuel_product_id,movement_type,command_id,request_hash,source_type,
   quantity_entered,unit_entered,conversion_factor_to_l,observed_l,delta_l,volume_basis,valuation_quality,
   before_quantity_l,after_quantity_l,actor_user_id,occurred_at,correlation_id)
   VALUES(org,branch,tank,product,'opening',gen_random_uuid(),repeat('e',64),'opening_balance',9000,'liter',1,9000,9000,'nominal','unknown',0,9000,actor,'2026-10-01 11:58+00',gen_random_uuid());
  -- A delivery received at 02:00 local, inside the non-cut period.
  INSERT INTO inventory_movements(organization_id,branch_id,tank_id,fuel_product_id,movement_type,command_id,request_hash,source_type,document_reference,
   quantity_entered,unit_entered,conversion_factor_to_l,observed_l,delta_l,volume_basis,valuation_quality,
   before_quantity_l,after_quantity_l,actor_user_id,occurred_at,correlation_id)
   VALUES(org,branch,tank,product,'receipt',gen_random_uuid(),repeat('f',64),'delivery','NIGHT-DELIVERY-1',500,'liter',1,500,500,'nominal','unknown',9000,9500,actor,'2026-10-02 08:00+00',gen_random_uuid());
  SET LOCAL ROLE dlc_api_runtime;
  PERFORM * FROM open_operational_cut(org,branch,morning,actor,1);
  PERFORM * FROM open_operational_cut(org,branch,evening,actor,1);
  PERFORM * FROM open_operational_cut(org,branch,next_morning,actor,1);
  BEGIN PERFORM * FROM capture_cut_meter(org,branch,next_morning,n1,r3,actor,2);
   RAISE EXCEPTION 'Morning captured without the previous evening reading'; EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM * FROM capture_cut_meter(org,branch,morning,n1,r1,actor,2);
  SELECT * INTO summary FROM capture_cut_meter(org,branch,evening,n1,r2,actor,2);
  IF summary.opening_value<>110 OR summary.closing_value<>120 THEN RAISE EXCEPTION 'Evening did not continue the morning'; END IF;
  SELECT * INTO summary FROM capture_cut_meter(org,branch,next_morning,n1,r3,actor,2);
  IF summary.opening_value<>120 OR summary.closing_value<>135 THEN RAISE EXCEPTION 'Next morning did not continue the previous evening across 22:00-06:00: %',row_to_json(summary); END IF;

  -- Preparation, ordered closing and the carried-over accounting of the non-cut period.
  PERFORM * FROM record_cut_tank_measurement(org,branch,morning,tank,actor,3,9000,0,25,'2026-10-01 19:59+00','manual',NULL);
  PERFORM * FROM record_cut_tank_measurement(org,branch,evening,tank,actor,3,9000,0,25,'2026-10-02 03:59+00','manual',NULL);
  PERFORM * FROM record_cut_tank_measurement(org,branch,next_morning,tank,actor,3,9500,0,25,'2026-10-02 19:59+00','manual',NULL);
  PERFORM * FROM prepare_operational_cut(org,branch,morning,actor,4);
  PERFORM * FROM prepare_operational_cut(org,branch,evening,actor,4);
  SELECT * INTO summary FROM prepare_operational_cut(org,branch,next_morning,actor,4);
  IF summary.review_required THEN RAISE EXCEPTION 'The night delivery should not need review: it belongs to the next morning cut'; END IF;
  IF (SELECT (product_summary->0->>'receiptsLiters')::numeric FROM operational_cut_preparations WHERE cut_id=evening)<>0
   OR (SELECT (product_summary->0->>'receiptsLiters')::numeric FROM operational_cut_preparations WHERE cut_id=next_morning)<>500 THEN
   RAISE EXCEPTION 'Night movements were not reconciled in the next morning cut'; END IF;
  BEGIN PERFORM * FROM close_operational_cut(org,branch,next_morning,actor,5);
   RAISE EXCEPTION 'Next morning closed before the previous evening'; EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM * FROM close_operational_cut(org,branch,morning,actor,5);
  PERFORM * FROM close_operational_cut(org,branch,evening,actor,5);
  PERFORM * FROM close_operational_cut(org,branch,next_morning,actor,5);
  IF (SELECT (snapshot->>'accountingStartsAt')::timestamptz FROM operational_cut_closures WHERE cut_id=next_morning)<>'2026-10-02 04:00+00'
   OR (SELECT (snapshot->>'accountingStartsAt')::timestamptz FROM operational_cut_closures WHERE cut_id=morning)<>'2026-10-01 12:00+00' THEN
   RAISE EXCEPTION 'Closure snapshot lacks the accounting start'; END IF;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
