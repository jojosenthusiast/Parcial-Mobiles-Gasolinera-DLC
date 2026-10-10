ALTER TABLE maintenance_work_orders ADD COLUMN target_block_id uuid REFERENCES asset_blocks(id);
CREATE FUNCTION validate_work_order_block() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a maintenance_asset_profiles%ROWTYPE;
BEGIN
 IF NEW.target_block_id IS NULL THEN RETURN NEW; END IF;
 SELECT * INTO a FROM maintenance_asset_profiles WHERE id=NEW.asset_profile_id;
 IF NOT EXISTS(SELECT 1 FROM asset_blocks b WHERE b.id=NEW.target_block_id AND b.organization_id=NEW.organization_id
   AND b.branch_id=NEW.branch_id AND b.asset_type=a.asset_type AND b.asset_id=a.asset_id AND b.resolved_at IS NULL) THEN
  RAISE EXCEPTION 'Work order block does not match asset' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER work_order_block_guard BEFORE INSERT OR UPDATE OF target_block_id ON maintenance_work_orders
 FOR EACH ROW EXECUTE FUNCTION validate_work_order_block();
CREATE TABLE maintenance_order_tasks (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 order_id uuid NOT NULL,description text NOT NULL CHECK(length(btrim(description)) BETWEEN 5 AND 500),
 result text NOT NULL CHECK(length(btrim(result)) BETWEEN 5 AND 1000),
 labor_minutes integer CHECK(labor_minutes>=0),labor_estimate_usd numeric(18,2) CHECK(labor_estimate_usd>=0),
 completed_by uuid NOT NULL,completed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(order_id,organization_id,branch_id) REFERENCES maintenance_work_orders(id,organization_id,branch_id),
 FOREIGN KEY(completed_by,organization_id) REFERENCES users(id,organization_id)
);
CREATE TABLE maintenance_order_parts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 order_id uuid NOT NULL,part_description text NOT NULL CHECK(length(btrim(part_description)) BETWEEN 2 AND 160),
 quantity numeric(18,3) NOT NULL CHECK(quantity>0),estimated_unit_cost_usd numeric(18,2) CHECK(estimated_unit_cost_usd>=0),
 source_reference text,recorded_by uuid NOT NULL,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(order_id,organization_id,branch_id) REFERENCES maintenance_work_orders(id,organization_id,branch_id),
 FOREIGN KEY(recorded_by,organization_id) REFERENCES users(id,organization_id)
);
CREATE TABLE equipment_observations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 asset_profile_id uuid NOT NULL,work_order_id uuid,
 metric text NOT NULL CHECK(metric IN('water_level','fuel_temperature','line_pressure','leak_test','calibration','usage_counter','other')),
 value numeric(24,9),unit text, outcome text NOT NULL CHECK(outcome IN('pass','fail','observed','unknown')),
 source text NOT NULL CHECK(source IN('manual','device','laboratory')),
 instrument_reference text,evidence_reference text,observed_at timestamptz NOT NULL,recorded_by uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(asset_profile_id,organization_id,branch_id) REFERENCES maintenance_asset_profiles(id,organization_id,branch_id),
 FOREIGN KEY(work_order_id,organization_id,branch_id) REFERENCES maintenance_work_orders(id,organization_id,branch_id),
 FOREIGN KEY(recorded_by,organization_id) REFERENCES users(id,organization_id),
 CHECK((outcome='unknown' AND value IS NULL) OR outcome<>'unknown'),
 CHECK((source='device' AND instrument_reference IS NOT NULL) OR source<>'device'),
 CHECK(value IS NULL OR unit IS NOT NULL)
);
CREATE INDEX equipment_observations_recent_idx ON equipment_observations(asset_profile_id,metric,observed_at DESC);
CREATE TABLE asset_operating_intervals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 asset_profile_id uuid NOT NULL,reason text NOT NULL CHECK(reason IN('available','maintenance','technical_failure','staffing','no_product','closed')),
 started_at timestamptz NOT NULL,ended_at timestamptz,
 source_order_id uuid,recorded_by uuid NOT NULL,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(asset_profile_id,organization_id,branch_id) REFERENCES maintenance_asset_profiles(id,organization_id,branch_id),
 FOREIGN KEY(source_order_id,organization_id,branch_id) REFERENCES maintenance_work_orders(id,organization_id,branch_id),
 FOREIGN KEY(recorded_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(ended_at IS NULL OR ended_at>started_at)
);
CREATE INDEX asset_interval_history_idx ON asset_operating_intervals(asset_profile_id,started_at DESC);
CREATE UNIQUE INDEX one_open_operating_interval ON asset_operating_intervals(asset_profile_id) WHERE ended_at IS NULL;
CREATE FUNCTION guard_asset_interval() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('asset-interval:'||NEW.asset_profile_id::text,0));
 IF EXISTS(SELECT 1 FROM asset_operating_intervals x WHERE x.asset_profile_id=NEW.asset_profile_id
  AND x.id<>NEW.id AND tstzrange(x.started_at,x.ended_at,'[)') && tstzrange(NEW.started_at,NEW.ended_at,'[)')) THEN
  RAISE EXCEPTION 'Asset status intervals overlap' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER asset_interval_overlap BEFORE INSERT OR UPDATE ON asset_operating_intervals FOR EACH ROW EXECUTE FUNCTION guard_asset_interval();

CREATE FUNCTION advance_work_order(org uuid,branch uuid,target_order uuid,actor uuid,expected_version integer,
 next_status text,diagnosis_note text)
 RETURNS TABLE(order_id uuid,status text,version integer)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE w maintenance_work_orders%ROWTYPE;
