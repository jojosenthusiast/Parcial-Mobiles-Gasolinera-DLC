BEGIN;

INSERT INTO permissions(code, description) VALUES
  ('promotion.read','Consultar promociones y sus condiciones'),
  ('promotion.manage','Crear promociones locales y propuestas'),
  ('promotion.approve','Aprobar, rechazar o suspender promociones locales'),
  ('promotion.network.manage','Crear promociones para toda la red'),
  ('promotion.network.approve','Aprobar promociones de toda la red')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE customer_cashback_partners (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL CHECK (code ~ '^[A-Z0-9_-]{2,40}$'),
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 2 AND 120),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id,code),
  UNIQUE (organization_id,command_id),
  UNIQUE (id,organization_id),
  FOREIGN KEY (created_by,organization_id) REFERENCES users(id,organization_id)
);

CREATE TABLE customer_cashback_partner_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  partner_code text NOT NULL,
  command_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type='status_changed'),
  status text NOT NULL CHECK (status IN ('active','inactive')),
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id,partner_code) REFERENCES customer_cashback_partners(organization_id,code),
  FOREIGN KEY (actor_id,organization_id) REFERENCES users(id,organization_id),
  UNIQUE (organization_id,command_id)
);

CREATE TABLE customer_promotion_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  object_path text NOT NULL UNIQUE,
  image_url text NOT NULL,
  mime_type text NOT NULL CHECK (mime_type IN ('image/jpeg','image/png','image/webp')),
  byte_size integer NOT NULL CHECK (byte_size BETWEEN 32 AND 1048576),
  scope text NOT NULL CHECK (scope IN ('network','branch')),
  branch_id uuid,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id,organization_id) REFERENCES branches(id,organization_id),
  FOREIGN KEY (created_by,organization_id) REFERENCES users(id,organization_id),
  UNIQUE (organization_id,command_id),
  CHECK ((scope='network' AND branch_id IS NULL) OR (scope='branch' AND branch_id IS NOT NULL))
);
CREATE FUNCTION reject_customer_promotion_image_mutation() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'Promotion image records are immutable' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER customer_promotion_image_immutable BEFORE UPDATE OR DELETE ON customer_promotion_images
  FOR EACH ROW EXECUTE FUNCTION reject_customer_promotion_image_mutation();
CREATE FUNCTION reject_cashback_partner_event_mutation() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'Cashback partner events are append-only' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER customer_cashback_partner_event_immutable BEFORE UPDATE OR DELETE ON customer_cashback_partner_events
  FOR EACH ROW EXECUTE FUNCTION reject_cashback_partner_event_mutation();

CREATE TABLE customer_promotions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  branch_id uuid,
  scope text NOT NULL CHECK (scope IN ('network','branch')),
  current_version integer NOT NULL DEFAULT 1 CHECK (current_version > 0),
  active_version integer,
  scheduled_version integer,
  create_command_id uuid NOT NULL,
  create_request_hash char(64) NOT NULL CHECK (create_request_hash ~ '^[0-9a-f]{64}$'),
  status text NOT NULL CHECK (status IN ('draft','pending_approval','approved','scheduled','active','paused','ended','rejected','cancelled')),
  created_by uuid NOT NULL,
  approved_by uuid,
  approved_at timestamptz,
  paused_by uuid,
  paused_at timestamptz,
  pause_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, organization_id),
  UNIQUE (organization_id, create_command_id),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (created_by, organization_id) REFERENCES users(id, organization_id),
  FOREIGN KEY (approved_by, organization_id) REFERENCES users(id, organization_id),
  FOREIGN KEY (paused_by, organization_id) REFERENCES users(id, organization_id),
  CHECK ((scope='network' AND branch_id IS NULL) OR (scope='branch' AND branch_id IS NOT NULL)),
  CHECK ((status IN ('approved','scheduled','active','paused','ended') AND approved_by IS NOT NULL AND approved_at IS NOT NULL)
      OR (status IN ('draft','pending_approval','rejected','cancelled') AND approved_by IS NULL AND approved_at IS NULL)),
  CHECK ((status='paused') = (paused_at IS NOT NULL AND paused_by IS NOT NULL AND pause_reason IS NOT NULL))
);
CREATE INDEX customer_promotions_scope_status_idx ON customer_promotions(organization_id, branch_id, status, updated_at DESC, id);

