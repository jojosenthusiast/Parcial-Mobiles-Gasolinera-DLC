BEGIN;

INSERT INTO permissions(code,description) VALUES
 ('operational_asset.read','Consultar activos operativos de sucursal'),
 ('operational_asset.manage','Registrar y asignar activos operativos'),
 ('operational_asset.verify','Verificar condición y liberar activos operativos'),
 ('operational_asset.transfer','Transferir activos operativos entre sucursales'),
 ('operational_asset.retire','Retirar activos operativos'),
 ('operational_asset.cost.read','Consultar costo de adquisición de activos operativos')
ON CONFLICT(code) DO NOTHING;

CREATE TABLE operational_assets (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 branch_id uuid NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),
 asset_type text NOT NULL CHECK(asset_type IN('payment_terminal','tire_gauge','air_hose','tool','safety_equipment','other')),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 120),
 description text NOT NULL DEFAULT '' CHECK(length(description)<=1000),
 manufacturer text CHECK(manufacturer IS NULL OR length(btrim(manufacturer)) BETWEEN 1 AND 100),
 model text CHECK(model IS NULL OR length(btrim(model)) BETWEEN 1 AND 100),
 serial_number text CHECK(serial_number IS NULL OR length(btrim(serial_number)) BETWEEN 1 AND 120),
 acquired_on date,
 acquisition_cost_usd numeric(18,2) CHECK(acquisition_cost_usd IS NULL OR acquisition_cost_usd>=0),
 location_label text CHECK(location_label IS NULL OR length(btrim(location_label)) BETWEEN 1 AND 160),
 custodian_employee_id uuid,
 status text NOT NULL DEFAULT 'available' CHECK(status IN('available','assigned','under_repair','missing','retired')),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(custodian_employee_id,organization_id) REFERENCES employees(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,branch_id,code),
 UNIQUE(id,organization_id),
 CHECK((status='assigned')=(custodian_employee_id IS NOT NULL)),
 CHECK(acquired_on IS NULL OR acquired_on<=CURRENT_DATE)
);
CREATE UNIQUE INDEX operational_assets_serial_idx ON operational_assets(organization_id,serial_number) WHERE serial_number IS NOT NULL;
CREATE INDEX operational_assets_branch_status_idx ON operational_assets(organization_id,branch_id,status,updated_at DESC,id);
CREATE INDEX operational_assets_branch_type_idx ON operational_assets(organization_id,branch_id,asset_type,updated_at DESC,id);

CREATE TABLE operational_asset_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 asset_id uuid NOT NULL,
 from_branch_id uuid,
 to_branch_id uuid NOT NULL,
 event_type text NOT NULL CHECK(event_type IN('created','profile_changed','assignment_changed','status_changed','transferred','incident_reported')),
 from_status text CHECK(from_status IS NULL OR from_status IN('available','assigned','under_repair','missing','retired')),
 to_status text NOT NULL CHECK(to_status IN('available','assigned','under_repair','missing','retired')),
 from_custodian_employee_id uuid,
 to_custodian_employee_id uuid,
 related_incident_id uuid,
 note text NOT NULL CHECK(length(btrim(note)) BETWEEN 4 AND 500),
 asset_version integer NOT NULL CHECK(asset_version>0),
 expected_version integer CHECK(expected_version IS NULL OR expected_version>0),
 command_id uuid NOT NULL,
 request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 actor_id uuid NOT NULL,
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(asset_id,organization_id) REFERENCES operational_assets(id,organization_id),
 FOREIGN KEY(from_branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(to_branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(from_custodian_employee_id,organization_id) REFERENCES employees(id,organization_id),
 FOREIGN KEY(to_custodian_employee_id,organization_id) REFERENCES employees(id,organization_id),
 FOREIGN KEY(related_incident_id,organization_id,to_branch_id) REFERENCES incidents(id,organization_id,branch_id),
 FOREIGN KEY(actor_id,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id),
 UNIQUE(asset_id,asset_version)
);
CREATE INDEX operational_asset_events_history_idx ON operational_asset_events(organization_id,asset_id,occurred_at DESC,id DESC);
CREATE INDEX operational_asset_events_branch_idx ON operational_asset_events(organization_id,to_branch_id,occurred_at DESC,id DESC);

CREATE FUNCTION validate_operational_asset_scope() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.custodian_employee_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM employees e WHERE e.id=NEW.custodian_employee_id AND e.organization_id=NEW.organization_id
    AND e.status='active' AND (e.branch_id IS NULL OR e.branch_id=NEW.branch_id)) THEN
  RAISE EXCEPTION 'Operational asset custodian is inactive or outside branch' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER operational_asset_scope BEFORE INSERT OR UPDATE OF branch_id,custodian_employee_id,status
 ON operational_assets FOR EACH ROW EXECUTE FUNCTION validate_operational_asset_scope();

