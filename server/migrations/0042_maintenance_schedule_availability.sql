CREATE FUNCTION generate_due_maintenance_orders(org uuid,branch uuid,as_of timestamptz,actor uuid)
 RETURNS TABLE(order_id uuid,plan_id uuid,due_at timestamptz)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE p maintenance_plans%ROWTYPE; due_time timestamptz; generated uuid; iterations integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Inactive scheduler' USING ERRCODE='23514'; END IF;
 FOR p IN SELECT x.* FROM maintenance_plans x WHERE x.organization_id=org AND x.branch_id=branch
  AND x.active AND x.cadence_days IS NOT NULL AND x.next_due_at<=as_of FOR UPDATE LOOP
  due_time:=p.next_due_at;iterations:=0;
  WHILE due_time<=as_of LOOP
   iterations:=iterations+1;
   IF iterations>120 THEN RAISE EXCEPTION 'Too many missed intervals; reschedule plan explicitly' USING ERRCODE='23514'; END IF;
   INSERT INTO maintenance_work_orders(organization_id,branch_id,asset_profile_id,plan_id,kind,due_key,description,due_at,created_by)
    VALUES(org,branch,p.asset_profile_id,p.id,'preventive','plan:'||p.id||':'||due_time::text,p.description,due_time,actor)
    ON CONFLICT(branch_id,asset_profile_id,due_key) DO NOTHING RETURNING id INTO generated;
   IF generated IS NOT NULL THEN RETURN QUERY SELECT generated,p.id,due_time; END IF;
   generated:=NULL;due_time:=due_time+make_interval(days=>p.cadence_days);
  END LOOP;
  UPDATE maintenance_plans mp SET next_due_at=due_time WHERE mp.id=p.id;
 END LOOP;
END; $$;
CREATE FUNCTION generate_usage_maintenance_orders(org uuid,branch uuid,observation uuid,actor uuid)
 RETURNS TABLE(order_id uuid,plan_id uuid,due_usage numeric)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE o equipment_observations%ROWTYPE; p maintenance_plans%ROWTYPE; generated uuid;
BEGIN
 SELECT x.* INTO o FROM equipment_observations x WHERE x.id=observation AND x.organization_id=org AND x.branch_id=branch
  AND x.metric='usage_counter' AND x.value IS NOT NULL AND x.value>=0;
 IF o.id IS NULL THEN RAISE EXCEPTION 'A known usage counter is required' USING ERRCODE='23514'; END IF;
 FOR p IN SELECT x.* FROM maintenance_plans x WHERE x.organization_id=org AND x.branch_id=branch AND
  x.asset_profile_id=o.asset_profile_id AND x.active AND x.cadence_usage IS NOT NULL AND
  x.usage_unit=o.unit AND x.next_due_usage<=o.value FOR UPDATE LOOP
  INSERT INTO maintenance_work_orders(organization_id,branch_id,asset_profile_id,plan_id,kind,due_key,description,created_by)
    VALUES(org,branch,p.asset_profile_id,p.id,'preventive','usage:'||p.id||':'||p.next_due_usage::text,p.description,actor)
    ON CONFLICT(branch_id,asset_profile_id,due_key) DO NOTHING RETURNING id INTO generated;
  IF generated IS NOT NULL THEN RETURN QUERY SELECT generated,p.id,p.next_due_usage; END IF;
  UPDATE maintenance_plans mp SET next_due_usage=p.next_due_usage+
   (floor((o.value-p.next_due_usage)/p.cadence_usage)+1)*p.cadence_usage WHERE mp.id=p.id;
  generated:=NULL;
 END LOOP;
END; $$;
CREATE FUNCTION transition_asset_interval(org uuid,branch uuid,asset uuid,actor uuid,next_reason text,effective timestamptz,
 source_order uuid) RETURNS uuid LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE prior asset_operating_intervals%ROWTYPE; aid uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM maintenance_asset_profiles p WHERE p.id=asset AND p.branch_id=branch AND p.organization_id=org) OR
  NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Asset or actor outside branch' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('asset-interval:'||asset::text,0));
 SELECT x.* INTO prior FROM asset_operating_intervals x WHERE x.asset_profile_id=asset AND x.ended_at IS NULL FOR UPDATE;
 IF prior.id IS NOT NULL THEN
  IF effective<=prior.started_at OR prior.reason=next_reason THEN
   RAISE EXCEPTION 'Interval boundary or status is invalid' USING ERRCODE='23514'; END IF;
  UPDATE asset_operating_intervals SET ended_at=effective WHERE id=prior.id;
 END IF;
 INSERT INTO asset_operating_intervals(organization_id,branch_id,asset_profile_id,reason,started_at,source_order_id,recorded_by)
 VALUES(org,branch,asset,next_reason,effective,source_order,actor) RETURNING id INTO aid;
 RETURN aid;
END; $$;
CREATE FUNCTION asset_availability(org uuid,branch uuid,asset uuid,period_start timestamptz,period_end timestamptz)
 RETURNS TABLE(available_seconds numeric,covered_seconds numeric,unknown_seconds numeric,availability_pct numeric)
 LANGUAGE plpgsql STABLE SET search_path=public,pg_temp AS $$
DECLARE covered numeric; available numeric; total numeric;
BEGIN
 IF period_end<=period_start OR period_end-period_start>interval '366 days' OR NOT EXISTS(
  SELECT 1 FROM maintenance_asset_profiles p WHERE p.id=asset AND p.organization_id=org AND p.branch_id=branch) THEN
  RAISE EXCEPTION 'Invalid availability period or asset' USING ERRCODE='23514'; END IF;
 total:=extract(epoch FROM period_end-period_start);
 SELECT COALESCE(sum(extract(epoch FROM least(COALESCE(i.ended_at,period_end),period_end)-greatest(i.started_at,period_start))),0),
  COALESCE(sum(extract(epoch FROM least(COALESCE(i.ended_at,period_end),period_end)-greatest(i.started_at,period_start)))
   FILTER(WHERE i.reason='available'),0) INTO covered,available
 FROM asset_operating_intervals i WHERE i.asset_profile_id=asset AND i.organization_id=org AND i.branch_id=branch AND
  i.started_at<period_end AND (i.ended_at IS NULL OR i.ended_at>period_start);
 RETURN QUERY SELECT available,covered,greatest(total-covered,0),round(available/total*100,2);
END; $$;
REVOKE ALL ON FUNCTION generate_due_maintenance_orders(uuid,uuid,timestamptz,uuid),
 generate_usage_maintenance_orders(uuid,uuid,uuid,uuid),transition_asset_interval(uuid,uuid,uuid,uuid,text,timestamptz,uuid),
 asset_availability(uuid,uuid,uuid,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION generate_due_maintenance_orders(uuid,uuid,timestamptz,uuid),
 generate_usage_maintenance_orders(uuid,uuid,uuid,uuid),transition_asset_interval(uuid,uuid,uuid,uuid,text,timestamptz,uuid),
 asset_availability(uuid,uuid,uuid,timestamptz,timestamptz) TO dlc_api_runtime;
