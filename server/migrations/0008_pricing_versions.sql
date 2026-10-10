CREATE TABLE fuel_market_references (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  fuel_product_id uuid NOT NULL,
  zone text NOT NULL CHECK (zone IN ('occidental','central','oriental','other')),
  announced_at timestamptz NOT NULL,
  effective_at timestamptz,
  direction text NOT NULL CHECK (direction IN ('increase','decrease','unchanged','unknown')),
  reference_price numeric(18,8),
  currency char(3) NOT NULL DEFAULT 'USD' CHECK (currency='USD'),
  unit text NOT NULL CHECK (unit IN ('liter','us_gallon')),
  source_name text NOT NULL CHECK (length(btrim(source_name)) BETWEEN 1 AND 120),
  source_reference text,
  note text,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (fuel_product_id,organization_id) REFERENCES fuel_products(id,organization_id),
  FOREIGN KEY (created_by,organization_id) REFERENCES users(id,organization_id),
  CHECK (reference_price IS NULL OR reference_price >= 0),
  UNIQUE (id,organization_id)
);
CREATE INDEX fuel_market_reference_recent_idx ON fuel_market_references(organization_id,zone,fuel_product_id,announced_at DESC);

CREATE TABLE fuel_price_proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  service_mode text NOT NULL CHECK (service_mode IN ('full_service','self_service')),
  proposed_price_usd_per_unit numeric(18,8) NOT NULL CHECK (proposed_price_usd_per_unit > 0),
  unit text NOT NULL CHECK (unit IN ('liter','us_gallon')),
  effective_at timestamptz NOT NULL,
  market_reference_id uuid,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 500),
  status text NOT NULL DEFAULT 'pending_approval' CHECK (status IN ('pending_approval','approved','scheduled','rejected','cancelled')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by uuid NOT NULL,
  approved_by uuid,
  rejected_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  approved_at timestamptz,
  rejected_at timestamptz,
  FOREIGN KEY (branch_id,organization_id) REFERENCES branches(id,organization_id),
  FOREIGN KEY (fuel_product_id,organization_id) REFERENCES fuel_products(id,organization_id),
  FOREIGN KEY (market_reference_id,organization_id) REFERENCES fuel_market_references(id,organization_id),
  FOREIGN KEY (created_by,organization_id) REFERENCES users(id,organization_id),
  FOREIGN KEY (approved_by,organization_id) REFERENCES users(id,organization_id),
  FOREIGN KEY (rejected_by,organization_id) REFERENCES users(id,organization_id),
  CHECK (approved_by IS NULL OR approved_by <> created_by),
  CHECK (rejected_by IS NULL OR rejected_by <> created_by),
  CHECK ((status='pending_approval' AND approved_by IS NULL AND rejected_by IS NULL)
      OR (status IN ('approved','scheduled') AND approved_by IS NOT NULL AND rejected_by IS NULL)
      OR (status='rejected' AND rejected_by IS NOT NULL AND approved_by IS NULL)
      OR status='cancelled'),
  UNIQUE (id,organization_id)
);
CREATE INDEX fuel_price_proposals_branch_idx ON fuel_price_proposals(organization_id,branch_id,status,created_at DESC);

CREATE TABLE fuel_price_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  service_mode text NOT NULL CHECK (service_mode IN ('full_service','self_service')),
  version integer NOT NULL CHECK (version > 0),
  price_usd_per_unit numeric(18,8) NOT NULL CHECK (price_usd_per_unit > 0),
  unit text NOT NULL CHECK (unit IN ('liter','us_gallon')),
  effective_at timestamptz NOT NULL,
  proposal_id uuid NOT NULL UNIQUE,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id,organization_id) REFERENCES branches(id,organization_id),
  FOREIGN KEY (fuel_product_id,organization_id) REFERENCES fuel_products(id,organization_id),
  FOREIGN KEY (proposal_id,organization_id) REFERENCES fuel_price_proposals(id,organization_id),
  FOREIGN KEY (created_by,organization_id) REFERENCES users(id,organization_id),
  UNIQUE (organization_id,branch_id,fuel_product_id,service_mode,version),
  UNIQUE (organization_id,branch_id,fuel_product_id,service_mode,effective_at)
);
CREATE INDEX fuel_price_lookup_idx ON fuel_price_versions(organization_id,branch_id,fuel_product_id,service_mode,effective_at DESC);

CREATE FUNCTION prevent_fuel_price_version_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'fuel_price_versions is append-only' USING ERRCODE = '55000';
END;
$$;
CREATE TRIGGER fuel_price_versions_immutable BEFORE UPDATE OR DELETE ON fuel_price_versions
FOR EACH ROW EXECUTE FUNCTION prevent_fuel_price_version_mutation();
