CREATE TABLE maintenance_asset_profiles (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 asset_type text NOT NULL CHECK(asset_type IN('tank','dispenser','nozzle')),asset_id uuid NOT NULL,
 manufacturer text,model text,serial_number text,location_label text,
 supplier_id uuid,commissioned_on date,warranty_until date,
 criticality text NOT NULL DEFAULT 'medium' CHECK(criticality IN('low','medium','high','critical')),
 created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(supplier_id,organization_id) REFERENCES suppliers(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(branch_id,asset_type,asset_id),UNIQUE(id,organization_id,branch_id),
 CHECK(warranty_until IS NULL OR commissioned_on IS NULL OR warranty_until>=commissioned_on)
);
CREATE FUNCTION validate_maintenance_asset() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF (NEW.asset_type='tank' AND NOT EXISTS(SELECT 1 FROM tanks t WHERE t.id=NEW.asset_id AND t.branch_id=NEW.branch_id AND t.organization_id=NEW.organization_id)) OR
    (NEW.asset_type='dispenser' AND NOT EXISTS(SELECT 1 FROM dispensers d WHERE d.id=NEW.asset_id AND d.branch_id=NEW.branch_id AND d.organization_id=NEW.organization_id)) OR
    (NEW.asset_type='nozzle' AND NOT EXISTS(SELECT 1 FROM nozzles n WHERE n.id=NEW.asset_id AND n.branch_id=NEW.branch_id AND n.organization_id=NEW.organization_id)) THEN
  RAISE EXCEPTION 'Maintenance asset belongs to another branch' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER maintenance_asset_scope BEFORE INSERT OR UPDATE OF asset_type,asset_id,branch_id ON maintenance_asset_profiles
 FOR EACH ROW EXECUTE FUNCTION validate_maintenance_asset();
CREATE TABLE maintenance_plans (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 asset_profile_id uuid NOT NULL,code text NOT NULL,description text NOT NULL CHECK(length(btrim(description)) BETWEEN 8 AND 500),
 cadence_days integer CHECK(cadence_days>0),cadence_usage numeric(20,3) CHECK(cadence_usage>0),
 usage_unit text, next_due_at timestamptz,next_due_usage numeric(20,3),
 active boolean NOT NULL DEFAULT true,created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(asset_profile_id,organization_id,branch_id) REFERENCES maintenance_asset_profiles(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(asset_profile_id,code),
 CHECK((cadence_days IS NOT NULL AND next_due_at IS NOT NULL) OR
       (cadence_usage IS NOT NULL AND usage_unit IS NOT NULL AND next_due_usage IS NOT NULL))
);
CREATE TABLE maintenance_work_orders (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 asset_profile_id uuid NOT NULL,plan_id uuid REFERENCES maintenance_plans(id),incident_id uuid REFERENCES incidents(id),
 kind text NOT NULL CHECK(kind IN('preventive','corrective','inspection')),
 status text NOT NULL DEFAULT 'planned' CHECK(status IN('planned','in_progress','completed','verified','cancelled')),
 due_key text NOT NULL,diagnosis text,description text NOT NULL CHECK(length(btrim(description)) BETWEEN 8 AND 1000),
 assigned_to uuid,due_at timestamptz,started_at timestamptz,completed_at timestamptz,verified_at timestamptz,
 completed_by uuid,verified_by uuid,estimate_usd numeric(18,2) CHECK(estimate_usd>=0),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(asset_profile_id,organization_id,branch_id) REFERENCES maintenance_asset_profiles(id,organization_id,branch_id),
 FOREIGN KEY(assigned_to,organization_id) REFERENCES users(id,organization_id),
 FOREIGN KEY(completed_by,organization_id) REFERENCES users(id,organization_id),
 FOREIGN KEY(verified_by,organization_id) REFERENCES users(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(branch_id,asset_profile_id,due_key),UNIQUE(id,organization_id,branch_id),
 CHECK(verified_by IS NULL OR verified_by<>completed_by)
);
CREATE INDEX maintenance_orders_queue_idx ON maintenance_work_orders(branch_id,status,due_at);
CREATE FUNCTION validate_work_order_scope() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.plan_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM maintenance_plans p WHERE p.id=NEW.plan_id
  AND p.asset_profile_id=NEW.asset_profile_id AND p.branch_id=NEW.branch_id AND p.organization_id=NEW.organization_id) THEN
  RAISE EXCEPTION 'Maintenance plan does not match asset' USING ERRCODE='23514'; END IF;
 IF NEW.incident_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM incidents i WHERE i.id=NEW.incident_id
  AND i.branch_id=NEW.branch_id AND i.organization_id=NEW.organization_id) THEN
  RAISE EXCEPTION 'Incident does not match branch' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER work_order_scope BEFORE INSERT OR UPDATE OF plan_id,incident_id ON maintenance_work_orders
 FOR EACH ROW EXECUTE FUNCTION validate_work_order_scope();
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['maintenance_asset_profiles','maintenance_plans','maintenance_work_orders'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_update ON %I FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true)',t);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION validate_maintenance_asset(),validate_work_order_scope() FROM PUBLIC,anon,authenticated,service_role;
