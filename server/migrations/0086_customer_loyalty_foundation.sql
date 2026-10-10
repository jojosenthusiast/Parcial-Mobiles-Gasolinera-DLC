BEGIN;

CREATE TABLE customer_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  auth_user_id uuid NOT NULL,
  email_normalized text NOT NULL,
  full_name text NOT NULL CHECK (length(btrim(full_name)) BETWEEN 2 AND 160),
  phone text CHECK (phone IS NULL OR phone ~ '^\+?[0-9 ()-]{7,24}$'),
  terms_version text NOT NULL CHECK (length(terms_version) BETWEEN 1 AND 40),
  terms_accepted_at timestamptz NOT NULL DEFAULT now(),
  communications_consent boolean NOT NULL DEFAULT false,
  public_code uuid NOT NULL DEFAULT gen_random_uuid(),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','blocked','closed')),
  blocked_at timestamptz,
  blocked_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, auth_user_id),
  UNIQUE (organization_id, email_normalized),
  UNIQUE (public_code),
  UNIQUE (id, organization_id),
  CHECK ((status='blocked') = (blocked_at IS NOT NULL))
);
CREATE INDEX customer_accounts_status_created_idx ON customer_accounts (organization_id, status, created_at DESC, id);

CREATE TABLE customer_loyalty_programs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  version integer NOT NULL CHECK (version > 0),
  status text NOT NULL CHECK (status IN ('draft','active','retired')),
  points_per_eligible_usd numeric(12,6) NOT NULL CHECK (points_per_eligible_usd >= 0),
  minimum_eligible_usd numeric(12,2) NOT NULL DEFAULT 0 CHECK (minimum_eligible_usd >= 0),
  points_expire_after_days integer CHECK (points_expire_after_days IS NULL OR points_expire_after_days BETWEEN 1 AND 3650),
  policy jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(policy)='object'),
  approved_by uuid,
  approved_at timestamptz,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, version),
  UNIQUE (id, organization_id),
  FOREIGN KEY (created_by, organization_id) REFERENCES users(id, organization_id),
  FOREIGN KEY (approved_by, organization_id) REFERENCES users(id, organization_id),
  CHECK ((status='active') = (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);
CREATE UNIQUE INDEX customer_loyalty_one_active_idx ON customer_loyalty_programs (organization_id) WHERE status='active';

CREATE TABLE customer_points_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  customer_id uuid NOT NULL,
  program_id uuid,
  event_type text NOT NULL CHECK (event_type IN ('earn','reserve','redeem','release','expire','reverse','adjust')),
  points_delta bigint NOT NULL CHECK (points_delta <> 0),
  source_type text NOT NULL CHECK (length(source_type) BETWEEN 1 AND 60),
  source_id uuid NOT NULL,
  command_id uuid NOT NULL,
  reason text,
  expires_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, command_id),
  UNIQUE (organization_id, source_type, source_id, event_type),
  FOREIGN KEY (customer_id, organization_id) REFERENCES customer_accounts(id, organization_id),
  FOREIGN KEY (program_id, organization_id) REFERENCES customer_loyalty_programs(id, organization_id),
  FOREIGN KEY (created_by, organization_id) REFERENCES users(id, organization_id),
  CHECK ((event_type IN ('earn','release') AND points_delta > 0)
      OR (event_type IN ('reserve','redeem','expire','reverse') AND points_delta < 0)
      OR event_type='adjust')
);
CREATE INDEX customer_points_history_idx ON customer_points_ledger (organization_id, customer_id, created_at DESC, id DESC);
CREATE INDEX customer_points_expiry_idx ON customer_points_ledger (organization_id, customer_id, expires_at) WHERE expires_at IS NOT NULL AND points_delta > 0;