CREATE FUNCTION guard_operational_asset_event_scope() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM operational_assets a WHERE a.id=NEW.asset_id AND a.organization_id=NEW.organization_id
   AND a.branch_id=NEW.to_branch_id AND a.version=NEW.asset_version AND a.status=NEW.to_status
   AND a.custodian_employee_id IS NOT DISTINCT FROM NEW.to_custodian_employee_id)
 OR NEW.event_type='transferred' AND (NEW.from_branch_id IS NULL OR NEW.from_branch_id=NEW.to_branch_id)
 OR NEW.event_type='created' AND (NEW.from_branch_id IS NOT NULL OR NEW.from_status IS NOT NULL)
 OR NEW.event_type NOT IN('created','transferred') AND NEW.from_branch_id IS DISTINCT FROM NEW.to_branch_id THEN
  RAISE EXCEPTION 'Operational asset event does not match current snapshot' USING ERRCODE='23514';
 END IF;
 IF NEW.related_incident_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM incidents i WHERE i.id=NEW.related_incident_id
   AND i.organization_id=NEW.organization_id AND i.branch_id=NEW.to_branch_id AND i.asset_type='operational_asset' AND i.asset_id=NEW.asset_id) THEN
  RAISE EXCEPTION 'Operational asset incident link mismatch' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER operational_asset_event_scope BEFORE INSERT ON operational_asset_events
 FOR EACH ROW EXECUTE FUNCTION guard_operational_asset_event_scope();
CREATE FUNCTION prevent_operational_asset_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Operational asset history is append-only' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER operational_asset_events_immutable BEFORE UPDATE OR DELETE ON operational_asset_events
 FOR EACH ROW EXECUTE FUNCTION prevent_operational_asset_event_mutation();

-- Extend incidents so a damage/loss report can point at a real, branch-scoped item.
ALTER TABLE incidents DROP CONSTRAINT incidents_asset_type_check;
ALTER TABLE incidents ADD CONSTRAINT incidents_asset_type_check
 CHECK(asset_type IN('branch','dispenser','nozzle','tank','sale','operational_asset','other'));
ALTER TABLE incidents DROP CONSTRAINT incidents_category_check;
ALTER TABLE incidents ADD CONSTRAINT incidents_category_check
 CHECK(category IN('personal_injury','third_party_damage','premises_damage','equipment_damage','asset_missing','fuel_spill','wrong_tank_delivery','fuel_variance','safety','other'));
