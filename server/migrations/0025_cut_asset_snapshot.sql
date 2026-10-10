-- The expected set belongs to the cut, never to a fixed application constant.
CREATE TABLE operational_cut_dispensers (
 cut_id uuid NOT NULL, organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 dispenser_id uuid NOT NULL, code text NOT NULL, physical_status text NOT NULL,
 configuration_version integer NOT NULL, opened_at timestamptz NOT NULL,
 PRIMARY KEY(cut_id,dispenser_id),
 FOREIGN KEY(cut_id,organization_id,branch_id) REFERENCES operational_cuts(id,organization_id,branch_id),
 FOREIGN KEY(dispenser_id,branch_id) REFERENCES dispensers(id,branch_id)
);
CREATE TABLE operational_cut_nozzles (
 cut_id uuid NOT NULL, organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 nozzle_id uuid NOT NULL, dispenser_id uuid NOT NULL, code text NOT NULL,
 fuel_product_id uuid NOT NULL, meter_unit text NOT NULL,
 configuration_version integer NOT NULL, participation text NOT NULL CHECK(participation IN('expected','excused')),
 exclusion_reason text, opened_at timestamptz NOT NULL,
 PRIMARY KEY(cut_id,nozzle_id),
 FOREIGN KEY(cut_id,dispenser_id) REFERENCES operational_cut_dispensers(cut_id,dispenser_id),
 FOREIGN KEY(nozzle_id,branch_id,fuel_product_id) REFERENCES nozzles(id,branch_id,fuel_product_id),
 CHECK((participation='expected' AND exclusion_reason IS NULL) OR
       (participation='excused' AND length(btrim(exclusion_reason))>0))
);
CREATE INDEX operational_cut_nozzles_participation_idx ON operational_cut_nozzles(cut_id,participation);
CREATE FUNCTION guard_cut_snapshot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Cut asset snapshots are immutable' USING ERRCODE='55000'; END IF;
 IF NOT EXISTS(SELECT 1 FROM operational_cuts WHERE id=NEW.cut_id AND status='scheduled') THEN
  RAISE EXCEPTION 'Snapshot can only be captured while opening a scheduled cut' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER cut_dispenser_snapshot_guard BEFORE INSERT OR UPDATE OR DELETE ON operational_cut_dispensers
 FOR EACH ROW EXECUTE FUNCTION guard_cut_snapshot();
CREATE TRIGGER cut_nozzle_snapshot_guard BEFORE INSERT OR UPDATE OR DELETE ON operational_cut_nozzles
 FOR EACH ROW EXECUTE FUNCTION guard_cut_snapshot();