BEGIN
 SELECT x.* INTO w FROM maintenance_work_orders x WHERE x.id=target_order AND x.organization_id=org AND x.branch_id=branch FOR UPDATE;
 IF w.id IS NULL OR w.version<>expected_version OR NOT ((w.status='planned' AND next_status IN('in_progress','cancelled')) OR
  (w.status='in_progress' AND next_status='completed') OR (w.status='completed' AND next_status='verified')) THEN
  RAISE EXCEPTION 'Work order state/version changed' USING ERRCODE='40001'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') OR
  (next_status='verified' AND w.completed_by=actor) THEN
  RAISE EXCEPTION 'Verification needs a different active person' USING ERRCODE='23514'; END IF;
 IF next_status='completed' AND (NOT EXISTS(SELECT 1 FROM maintenance_order_tasks t WHERE t.order_id=target_order) OR
  length(btrim(COALESCE(diagnosis_note,'')))<8) THEN
  RAISE EXCEPTION 'Completion needs diagnosis and at least one recorded task' USING ERRCODE='23514'; END IF;
 IF next_status='verified' AND EXISTS(SELECT 1 FROM equipment_observations o WHERE o.work_order_id=target_order AND o.outcome='fail'
  AND NOT EXISTS(SELECT 1 FROM equipment_observations newer WHERE newer.work_order_id=target_order AND newer.metric=o.metric
   AND newer.outcome='pass' AND newer.observed_at>o.observed_at)) THEN
  RAISE EXCEPTION 'Failed technical observation has no passing retest' USING ERRCODE='23514'; END IF;
 UPDATE maintenance_work_orders x SET status=next_status,version=x.version+1,
  started_at=CASE WHEN next_status='in_progress' THEN clock_timestamp() ELSE x.started_at END,
  diagnosis=CASE WHEN next_status='completed' THEN diagnosis_note ELSE x.diagnosis END,
  completed_at=CASE WHEN next_status='completed' THEN clock_timestamp() ELSE x.completed_at END,
  completed_by=CASE WHEN next_status='completed' THEN actor ELSE x.completed_by END,
  verified_at=CASE WHEN next_status='verified' THEN clock_timestamp() ELSE x.verified_at END,
  verified_by=CASE WHEN next_status='verified' THEN actor ELSE x.verified_by END WHERE x.id=target_order;
 RETURN QUERY SELECT target_order,next_status,expected_version+1;
END; $$;
CREATE FUNCTION release_maintenance_block(org uuid,branch uuid,target_order uuid,target_block uuid,actor uuid,release_reason text)
 RETURNS TABLE(block_id uuid,remaining_blocks integer,can_operate boolean)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE w maintenance_work_orders%ROWTYPE; asset maintenance_asset_profiles%ROWTYPE; block asset_blocks%ROWTYPE; remains integer;
BEGIN
 SELECT x.* INTO w FROM maintenance_work_orders x WHERE x.id=target_order AND x.organization_id=org AND x.branch_id=branch FOR UPDATE;
 SELECT x.* INTO asset FROM maintenance_asset_profiles x WHERE x.id=w.asset_profile_id;
 SELECT x.* INTO block FROM asset_blocks x WHERE x.id=target_block AND x.organization_id=org AND x.branch_id=branch FOR UPDATE;
 IF w.id IS NULL OR w.status<>'verified' OR asset.id IS NULL OR block.id IS NULL OR block.resolved_at IS NOT NULL OR
  block.asset_type<>asset.asset_type OR block.asset_id<>asset.asset_id OR w.target_block_id IS DISTINCT FROM target_block OR
  (w.incident_id IS NOT NULL AND block.incident_id IS DISTINCT FROM w.incident_id) OR
  (w.verified_by IS NULL OR w.verified_by=actor) THEN
  RAISE EXCEPTION 'Verified independent work order cannot release this block' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Inactive release actor' USING ERRCODE='23514'; END IF;
 UPDATE asset_blocks SET resolved_by=actor,resolved_at=clock_timestamp(),resolution=release_reason WHERE id=target_block;
 SELECT count(*) INTO remains FROM asset_blocks b WHERE b.organization_id=org AND b.branch_id=branch AND
   b.asset_type=asset.asset_type AND b.asset_id=asset.asset_id AND b.resolved_at IS NULL;
 IF remains=0 THEN
  IF asset.asset_type='nozzle' THEN UPDATE nozzles SET physical_status='active',version=version+1 WHERE id=asset.asset_id AND physical_status IN('maintenance','offline');
  ELSIF asset.asset_type='dispenser' THEN UPDATE dispensers SET physical_status='active',version=version+1 WHERE id=asset.asset_id AND physical_status IN('maintenance','offline');
  ELSIF asset.asset_type='tank' THEN UPDATE tanks SET status='active',version=version+1 WHERE id=asset.asset_id AND status IN('maintenance','offline'); END IF;
 END IF;
 RETURN QUERY SELECT target_block,remains,remains=0;
END; $$;

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['maintenance_order_tasks','maintenance_order_parts','equipment_observations','asset_operating_intervals'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
 END LOOP;
END $$;
GRANT UPDATE ON asset_operating_intervals TO dlc_api_runtime;
CREATE POLICY dlc_api_update ON asset_operating_intervals FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
REVOKE ALL ON FUNCTION validate_work_order_block(),guard_asset_interval(),advance_work_order(uuid,uuid,uuid,uuid,integer,text,text),
 release_maintenance_block(uuid,uuid,uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION advance_work_order(uuid,uuid,uuid,uuid,integer,text,text),
 release_maintenance_block(uuid,uuid,uuid,uuid,uuid,text) TO dlc_api_runtime;