CREATE TABLE customer_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL CHECK (code ~ '^[A-Z0-9_-]{1,40}$'),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  description text NOT NULL DEFAULT '',
  image_url text,
  points_cost bigint NOT NULL CHECK (points_cost > 0),
  stock_quantity integer CHECK (stock_quantity IS NULL OR stock_quantity >= 0),
  per_customer_limit integer CHECK (per_customer_limit IS NULL OR per_customer_limit > 0),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  status text NOT NULL CHECK (status IN ('draft','pending_approval','scheduled','published','paused','archived')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by uuid NOT NULL,
  approved_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, code),
  UNIQUE (id, organization_id),
  FOREIGN KEY (created_by, organization_id) REFERENCES users(id, organization_id),
  FOREIGN KEY (approved_by, organization_id) REFERENCES users(id, organization_id),
  CHECK (ends_at IS NULL OR ends_at > starts_at),
  CHECK (status <> 'published' OR approved_by IS NOT NULL)
);
CREATE INDEX customer_rewards_catalog_idx ON customer_rewards (organization_id, status, starts_at, ends_at, id);

CREATE TABLE customer_reward_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  customer_id uuid NOT NULL,
  reward_id uuid NOT NULL,
  points_cost bigint NOT NULL CHECK (points_cost > 0),
  status text NOT NULL CHECK (status IN ('reserved','redeemed','released','expired')),
  confirmation_nonce_hash bytea,
  nonce_expires_at timestamptz,
  command_id uuid NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  fulfilled_by uuid,
  fulfilled_at timestamptz,
  UNIQUE (organization_id, command_id),
  FOREIGN KEY (customer_id, organization_id) REFERENCES customer_accounts(id, organization_id),
  FOREIGN KEY (reward_id, organization_id) REFERENCES customer_rewards(id, organization_id),
  FOREIGN KEY (fulfilled_by, organization_id) REFERENCES users(id, organization_id),
  CHECK ((status='reserved') OR confirmed_at IS NOT NULL OR status IN ('released','expired')),
  CHECK (status <> 'reserved' OR (confirmation_nonce_hash IS NOT NULL AND nonce_expires_at IS NOT NULL)),
  CHECK ((status='redeemed') = (confirmed_at IS NOT NULL))
);
CREATE INDEX customer_redemptions_customer_idx ON customer_reward_redemptions (organization_id, customer_id, requested_at DESC, id DESC);
CREATE INDEX customer_redemptions_reserved_idx ON customer_reward_redemptions (organization_id, nonce_expires_at) WHERE status='reserved';

CREATE TABLE customer_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 2000),
  image_url text,
  image_alt text NOT NULL CHECK (length(btrim(image_alt)) BETWEEN 1 AND 240),
  branch_id uuid REFERENCES branches(id),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  priority integer NOT NULL DEFAULT 0,
  status text NOT NULL CHECK (status IN ('draft','pending_approval','scheduled','published','paused','archived')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by uuid NOT NULL,
  approved_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (created_by, organization_id) REFERENCES users(id, organization_id),
  FOREIGN KEY (approved_by, organization_id) REFERENCES users(id, organization_id),
  CHECK (status <> 'published' OR approved_by IS NOT NULL)
);
CREATE INDEX customer_campaign_feed_idx ON customer_campaigns (organization_id, status, starts_at, ends_at, priority DESC, id);

CREATE FUNCTION reject_customer_ledger_mutation() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'Customer points ledger is append-only' USING ERRCODE='55000';
END; $$;
CREATE TRIGGER customer_points_ledger_immutable
BEFORE UPDATE OR DELETE ON customer_points_ledger
FOR EACH ROW EXECUTE FUNCTION reject_customer_ledger_mutation();
REVOKE ALL ON FUNCTION reject_customer_ledger_mutation() FROM PUBLIC, anon, authenticated, service_role;

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'customer_accounts','customer_loyalty_programs','customer_points_ledger',
    'customer_rewards','customer_reward_redemptions','customer_campaigns'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role', table_name);
  END LOOP;
END $$;

GRANT SELECT, INSERT, UPDATE ON TABLE customer_accounts TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON customer_accounts FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON customer_accounts FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON customer_accounts FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT ON TABLE customer_loyalty_programs, customer_points_ledger, customer_rewards,
  customer_reward_redemptions, customer_campaigns TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON customer_loyalty_programs FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_select ON customer_points_ledger FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_select ON customer_rewards FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_select ON customer_reward_redemptions FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_select ON customer_campaigns FOR SELECT TO dlc_api_runtime USING (true);

COMMIT;