CREATE OR REPLACE FUNCTION validate_incident_asset() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.asset_type='dispenser' AND NOT EXISTS(SELECT 1 FROM dispensers d WHERE d.id=NEW.asset_id AND d.branch_id=NEW.branch_id AND d.organization_id=NEW.organization_id)
 OR NEW.asset_type='nozzle' AND NOT EXISTS(SELECT 1 FROM nozzles n WHERE n.id=NEW.asset_id AND n.branch_id=NEW.branch_id AND n.organization_id=NEW.organization_id)
 OR NEW.asset_type='tank' AND NOT EXISTS(SELECT 1 FROM tanks t WHERE t.id=NEW.asset_id AND t.branch_id=NEW.branch_id AND t.organization_id=NEW.organization_id)
 OR NEW.asset_type='sale' AND NOT EXISTS(SELECT 1 FROM sales s WHERE s.id=NEW.asset_id AND s.branch_id=NEW.branch_id AND s.organization_id=NEW.organization_id)
 OR NEW.asset_type='operational_asset' AND NOT EXISTS(SELECT 1 FROM operational_assets a WHERE a.id=NEW.asset_id AND a.branch_id=NEW.branch_id AND a.organization_id=NEW.organization_id) THEN
  RAISE EXCEPTION 'Incident asset outside this branch' USING ERRCODE='23514'; END IF;
 IF NEW.category='asset_missing' AND NEW.asset_type<>'operational_asset' THEN
  RAISE EXCEPTION 'Missing asset incidents require an operational asset' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
DROP TRIGGER incident_asset_guard ON incidents;
CREATE TRIGGER incident_asset_guard BEFORE INSERT OR UPDATE OF asset_type,asset_id,branch_id,category ON incidents
 FOR EACH ROW EXECUTE FUNCTION validate_incident_asset();

-- The normal incident workflow changes the asset condition atomically and records the incident link.
CREATE OR REPLACE FUNCTION sync_operational_asset_incident() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old_status text; old_custodian uuid; new_status text; current_version integer; next_version integer;
BEGIN
 IF NEW.asset_type<>'operational_asset' OR NEW.category NOT IN('asset_missing','equipment_damage') THEN RETURN NEW; END IF;
 new_status:=CASE WHEN NEW.category='asset_missing' THEN 'missing' ELSE 'under_repair' END;
 SELECT status,custodian_employee_id,version INTO old_status,old_custodian,current_version FROM operational_assets
  WHERE id=NEW.asset_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id FOR UPDATE;
 IF current_version IS NULL THEN RAISE EXCEPTION 'Operational asset is outside this branch' USING ERRCODE='23514'; END IF;
 IF old_status='retired' THEN RAISE EXCEPTION 'Retired assets cannot receive a new incident' USING ERRCODE='23514'; END IF;
 IF old_status=new_status THEN RETURN NEW; END IF;
 UPDATE operational_assets SET status=new_status,custodian_employee_id=NULL,version=version+1,updated_at=clock_timestamp()
  WHERE id=NEW.asset_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id RETURNING version INTO next_version;
 INSERT INTO operational_asset_events(organization_id,asset_id,from_branch_id,to_branch_id,event_type,from_status,to_status,
  from_custodian_employee_id,to_custodian_employee_id,related_incident_id,note,asset_version,expected_version,command_id,request_hash,actor_id)
 VALUES(NEW.organization_id,NEW.asset_id,NEW.branch_id,NEW.branch_id,'incident_reported',old_status,new_status,
  old_custodian,NULL,NEW.id,'Estado actualizado por incidencia '||NEW.code,next_version,current_version,NEW.command_id,NEW.request_hash,NEW.reported_by)
 ON CONFLICT(organization_id,command_id) DO NOTHING;
 RETURN NEW;
END; $$;
CREATE TRIGGER sync_operational_asset_incident AFTER INSERT ON incidents
 FOR EACH ROW EXECUTE FUNCTION sync_operational_asset_incident();

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['operational_assets','operational_asset_events'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_update ON %I FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true)',t);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION validate_operational_asset_scope(),guard_operational_asset_event_scope(),
 prevent_operational_asset_event_mutation(),sync_operational_asset_incident() FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT,UPDATE ON operational_assets TO dlc_api_runtime;
GRANT SELECT,INSERT ON operational_asset_events TO dlc_api_runtime;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO dlc_api_runtime;

COMMIT;
