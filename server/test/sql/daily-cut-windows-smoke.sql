DO $test$
DECLARE org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); night_branch uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid();
 profile_one uuid:=gen_random_uuid(); profile_two uuid:=gen_random_uuid(); first_id uuid; n integer;
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(org,'Cut transient');
  INSERT INTO branches(id,organization_id,code,name,zone,status,timezone)
   VALUES(branch,org,'CUTTEST','Cuts','occidental','active','America/El_Salvador'),
         (night_branch,org,'NIGHT','Night','central','active','America/El_Salvador');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash)
   VALUES(actor,org,actor::text||'@example.invalid','Operator','NOT_A_LOGIN_HASH');
  SET LOCAL ROLE dlc_api_runtime;
  BEGIN
   PERFORM * FROM generate_operational_cuts(org,branch,DATE '2026-10-07');
   RAISE EXCEPTION 'Unconfigured branch generated cuts';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO operational_cut_profiles(id,organization_id,branch_id,effective_date,day_start,split_at,timezone,created_by)
   VALUES(profile_one,org,branch,'2026-10-07','06:00','14:00','America/El_Salvador',actor),
         (profile_two,org,night_branch,'2026-10-08','22:00','06:00','America/El_Salvador',actor);
  SELECT cut_id INTO first_id FROM generate_operational_cuts(org,branch,DATE '2026-10-07') WHERE slot=1;
  PERFORM * FROM generate_operational_cuts(org,branch,DATE '2026-10-07');
  IF first_id IS DISTINCT FROM (SELECT id FROM operational_cuts WHERE branch_id=branch AND operational_date='2026-10-07' AND slot=1) THEN
   RAISE EXCEPTION 'Replay changed the first cut';
  END IF;
  PERFORM * FROM generate_operational_cuts(org,branch,DATE '2026-10-08');
  PERFORM * FROM generate_operational_cuts(org,night_branch,DATE '2026-10-08');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT count(*) INTO n FROM operational_cuts WHERE branch_id=branch;
  IF n<>4 OR EXISTS(SELECT 1 FROM operational_cuts c WHERE c.operational_date='2026-10-07' AND c.branch_id=branch AND
     ((c.slot=1 AND c.ends_at-c.starts_at<>interval '8 hours') OR (c.slot=2 AND c.ends_at-c.starts_at<>interval '16 hours'))) THEN
   RAISE EXCEPTION 'The normal day is not exactly two 8/16-hour windows';
  END IF;
  IF EXISTS(SELECT 1 FROM operational_cuts c WHERE c.operational_date='2026-10-08' AND c.branch_id=night_branch AND
     ((c.slot=1 AND c.ends_at-c.starts_at<>interval '8 hours') OR (c.slot=2 AND c.ends_at-c.starts_at<>interval '16 hours'))) THEN
   RAISE EXCEPTION 'The midnight-crossing day has a gap or third window';
  END IF;
  BEGIN
   INSERT INTO operational_cuts(organization_id,branch_id,operational_date,slot,profile_id,starts_at,ends_at)
    VALUES(org,night_branch,'2026-10-09',1,profile_two,'2026-10-10 04:00+00','2026-10-10 12:00+00');
   SET CONSTRAINTS ALL IMMEDIATE;
   RAISE EXCEPTION 'An orphan cut was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
