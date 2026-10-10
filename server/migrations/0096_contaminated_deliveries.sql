BEGIN;
CREATE TABLE contaminated_deliveries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 purchase_order_id uuid NOT NULL REFERENCES purchase_orders(id), purchase_order_line_id uuid NOT NULL REFERENCES purchase_order_lines(id),
 incident_id uuid NOT NULL REFERENCES incidents(id), tank_id uuid NOT NULL REFERENCES tanks(id),
 original_product_id uuid NOT NULL REFERENCES fuel_products(id), incoming_product_id uuid NOT NULL REFERENCES fuel_products(id),
 prior_quantity_l numeric(24,9) NOT NULL CHECK(prior_quantity_l>=0), actual_quantity numeric(24,9) NOT NULL CHECK(actual_quantity>0),
 unit text NOT NULL CHECK(unit IN('liter','us_gallon')), incoming_quantity_l numeric(24,9) NOT NULL CHECK(incoming_quantity_l>0),
 prior_cost_usd numeric(24,8), incoming_cost_usd numeric(24,8) NOT NULL CHECK(incoming_cost_usd>=0),
 remaining_order_quantity numeric(24,9) NOT NULL CHECK(remaining_order_quantity>=0), balance_version integer NOT NULL,
 document_reference text NOT NULL CHECK(length(btrim(document_reference)) BETWEEN 3 AND 120),
 description text NOT NULL CHECK(length(btrim(description)) BETWEEN 12 AND 2000),
 command_id uuid NOT NULL, request_hash char(64) NOT NULL, reported_by uuid NOT NULL REFERENCES users(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(organization_id,command_id)
);
CREATE INDEX contamination_line_idx ON contaminated_deliveries(purchase_order_line_id);
CREATE INDEX contamination_tank_idx ON contaminated_deliveries(tank_id);
CREATE TRIGGER contamination_immutable BEFORE UPDATE OR DELETE ON contaminated_deliveries FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
ALTER TABLE contaminated_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON contaminated_deliveries FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON contaminated_deliveries TO dlc_api_runtime;
CREATE POLICY api_select ON contaminated_deliveries FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY api_insert ON contaminated_deliveries FOR INSERT TO dlc_api_runtime WITH CHECK(true);
COMMIT;
