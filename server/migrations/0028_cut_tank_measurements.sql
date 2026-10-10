-- Physical tank readings are evidence; they do not themselves modify inventory.
CREATE TABLE operational_cut_tank_measurements (
 cut_id uuid NOT NULL, organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 tank_id uuid NOT NULL, fuel_product_id uuid NOT NULL,
 measured_l numeric(24,9) NOT NULL CHECK(measured_l>=0), water_l numeric(24,9) CHECK(water_l>=0),
 temperature_c numeric(8,4), observed_at timestamptz NOT NULL,
 source text NOT NULL CHECK(source IN('manual','device','simulated')),
 evidence_reference text, captured_by uuid NOT NULL, captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(cut_id,tank_id),
 FOREIGN KEY(cut_id,organization_id,branch_id) REFERENCES operational_cuts(id,organization_id,branch_id),
 FOREIGN KEY(tank_id,branch_id,fuel_product_id) REFERENCES tanks(id,branch_id,fuel_product_id),
 FOREIGN KEY(captured_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(evidence_reference IS NULL OR length(btrim(evidence_reference)) BETWEEN 1 AND 200)
);
CREATE TRIGGER operational_cut_tank_measurements_immutable BEFORE UPDATE OR DELETE ON operational_cut_tank_measurements
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE FUNCTION record_cut_tank_measurement(org uuid, branch uuid, target_cut uuid, target_tank uuid,
 actor uuid, expected_version integer, amount_l numeric, water_amount_l numeric, temp_c numeric,
 observed timestamptz, reading_source text, evidence text)
 RETURNS TABLE(cut_id uuid,tank_id uuid,version integer,measured_l numeric)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c operational_cuts%ROWTYPE; t tanks%ROWTYPE;
BEGIN
 SELECT * INTO c FROM operational_cuts oc WHERE oc.id=target_cut AND oc.organization_id=org AND oc.branch_id=branch FOR UPDATE;
 IF c.id IS NULL OR c.status<>'open' OR c.version<>expected_version THEN
  RAISE EXCEPTION 'Cut not open or version changed' USING ERRCODE='40001'; END IF;
 SELECT * INTO t FROM tanks tk WHERE tk.id=target_tank AND tk.branch_id=branch AND tk.organization_id=org;
 IF t.id IS NULL OR t.status='decommissioned' THEN RAISE EXCEPTION 'Tank not configured in branch' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Inactive actor' USING ERRCODE='23514'; END IF;
 IF amount_l IS NULL OR amount_l<0 OR amount_l>t.safe_fill_limit_l OR water_amount_l<0 OR water_amount_l>amount_l
   OR observed<c.starts_at OR observed>c.ends_at+interval '24 hours' THEN
  RAISE EXCEPTION 'Invalid measured tank level or timestamp' USING ERRCODE='23514'; END IF;
 INSERT INTO operational_cut_tank_measurements(cut_id,organization_id,branch_id,tank_id,fuel_product_id,measured_l,water_l,temperature_c,observed_at,source,evidence_reference,captured_by)
 VALUES(target_cut,org,branch,target_tank,t.fuel_product_id,amount_l,water_amount_l,temp_c,observed,reading_source,evidence,actor);
 UPDATE operational_cuts oc SET version=oc.version+1 WHERE oc.id=target_cut;
 RETURN QUERY SELECT target_cut,target_tank,expected_version+1,amount_l;
END; $$;
ALTER TABLE operational_cut_tank_measurements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE operational_cut_tank_measurements FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON TABLE operational_cut_tank_measurements TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON operational_cut_tank_measurements FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON operational_cut_tank_measurements FOR INSERT TO dlc_api_runtime WITH CHECK(true);
REVOKE ALL ON FUNCTION record_cut_tank_measurement(uuid,uuid,uuid,uuid,uuid,integer,numeric,numeric,numeric,timestamptz,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION record_cut_tank_measurement(uuid,uuid,uuid,uuid,uuid,integer,numeric,numeric,numeric,timestamptz,text,text) TO dlc_api_runtime;
