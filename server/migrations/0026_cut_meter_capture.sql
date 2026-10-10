-- A cut refers to existing append-only meter readings. It never posts another sale.
CREATE TABLE operational_cut_meter_captures (
 cut_id uuid NOT NULL, organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 nozzle_id uuid NOT NULL, reading_id uuid NOT NULL UNIQUE,
 opening_value numeric(24,9) NOT NULL, closing_value numeric(24,9) NOT NULL,
 measured_l numeric(24,9) NOT NULL CHECK(measured_l>=0), meter_unit text NOT NULL CHECK(meter_unit IN('liter','gallon_us')),
 captured_by uuid NOT NULL, captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(cut_id,nozzle_id),
 FOREIGN KEY(cut_id,nozzle_id) REFERENCES operational_cut_nozzles(cut_id,nozzle_id),
 FOREIGN KEY(reading_id,nozzle_id) REFERENCES nozzle_meter_readings(id,nozzle_id),
 FOREIGN KEY(captured_by,organization_id) REFERENCES users(id,organization_id),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id)
);
CREATE INDEX operational_cut_meter_capture_branch_idx ON operational_cut_meter_captures(branch_id,cut_id);
CREATE TRIGGER operational_cut_meter_captures_immutable BEFORE UPDATE OR DELETE ON operational_cut_meter_captures
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();

CREATE FUNCTION capture_cut_meter(org uuid, branch uuid, target_cut uuid, target_nozzle uuid, target_reading uuid,
 actor uuid, expected_version integer)
 RETURNS TABLE(cut_id uuid,nozzle_id uuid,version integer,opening_value numeric,closing_value numeric,measured_l numeric)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c operational_cuts%ROWTYPE; r nozzle_meter_readings%ROWTYPE; prior operational_cut_meter_captures%ROWTYPE;
 starting numeric(24,9); liters numeric(24,9);
BEGIN
 SELECT * INTO c FROM operational_cuts WHERE id=target_cut AND branch_id=branch AND organization_id=org FOR UPDATE;
 IF c.id IS NULL OR c.status<>'open' OR c.version<>expected_version THEN
  RAISE EXCEPTION 'Cut not open or version changed' USING ERRCODE='40001'; END IF;
 IF NOT EXISTS(SELECT 1 FROM operational_cut_nozzles n WHERE n.cut_id=target_cut AND n.nozzle_id=target_nozzle AND n.participation='expected') THEN
  RAISE EXCEPTION 'Nozzle not expected in this cut' USING ERRCODE='23514'; END IF;
 SELECT * INTO r FROM nozzle_meter_readings WHERE id=target_reading AND nozzle_id=target_nozzle AND
  branch_id=branch AND organization_id=org;
 IF r.id IS NULL OR r.reading_type<>'regular' OR r.captured_at<c.starts_at OR r.captured_at>c.ends_at+interval '24 hours' THEN
  RAISE EXCEPTION 'Regular meter reading outside cut capture period' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users WHERE id=actor AND organization_id=org AND status='active') THEN
  RAISE EXCEPTION 'Cut actor inactive' USING ERRCODE='23514'; END IF;
 IF r.unit IS DISTINCT FROM (SELECT meter_unit FROM operational_cut_nozzles WHERE cut_id=target_cut AND nozzle_id=target_nozzle) THEN
  RAISE EXCEPTION 'Meter unit changed after opening' USING ERRCODE='23514'; END IF;
 SELECT x.* INTO prior FROM operational_cut_meter_captures x JOIN operational_cuts pc ON pc.id=x.cut_id
 WHERE pc.branch_id=branch AND pc.ends_at=c.starts_at AND x.nozzle_id=target_nozzle;
 IF prior.reading_id IS NOT NULL AND (r.prior_reading_id IS DISTINCT FROM prior.reading_id OR
  r.prior_value IS DISTINCT FROM prior.closing_value) THEN
  RAISE EXCEPTION 'Meter reading does not continue previous cut' USING ERRCODE='23514'; END IF;
 IF prior.reading_id IS NULL AND EXISTS(SELECT 1 FROM operational_cuts pc JOIN operational_cut_nozzles pn ON pn.cut_id=pc.id
  WHERE pc.branch_id=branch AND pc.ends_at=c.starts_at AND pn.nozzle_id=target_nozzle AND pn.participation='expected') THEN
  RAISE EXCEPTION 'Previous cut lacks expected nozzle reading' USING ERRCODE='23514'; END IF;
 IF prior.reading_id IS NULL AND NOT EXISTS(SELECT 1 FROM nozzle_meter_readings baseline
   WHERE baseline.id=r.prior_reading_id AND baseline.nozzle_id=target_nozzle AND baseline.captured_at<=c.starts_at) THEN
  RAISE EXCEPTION 'First cut needs a meter baseline at or before its start' USING ERRCODE='23514'; END IF;
 starting:=COALESCE(prior.closing_value,r.prior_value);
 IF starting IS NULL OR r.value<starting OR (prior.reading_id IS NULL AND r.prior_value IS NULL) THEN
  RAISE EXCEPTION 'Meter requires a valid opening baseline and nondecreasing final' USING ERRCODE='23514'; END IF;
 liters:=round((r.value-starting)*CASE WHEN r.unit='gallon_us' THEN 3.785411784 ELSE 1 END,9);
 INSERT INTO operational_cut_meter_captures(cut_id,organization_id,branch_id,nozzle_id,reading_id,opening_value,closing_value,measured_l,meter_unit,captured_by)
 VALUES(target_cut,org,branch,target_nozzle,target_reading,starting,r.value,liters,r.unit,actor);
 UPDATE operational_cuts c2 SET version=c2.version+1 WHERE c2.id=target_cut;
 RETURN QUERY SELECT target_cut,target_nozzle,expected_version+1,starting,r.value,liters;
END; $$;

ALTER TABLE operational_cut_meter_captures ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE operational_cut_meter_captures FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON TABLE operational_cut_meter_captures TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON operational_cut_meter_captures FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON operational_cut_meter_captures FOR INSERT TO dlc_api_runtime WITH CHECK(true);
REVOKE ALL ON FUNCTION capture_cut_meter(uuid,uuid,uuid,uuid,uuid,uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION capture_cut_meter(uuid,uuid,uuid,uuid,uuid,uuid,integer) TO dlc_api_runtime;
