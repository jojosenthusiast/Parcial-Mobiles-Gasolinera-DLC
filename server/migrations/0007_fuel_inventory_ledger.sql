CREATE TABLE tank_inventory_balances (
  tank_id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  on_hand_l numeric(24,12) NOT NULL CHECK (on_hand_l >= 0),
  inventory_value_usd numeric(24,8),
  average_cost_per_l_usd numeric(24,12),
  valuation_quality text NOT NULL CHECK (valuation_quality IN ('known','unknown','provisional')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  last_movement_id uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (tank_id, branch_id, fuel_product_id) REFERENCES tanks(id, branch_id, fuel_product_id),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  CHECK ((valuation_quality = 'known' AND inventory_value_usd IS NOT NULL AND average_cost_per_l_usd IS NOT NULL)
      OR (valuation_quality <> 'known' AND inventory_value_usd IS NULL AND average_cost_per_l_usd IS NULL)),
  CHECK (inventory_value_usd IS NULL OR inventory_value_usd >= 0),
  CHECK (average_cost_per_l_usd IS NULL OR average_cost_per_l_usd >= 0)
);

CREATE TABLE inventory_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  tank_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  movement_type text NOT NULL CHECK (movement_type IN ('opening','receipt','sale','loss','adjustment_in','adjustment_out')),
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  source_type text NOT NULL,
  source_id text,
  source_line text,
  quantity_entered numeric(24,12) NOT NULL CHECK (quantity_entered >= 0),
  unit_entered text NOT NULL CHECK (unit_entered IN ('liter','us_gallon')),
  conversion_factor_to_l numeric(24,12) NOT NULL CHECK (conversion_factor_to_l > 0),
  observed_l numeric(24,12) NOT NULL CHECK (observed_l >= 0),
  compensated_l numeric(24,12) CHECK (compensated_l IS NULL OR compensated_l > 0),
  delta_l numeric(24,12) NOT NULL CHECK (delta_l <> 0 OR movement_type = 'opening'),
  volume_basis text NOT NULL CHECK (volume_basis IN ('observed','compensated','nominal')),
  temperature_c numeric(8,4),
  reference_temperature_c numeric(8,4),
  water_l numeric(24,12) CHECK (water_l IS NULL OR water_l >= 0),
  unit_cost_usd_per_l numeric(24,12),
  total_cost_usd numeric(24,8),
  valuation_quality text NOT NULL CHECK (valuation_quality IN ('known','unknown','provisional')),
  reason_code text,
  reason text,
  document_reference text,
  before_quantity_l numeric(24,12) NOT NULL CHECK (before_quantity_l >= 0),
  after_quantity_l numeric(24,12) NOT NULL CHECK (after_quantity_l >= 0),
  cost_recognized_usd numeric(24,8),
  actor_user_id uuid NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  correlation_id uuid NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (organization_id, command_id),
  FOREIGN KEY (tank_id, branch_id, fuel_product_id) REFERENCES tanks(id, branch_id, fuel_product_id),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (actor_user_id, organization_id) REFERENCES users(id, organization_id),
  CHECK (jsonb_typeof(metadata) = 'object'),
  CHECK (unit_cost_usd_per_l IS NULL OR unit_cost_usd_per_l >= 0),
  CHECK (total_cost_usd IS NULL OR total_cost_usd >= 0),
  CHECK (cost_recognized_usd IS NULL OR cost_recognized_usd >= 0),
  CHECK ((movement_type = 'opening' AND delta_l >= 0)
      OR (movement_type IN ('receipt','adjustment_in') AND delta_l > 0)
      OR (movement_type IN ('sale','loss','adjustment_out') AND delta_l < 0)),
  CHECK (movement_type = 'opening' OR quantity_entered > 0),
  CHECK ((volume_basis = 'compensated' AND compensated_l IS NOT NULL AND abs(delta_l) = compensated_l)
      OR (volume_basis <> 'compensated' AND compensated_l IS NULL AND abs(delta_l) = observed_l)),
  CHECK ((movement_type NOT IN ('loss','adjustment_in','adjustment_out') OR length(btrim(COALESCE(reason,''))) > 0)),
  CHECK (movement_type <> 'receipt' OR length(btrim(COALESCE(document_reference,''))) > 0),
  CHECK (movement_type <> 'opening' OR source_type = 'opening_balance')
);

CREATE INDEX inventory_movements_tank_history_idx
  ON inventory_movements (organization_id, branch_id, tank_id, occurred_at DESC, id DESC);
CREATE INDEX inventory_movements_source_idx
  ON inventory_movements (organization_id, source_type, source_id, source_line)
  WHERE source_id IS NOT NULL;

ALTER TABLE tank_inventory_balances
  ADD CONSTRAINT tank_inventory_balances_last_movement_fk
  FOREIGN KEY (last_movement_id) REFERENCES inventory_movements(id);

CREATE FUNCTION prevent_inventory_movement_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'inventory_movements is append-only' USING ERRCODE = '55000';
END;
$$;
CREATE TRIGGER inventory_movements_immutable BEFORE UPDATE OR DELETE ON inventory_movements
FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
