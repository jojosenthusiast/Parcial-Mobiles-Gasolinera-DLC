CREATE TABLE branch_operating_profiles (
  branch_id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  profile text NOT NULL DEFAULT 'operational' CHECK (profile IN ('academicLab22','operational')),
  expected_dispenser_count integer NOT NULL DEFAULT 6 CHECK (expected_dispenser_count > 0),
  configuration_version integer NOT NULL DEFAULT 1 CHECK (configuration_version > 0),
  updated_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (updated_by, organization_id) REFERENCES users(id, organization_id),
  CHECK (profile <> 'academicLab22' OR expected_dispenser_count = 6)
);

CREATE TABLE fuel_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  sku text NOT NULL,
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 100),
  family text NOT NULL CHECK (family IN ('super','regular','diesel','other')),
  brand text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','archived')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, sku),
  UNIQUE (id, organization_id)
);

CREATE TABLE fuel_product_specifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  attribute_code text NOT NULL,
  value text NOT NULL,
  unit text,
  test_method text,
  source_name text NOT NULL,
  source_reference text,
  valid_from date NOT NULL,
  valid_until date,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (fuel_product_id, organization_id) REFERENCES fuel_products(id, organization_id),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  UNIQUE (fuel_product_id, attribute_code, valid_from)
);

CREATE TABLE branch_fuel_offers (
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  created_by uuid NOT NULL,
  PRIMARY KEY (branch_id, fuel_product_id),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (fuel_product_id, organization_id) REFERENCES fuel_products(id, organization_id),
  FOREIGN KEY (created_by, organization_id) REFERENCES users(id, organization_id),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);

CREATE TABLE tanks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  fuel_product_id uuid NOT NULL,
  nominal_capacity_l numeric(24,12) NOT NULL CHECK (nominal_capacity_l > 0),
  safe_fill_limit_l numeric(24,12) NOT NULL CHECK (safe_fill_limit_l > 0),
  unusable_reserve_l numeric(24,12) NOT NULL DEFAULT 0 CHECK (unusable_reserve_l >= 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','maintenance','offline','decommissioned')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (branch_id, fuel_product_id) REFERENCES branch_fuel_offers(branch_id, fuel_product_id),
  UNIQUE (id, branch_id, fuel_product_id),
  UNIQUE (branch_id, code),
  CHECK (safe_fill_limit_l <= nominal_capacity_l),
  CHECK (unusable_reserve_l < safe_fill_limit_l)
);
CREATE INDEX tanks_branch_status_idx ON tanks(organization_id, branch_id, status);

CREATE TABLE dispensers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  code text NOT NULL,
  name text,
  physical_status text NOT NULL DEFAULT 'active' CHECK (physical_status IN ('active','maintenance','offline','decommissioned')),
  commissioned_at date,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  UNIQUE (id, branch_id),
  UNIQUE (branch_id, code)
);
CREATE INDEX dispensers_branch_status_idx ON dispensers(organization_id, branch_id, physical_status, code);

CREATE TABLE nozzles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  dispenser_id uuid NOT NULL,
  code text NOT NULL,
  product_code text NOT NULL,
  fuel_product_id uuid NOT NULL,
  service_mode text NOT NULL CHECK (service_mode IN ('full_service','self_service')),
  physical_status text NOT NULL DEFAULT 'active' CHECK (physical_status IN ('active','maintenance','offline','removed')),
  meter_unit text NOT NULL DEFAULT 'gallon_us' CHECK (meter_unit IN ('gallon_us','liter')),
  meter_precision integer NOT NULL DEFAULT 3 CHECK (meter_precision BETWEEN 0 AND 9),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  installed_at date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (dispenser_id, branch_id) REFERENCES dispensers(id, branch_id),
  FOREIGN KEY (branch_id, fuel_product_id) REFERENCES branch_fuel_offers(branch_id, fuel_product_id),
  UNIQUE (id, branch_id, fuel_product_id),
  UNIQUE (dispenser_id, code)
);
CREATE INDEX nozzles_branch_product_idx ON nozzles(organization_id, branch_id, fuel_product_id, physical_status);

CREATE TABLE nozzle_tank_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  nozzle_id uuid NOT NULL,
  tank_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  created_by uuid NOT NULL,
  reason text NOT NULL,
  FOREIGN KEY (nozzle_id, branch_id, fuel_product_id) REFERENCES nozzles(id, branch_id, fuel_product_id),
  FOREIGN KEY (tank_id, branch_id, fuel_product_id) REFERENCES tanks(id, branch_id, fuel_product_id),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (created_by, organization_id) REFERENCES users(id, organization_id),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);
CREATE UNIQUE INDEX nozzle_current_tank_idx ON nozzle_tank_connections(nozzle_id) WHERE valid_until IS NULL;
CREATE INDEX tank_nozzle_history_idx ON nozzle_tank_connections(tank_id, valid_from DESC);

CREATE TABLE asset_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  asset_type text NOT NULL CHECK (asset_type IN ('tank','dispenser','nozzle')),
  asset_id uuid NOT NULL,
  block_type text NOT NULL CHECK (block_type IN ('technical','operational','safety','inventory')),
  reason_code text NOT NULL,
  reason text NOT NULL,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_by uuid,
  resolved_at timestamptz,
  resolution text,
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (created_by, organization_id) REFERENCES users(id, organization_id),
  FOREIGN KEY (resolved_by, organization_id) REFERENCES users(id, organization_id),
  CHECK ((resolved_at IS NULL AND resolved_by IS NULL) OR (resolved_at IS NOT NULL AND resolved_by IS NOT NULL))
);
CREATE INDEX active_asset_blocks_idx ON asset_blocks(organization_id, branch_id, asset_type, asset_id) WHERE resolved_at IS NULL;
