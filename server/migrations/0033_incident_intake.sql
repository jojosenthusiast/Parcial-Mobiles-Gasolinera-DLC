-- Damage to a person, building or hose is independent of physical fuel loss.
CREATE TABLE incidents (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 code text NOT NULL,category text NOT NULL CHECK(category IN('personal_injury','third_party_damage','premises_damage','equipment_damage','fuel_spill','fuel_variance','safety','other')),
 severity text NOT NULL CHECK(severity IN('low','medium','high','critical')),
 asset_type text NOT NULL CHECK(asset_type IN('branch','dispenser','nozzle','tank','sale','other')),
 asset_id uuid,description text NOT NULL CHECK(length(btrim(description)) BETWEEN 12 AND 2000),
 occurred_at timestamptz NOT NULL,reported_by uuid NOT NULL,reported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 status text NOT NULL DEFAULT 'reported' CHECK(status IN('reported','assessed','in_progress','resolved','closed')),
 assignee_id uuid, due_at timestamptz, version integer NOT NULL DEFAULT 1 CHECK(version>0),
 resolved_at timestamptz,closed_at timestamptz,
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(reported_by,organization_id) REFERENCES users(id,organization_id),
 FOREIGN KEY(assignee_id,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(branch_id,code),UNIQUE(id,organization_id,branch_id),
 CHECK((asset_type='branch' AND asset_id IS NULL) OR (asset_type<>'branch' AND asset_id IS NOT NULL)),
 CHECK(due_at IS NULL OR due_at>occurred_at)
);
CREATE INDEX incidents_branch_queue_idx ON incidents(organization_id,branch_id,status,severity,reported_at DESC);
CREATE TABLE incident_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 incident_id uuid NOT NULL,from_status text,to_status text NOT NULL,
 note text NOT NULL CHECK(length(btrim(note)) BETWEEN 5 AND 1000),actor_id uuid NOT NULL,occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(incident_id,organization_id,branch_id) REFERENCES incidents(id,organization_id,branch_id),
 FOREIGN KEY(actor_id,organization_id) REFERENCES users(id,organization_id)
);
CREATE INDEX incident_events_history_idx ON incident_events(incident_id,occurred_at DESC);
CREATE TABLE incident_evidence (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 incident_id uuid NOT NULL,object_key text NOT NULL CHECK(length(btrim(object_key)) BETWEEN 8 AND 500),
 mime_type text NOT NULL CHECK(mime_type IN('image/jpeg','image/png','application/pdf')),
 sha256 char(64) NOT NULL CHECK(sha256~'^[0-9a-f]{64}$'),
 sensitive boolean NOT NULL DEFAULT false,uploaded_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(incident_id,organization_id,branch_id) REFERENCES incidents(id,organization_id,branch_id),
 FOREIGN KEY(uploaded_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,object_key)
);
CREATE FUNCTION validate_incident_asset() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.asset_type='dispenser' AND NOT EXISTS(SELECT 1 FROM dispensers d WHERE d.id=NEW.asset_id AND d.branch_id=NEW.branch_id AND d.organization_id=NEW.organization_id)
 OR NEW.asset_type='nozzle' AND NOT EXISTS(SELECT 1 FROM nozzles n WHERE n.id=NEW.asset_id AND n.branch_id=NEW.branch_id AND n.organization_id=NEW.organization_id)
 OR NEW.asset_type='tank' AND NOT EXISTS(SELECT 1 FROM tanks t WHERE t.id=NEW.asset_id AND t.branch_id=NEW.branch_id AND t.organization_id=NEW.organization_id)
 OR NEW.asset_type='sale' AND NOT EXISTS(SELECT 1 FROM sales s WHERE s.id=NEW.asset_id AND s.branch_id=NEW.branch_id AND s.organization_id=NEW.organization_id) THEN
  RAISE EXCEPTION 'Incident asset outside this branch' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER incident_asset_guard BEFORE INSERT OR UPDATE OF asset_type,asset_id,branch_id ON incidents
 FOR EACH ROW EXECUTE FUNCTION validate_incident_asset();
CREATE FUNCTION guard_incident_event() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 RAISE EXCEPTION 'Incident evidence and history are append-only' USING ERRCODE='55000';
END; $$;
CREATE TRIGGER incident_events_immutable BEFORE UPDATE OR DELETE ON incident_events FOR EACH ROW EXECUTE FUNCTION guard_incident_event();
CREATE TRIGGER incident_evidence_immutable BEFORE UPDATE OR DELETE ON incident_evidence FOR EACH ROW EXECUTE FUNCTION guard_incident_event();
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['incidents','incident_events','incident_evidence'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
 END LOOP;
END $$;
GRANT UPDATE ON incidents TO dlc_api_runtime;
CREATE POLICY dlc_api_update ON incidents FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
REVOKE ALL ON FUNCTION validate_incident_asset(),guard_incident_event() FROM PUBLIC,anon,authenticated,service_role;