CREATE FUNCTION open_operational_cut(org uuid, branch uuid, target_cut uuid, actor uuid, expected_version integer)
 RETURNS TABLE(cut_id uuid, version integer, expected_dispenser_count integer,
   expected_nozzle_count integer, excused_nozzle_count integer)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE cut_row operational_cuts%ROWTYPE; opened timestamptz:=clock_timestamp(); configured integer; actual integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'The cut opener must be an active user' USING ERRCODE='23514';
 END IF;
 SELECT c.* INTO cut_row FROM operational_cuts c
  WHERE c.id=target_cut AND c.organization_id=org AND c.branch_id=branch FOR UPDATE;
 IF cut_row.id IS NULL THEN RAISE EXCEPTION 'Cut does not belong to this branch' USING ERRCODE='23514'; END IF;
 IF cut_row.status<>'scheduled' OR cut_row.version<>expected_version THEN
  RAISE EXCEPTION 'Cut already opened or version changed' USING ERRCODE='40001';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM branches b WHERE b.id=branch AND b.organization_id=org AND b.status='active') THEN
  RAISE EXCEPTION 'Cut branch is inactive' USING ERRCODE='23514';
 END IF;
 SELECT p.expected_dispenser_count INTO configured FROM branch_operating_profiles p
  WHERE p.branch_id=branch AND p.organization_id=org;
 SELECT count(*) INTO actual FROM dispensers d WHERE d.branch_id=branch AND d.organization_id=org
  AND d.physical_status<>'decommissioned';
 IF actual=0 THEN RAISE EXCEPTION 'A cut needs configured dispensers' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM branch_operating_profiles p WHERE p.branch_id=branch AND p.profile='academicLab22')
   AND actual<>configured THEN
  RAISE EXCEPTION 'Academic profile requires exactly its configured dispenser count' USING ERRCODE='23514';
 END IF;
 INSERT INTO operational_cut_dispensers(cut_id,organization_id,branch_id,dispenser_id,code,physical_status,configuration_version,opened_at)
 SELECT target_cut,org,branch,d.id,d.code,d.physical_status,d.version,opened
 FROM dispensers d WHERE d.branch_id=branch AND d.organization_id=org AND d.physical_status<>'decommissioned';
 INSERT INTO operational_cut_nozzles(cut_id,organization_id,branch_id,nozzle_id,dispenser_id,code,fuel_product_id,meter_unit,configuration_version,participation,exclusion_reason,opened_at)
 SELECT target_cut,org,branch,n.id,n.dispenser_id,n.code,n.fuel_product_id,n.meter_unit,n.version,
  CASE WHEN n.physical_status='active' AND d.physical_status='active' AND o.status='active'
    AND conn.id IS NOT NULL AND block.reason IS NULL THEN 'expected' ELSE 'excused' END,
  CASE WHEN n.physical_status<>'active' THEN 'manguera: '||n.physical_status
   WHEN d.physical_status<>'active' THEN 'dispensador: '||d.physical_status
   WHEN o.status<>'active' THEN 'combustible no ofertado'
   WHEN conn.id IS NULL THEN 'sin conexión activa a tanque'
   WHEN block.reason IS NOT NULL THEN 'bloqueo: '||block.reason
   ELSE NULL END,opened
 FROM nozzles n JOIN operational_cut_dispensers snap ON snap.cut_id=target_cut AND snap.dispenser_id=n.dispenser_id
 JOIN dispensers d ON d.id=n.dispenser_id
 JOIN branch_fuel_offers o ON o.branch_id=n.branch_id AND o.fuel_product_id=n.fuel_product_id
 LEFT JOIN LATERAL (SELECT x.id FROM nozzle_tank_connections x JOIN tanks t ON t.id=x.tank_id AND t.status='active'
  WHERE x.nozzle_id=n.id AND x.valid_from<=opened AND (x.valid_until IS NULL OR x.valid_until>opened) LIMIT 1) conn ON true
 LEFT JOIN LATERAL (SELECT a.reason FROM asset_blocks a WHERE a.branch_id=branch AND a.resolved_at IS NULL AND
  ((a.asset_type='nozzle' AND a.asset_id=n.id) OR (a.asset_type='dispenser' AND a.asset_id=d.id))
  ORDER BY a.created_at LIMIT 1) block ON true
 WHERE n.branch_id=branch AND n.organization_id=org AND n.physical_status<>'removed';
 IF NOT EXISTS(SELECT 1 FROM operational_cut_nozzles WHERE operational_cut_nozzles.cut_id=target_cut) THEN
  RAISE EXCEPTION 'A cut needs configured nozzles' USING ERRCODE='23514';
 END IF;
 UPDATE operational_cuts c SET status='open',version=c.version+1 WHERE c.id=target_cut;
 RETURN QUERY SELECT target_cut,expected_version+1,actual,
  count(*) FILTER(WHERE n.participation='expected')::integer,
  count(*) FILTER(WHERE n.participation='excused')::integer
 FROM operational_cut_nozzles n WHERE n.cut_id=target_cut;
END; $$;

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['operational_cut_dispensers','operational_cut_nozzles'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
 END LOOP;
END $$;
GRANT UPDATE ON operational_cuts TO dlc_api_runtime;
CREATE POLICY dlc_api_update ON operational_cuts FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
REVOKE ALL ON FUNCTION guard_cut_snapshot(),open_operational_cut(uuid,uuid,uuid,uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION open_operational_cut(uuid,uuid,uuid,uuid,integer) TO dlc_api_runtime;
