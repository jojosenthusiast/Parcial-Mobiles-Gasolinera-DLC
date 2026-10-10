CREATE UNIQUE INDEX fuel_price_version_tenant_identity_idx ON fuel_price_versions(id,organization_id,branch_id,fuel_product_id,service_mode);
CREATE TABLE dispense_authorizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  nozzle_id uuid NOT NULL,
  tank_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  price_version_id uuid NOT NULL,
  service_mode text NOT NULL CHECK (service_mode IN ('full_service','self_service')),
  requested_by uuid NOT NULL,
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  request_type text NOT NULL CHECK (request_type IN ('volume','amount')),
  requested_amount_usd numeric(18,2),
  requested_volume numeric(24,9),
  requested_volume_unit text CHECK (requested_volume_unit IS NULL OR requested_volume_unit IN ('gallon_us','liter')),
  reserved_l numeric(24,9) NOT NULL CHECK (reserved_l > 0),
  price_usd_per_unit numeric(18,8) NOT NULL CHECK (price_usd_per_unit > 0),
  price_unit text NOT NULL CHECK (price_unit IN ('us_gallon','liter')),
  status text NOT NULL DEFAULT 'authorized' CHECK (status IN ('authorized','dispensing','unknown','posting','completed','cancelled','expired')),
  progress_l numeric(24,9) NOT NULL DEFAULT 0 CHECK (progress_l >= 0),
  actual_l numeric(24,9) CHECK (actual_l IS NULL OR actual_l > 0),
  sale_amount_usd numeric(18,2),
  inventory_movement_id uuid UNIQUE,
  completion_command_id uuid,
  completion_hash char(64),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  expires_at timestamptz NOT NULL,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id,organization_id) REFERENCES branches(id,organization_id),
  FOREIGN KEY (nozzle_id,branch_id,fuel_product_id) REFERENCES nozzles(id,branch_id,fuel_product_id),
  FOREIGN KEY (tank_id,branch_id,fuel_product_id) REFERENCES tanks(id,branch_id,fuel_product_id),
  FOREIGN KEY (price_version_id,organization_id,branch_id,fuel_product_id,service_mode)
    REFERENCES fuel_price_versions(id,organization_id,branch_id,fuel_product_id,service_mode),
  FOREIGN KEY (requested_by,organization_id) REFERENCES users(id,organization_id),
  FOREIGN KEY (inventory_movement_id,organization_id,branch_id) REFERENCES inventory_movements(id,organization_id,branch_id),
  CHECK ((request_type='volume' AND requested_volume>0 AND requested_volume_unit IS NOT NULL AND requested_amount_usd IS NULL)
      OR (request_type='amount' AND requested_amount_usd>0 AND requested_volume IS NULL AND requested_volume_unit IS NULL)),
  CHECK (progress_l<=reserved_l),
  CHECK ((status='completed' AND actual_l IS NOT NULL AND sale_amount_usd IS NOT NULL AND inventory_movement_id IS NOT NULL AND completed_at IS NOT NULL)
      OR status<>'completed'),
  UNIQUE (organization_id,command_id),
  UNIQUE (id,organization_id,branch_id)
);
CREATE UNIQUE INDEX dispense_one_active_per_nozzle ON dispense_authorizations(nozzle_id)
  WHERE status IN ('authorized','dispensing','unknown','posting');
CREATE INDEX dispense_tank_reservations_idx ON dispense_authorizations(organization_id,branch_id,tank_id,status)
  WHERE status IN ('authorized','dispensing','unknown','posting');
CREATE INDEX dispense_history_idx ON dispense_authorizations(organization_id,branch_id,nozzle_id,created_at DESC,id DESC);

CREATE TABLE dispense_authorization_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  authorization_id uuid NOT NULL,
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  event_type text NOT NULL CHECK (event_type IN ('authorized','started','progress','unknown','completion_requested','completed','cancelled','expired')),
  previous_status text,
  next_status text NOT NULL,
  measured_l numeric(24,9),
  actor_user_id uuid NOT NULL,
  reason text,
  correlation_id uuid NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (authorization_id,organization_id,branch_id) REFERENCES dispense_authorizations(id,organization_id,branch_id),
  FOREIGN KEY (actor_user_id,organization_id) REFERENCES users(id,organization_id),
  UNIQUE (organization_id,command_id)
);
CREATE INDEX dispense_event_history_idx ON dispense_authorization_events(authorization_id,occurred_at DESC);

CREATE FUNCTION prevent_dispense_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'dispense_authorization_events is append-only' USING ERRCODE = '55000';
END;
$$;
CREATE TRIGGER dispense_authorization_events_immutable BEFORE UPDATE OR DELETE ON dispense_authorization_events
FOR EACH ROW EXECUTE FUNCTION prevent_dispense_event_mutation();