CREATE TABLE customer_promotion_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  promotion_id uuid NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  status text NOT NULL CHECK (status IN ('draft','pending_approval','approved','rejected','superseded')),
  definition jsonb NOT NULL CHECK (jsonb_typeof(definition)='object'),
  created_by uuid NOT NULL,
  submitted_by uuid,
  submitted_at timestamptz,
  approved_by uuid,
  approved_at timestamptz,
  decision_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (promotion_id, version),
  UNIQUE (promotion_id, organization_id, version),
  UNIQUE (id, organization_id, promotion_id),
  FOREIGN KEY (promotion_id, organization_id) REFERENCES customer_promotions(id, organization_id),
  FOREIGN KEY (created_by, organization_id) REFERENCES users(id, organization_id),
  FOREIGN KEY (submitted_by, organization_id) REFERENCES users(id, organization_id),
  FOREIGN KEY (approved_by, organization_id) REFERENCES users(id, organization_id),
  CHECK ((status IN ('pending_approval','approved','rejected','superseded') AND submitted_by IS NOT NULL AND submitted_at IS NOT NULL)
      OR (status='draft' AND submitted_by IS NULL AND submitted_at IS NULL)),
  CHECK ((status IN ('approved','rejected','superseded') AND approved_by IS NOT NULL AND approved_at IS NOT NULL)
      OR (status IN ('draft','pending_approval') AND approved_by IS NULL AND approved_at IS NULL)),
  CHECK (approved_by IS NULL OR (approved_by <> created_by AND approved_by <> submitted_by))
);
CREATE INDEX customer_promotion_versions_review_idx ON customer_promotion_versions(organization_id,status,created_at,id);
ALTER TABLE customer_promotions ADD CONSTRAINT customer_promotions_current_version_fk
  FOREIGN KEY (id, organization_id, current_version)
  REFERENCES customer_promotion_versions(promotion_id, organization_id, version)
  DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE customer_promotions ADD CONSTRAINT customer_promotions_active_version_fk
  FOREIGN KEY (id, organization_id, active_version)
  REFERENCES customer_promotion_versions(promotion_id, organization_id, version)
  DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE customer_promotions ADD CONSTRAINT customer_promotions_scheduled_version_fk
  FOREIGN KEY (id, organization_id, scheduled_version)
  REFERENCES customer_promotion_versions(promotion_id, organization_id, version)
  DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE customer_promotion_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  promotion_id uuid NOT NULL,
  version integer NOT NULL,
  command_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('created','version_created','submitted','approved','rejected','paused','resumed')),
  actor_id uuid NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(payload)='object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (promotion_id, organization_id, version) REFERENCES customer_promotion_versions(promotion_id, organization_id, version),
  FOREIGN KEY (actor_id, organization_id) REFERENCES users(id, organization_id),
  UNIQUE (organization_id, command_id)
);
CREATE INDEX customer_promotion_events_history_idx ON customer_promotion_events(organization_id,promotion_id,created_at,id);

CREATE FUNCTION protect_customer_promotion_version() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF OLD.definition IS DISTINCT FROM NEW.definition OR OLD.version IS DISTINCT FROM NEW.version
     OR OLD.promotion_id IS DISTINCT FROM NEW.promotion_id OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
     OR OLD.created_by IS DISTINCT FROM NEW.created_by THEN
    RAISE EXCEPTION 'Promotion versions are immutable; create a new version' USING ERRCODE='55000';
  END IF;
  IF NOT (
    (OLD.status='draft' AND NEW.status IN ('draft','pending_approval')) OR
    (OLD.status='pending_approval' AND NEW.status IN ('approved','rejected')) OR
    (OLD.status IN ('approved','rejected') AND NEW.status='superseded')
  ) THEN RAISE EXCEPTION 'Invalid promotion version transition' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER customer_promotion_version_guard BEFORE UPDATE ON customer_promotion_versions
  FOR EACH ROW EXECUTE FUNCTION protect_customer_promotion_version();
CREATE FUNCTION reject_customer_promotion_version_delete() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'Promotion versions cannot be deleted' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER customer_promotion_version_no_delete BEFORE DELETE ON customer_promotion_versions
  FOR EACH ROW EXECUTE FUNCTION reject_customer_promotion_version_delete();

CREATE TABLE customer_notification_inbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('promotion_published','promotion_started','promotion_ending','points_earned','reward_ready','account_notice')),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 500),
  image_url text,
  target_type text,
  target_id uuid,
  dedupe_key text NOT NULL CHECK (length(btrim(dedupe_key)) BETWEEN 1 AND 160),
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  FOREIGN KEY (customer_id, organization_id) REFERENCES customer_accounts(id, organization_id),
  UNIQUE (organization_id, customer_id, dedupe_key)
);
CREATE INDEX customer_notification_inbox_unread_idx ON customer_notification_inbox(organization_id,customer_id,created_at DESC,id) WHERE read_at IS NULL;

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['customer_cashback_partners','customer_cashback_partner_events','customer_promotion_images','customer_promotions','customer_promotion_versions','customer_promotion_events','customer_notification_inbox'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role', table_name);
    EXECUTE format('CREATE POLICY dlc_api_select ON public.%I FOR SELECT TO dlc_api_runtime USING (true)', table_name);
  END LOOP;
END $$;
CREATE POLICY dlc_api_insert ON customer_promotions FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON customer_promotions FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);
CREATE POLICY dlc_api_insert ON customer_promotion_versions FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON customer_promotion_versions FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);
CREATE POLICY dlc_api_insert ON customer_promotion_events FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_insert ON customer_notification_inbox FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON customer_notification_inbox FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);
CREATE POLICY dlc_api_insert ON customer_cashback_partners FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON customer_cashback_partners FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);
CREATE POLICY dlc_api_insert ON customer_cashback_partner_events FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_insert ON customer_promotion_images FOR INSERT TO dlc_api_runtime WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE ON customer_cashback_partners, customer_promotions, customer_promotion_versions, customer_notification_inbox TO dlc_api_runtime;
GRANT SELECT, INSERT ON customer_promotion_events TO dlc_api_runtime;
GRANT SELECT, INSERT ON customer_cashback_partner_events TO dlc_api_runtime;
GRANT SELECT, INSERT ON customer_promotion_images TO dlc_api_runtime;
REVOKE ALL ON FUNCTION protect_customer_promotion_version() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION reject_customer_promotion_version_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION reject_cashback_partner_event_mutation() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION reject_customer_promotion_image_mutation() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
