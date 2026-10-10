-- Fuel tickets reuse a completed dispatch's inventory movement; never post stock twice.
CREATE TABLE sales (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 authorization_id uuid NOT NULL,
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 status text NOT NULL DEFAULT 'pending_collection' CHECK(status='pending_collection'),
 currency text NOT NULL DEFAULT 'USD' CHECK(currency='USD'),
 total_usd numeric(18,2) NOT NULL CHECK(total_usd>=0),
 tax_status text NOT NULL DEFAULT 'unconfigured' CHECK(tax_status='unconfigured'),
 net_usd numeric(18,2), tax_usd numeric(18,2),
 receipt_type text NOT NULL DEFAULT 'internal' CHECK(receipt_type='internal'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 occurred_at timestamptz NOT NULL, correlation_id uuid NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK(version=1),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(authorization_id,organization_id,branch_id) REFERENCES dispense_authorizations(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id), UNIQUE(authorization_id), UNIQUE(id,organization_id,branch_id),
 CHECK(net_usd IS NULL AND tax_usd IS NULL)
);
CREATE INDEX sales_branch_history_idx ON sales(organization_id,branch_id,occurred_at DESC,id DESC);

CREATE TABLE sale_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL, branch_id uuid NOT NULL, sale_id uuid NOT NULL,
 line_number integer NOT NULL CHECK(line_number=1),
 kind text NOT NULL DEFAULT 'fuel' CHECK(kind='fuel'),
 fuel_product_id uuid NOT NULL, description text NOT NULL CHECK(length(btrim(description))>0),
 quantity_l numeric(24,9) NOT NULL CHECK(quantity_l>0),
 price_usd_per_unit numeric(18,8) NOT NULL CHECK(price_usd_per_unit>0),
 price_unit text NOT NULL CHECK(price_unit IN('liter','us_gallon')),
 price_version_id uuid NOT NULL,
 total_usd numeric(18,2) NOT NULL CHECK(total_usd>=0),
 inventory_movement_id uuid NOT NULL UNIQUE,
 cost_usd numeric(24,8), unit_cost_usd_per_l numeric(24,12),
 cost_quality text NOT NULL CHECK(cost_quality IN('known','unknown','provisional')),
 FOREIGN KEY(sale_id,organization_id,branch_id) REFERENCES sales(id,organization_id,branch_id),
 FOREIGN KEY(fuel_product_id,organization_id) REFERENCES fuel_products(id,organization_id),
 FOREIGN KEY(price_version_id) REFERENCES fuel_price_versions(id),
 FOREIGN KEY(inventory_movement_id,organization_id,branch_id) REFERENCES inventory_movements(id,organization_id,branch_id),
 UNIQUE(sale_id,line_number),
 CHECK((cost_quality='known' AND cost_usd IS NOT NULL)
    OR (cost_quality<>'known' AND cost_usd IS NULL AND unit_cost_usd_per_l IS NULL)),
 CHECK(cost_usd IS NULL OR cost_usd>=0), CHECK(unit_cost_usd_per_l IS NULL OR unit_cost_usd_per_l>=0)
);
-- Defense in depth: tenant-safe FK alone does not prove this ticket matches its dispatch.
CREATE FUNCTION validate_fuel_sale_snapshot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a dispense_authorizations%ROWTYPE; m inventory_movements%ROWTYPE; s sales%ROWTYPE;
BEGIN
 IF TG_TABLE_NAME='sales' THEN
  SELECT * INTO a FROM dispense_authorizations WHERE id=NEW.authorization_id;
  IF a.status IS DISTINCT FROM 'completed' OR NEW.total_usd IS DISTINCT FROM a.sale_amount_usd
    OR NEW.occurred_at IS DISTINCT FROM a.completed_at THEN
   RAISE EXCEPTION 'Sale requires a completed dispatch and its original amount/time' USING ERRCODE='23514';
  END IF;
 ELSE
  SELECT * INTO s FROM sales WHERE id=NEW.sale_id;
  SELECT * INTO a FROM dispense_authorizations WHERE id=s.authorization_id;
  SELECT * INTO m FROM inventory_movements WHERE id=NEW.inventory_movement_id;
  IF a.status IS DISTINCT FROM 'completed' OR NEW.inventory_movement_id IS DISTINCT FROM a.inventory_movement_id
    OR NEW.fuel_product_id IS DISTINCT FROM a.fuel_product_id OR NEW.quantity_l IS DISTINCT FROM a.actual_l
    OR NEW.price_version_id IS DISTINCT FROM a.price_version_id OR NEW.price_unit IS DISTINCT FROM a.price_unit
    OR NEW.price_usd_per_unit IS DISTINCT FROM a.price_usd_per_unit OR NEW.total_usd IS DISTINCT FROM a.sale_amount_usd
    OR NEW.total_usd IS DISTINCT FROM round((CASE WHEN a.price_unit='us_gallon' THEN a.actual_l/3.785411784 ELSE a.actual_l END)*a.price_usd_per_unit,2)
    OR m.movement_type IS DISTINCT FROM 'sale' OR -m.delta_l IS DISTINCT FROM a.actual_l
    OR NEW.cost_quality IS DISTINCT FROM m.valuation_quality OR NEW.cost_usd IS DISTINCT FROM m.cost_recognized_usd
    OR NEW.unit_cost_usd_per_l IS DISTINCT FROM m.unit_cost_usd_per_l THEN
   RAISE EXCEPTION 'Sale line differs from the original dispatch/inventory snapshot' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER sales_snapshot BEFORE INSERT ON sales FOR EACH ROW EXECUTE FUNCTION validate_fuel_sale_snapshot();
CREATE TRIGGER sale_lines_snapshot BEFORE INSERT ON sale_lines FOR EACH ROW EXECUTE FUNCTION validate_fuel_sale_snapshot();
CREATE TRIGGER sales_immutable BEFORE UPDATE OR DELETE ON sales FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE TRIGGER sale_lines_immutable BEFORE UPDATE OR DELETE ON sale_lines FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION validate_fuel_sale_snapshot() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON TABLE sales,sale_lines FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_lines ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT ON sales,sale_lines TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON sales FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON sales FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_select ON sale_lines FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON sale_lines FOR INSERT TO dlc_api_runtime WITH CHECK(true);

CREATE FUNCTION validate_fuel_sale_line_count() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF (SELECT count(*) FROM sale_lines WHERE sale_id=NEW.id)<>1 THEN
  RAISE EXCEPTION 'Fuel sale requires exactly one original dispatch line' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER sales_line_required AFTER INSERT ON sales DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION validate_fuel_sale_line_count();
REVOKE ALL ON FUNCTION validate_fuel_sale_line_count() FROM PUBLIC,anon,authenticated,service_role;
