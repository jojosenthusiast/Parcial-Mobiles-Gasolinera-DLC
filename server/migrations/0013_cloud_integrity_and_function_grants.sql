-- Supabase default privileges may grant function execution to API roles
-- explicitly, independently of PUBLIC. Remove those grants as well.
DO $security$
DECLARE client_role text; function_name text;
BEGIN
  FOREACH client_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=client_role) THEN
      FOREACH function_name IN ARRAY ARRAY[
        'prevent_audit_mutation','prevent_inventory_movement_mutation',
        'prevent_fuel_price_version_mutation','prevent_nozzle_meter_reading_mutation',
        'prevent_dispense_event_mutation'
      ] LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION public.%I() FROM %I', function_name, client_role);
      END LOOP;
    END IF;
  END LOOP;
END;
$security$;

-- Tenant consistency must also hold when data is written outside a DTO.
ALTER TABLE employees ADD CONSTRAINT employee_branch_tenant_fk
  FOREIGN KEY (branch_id,organization_id) REFERENCES branches(id,organization_id);
ALTER TABLE nozzles ADD CONSTRAINT nozzle_branch_tenant_fk
  FOREIGN KEY (branch_id,organization_id) REFERENCES branches(id,organization_id);
CREATE INDEX employee_branch_tenant_idx ON employees(branch_id,organization_id);
CREATE INDEX nozzle_branch_tenant_idx ON nozzles(branch_id,organization_id);

ALTER TABLE inventory_movements ADD CONSTRAINT inventory_movement_quantity_equation
  CHECK (after_quantity_l = before_quantity_l + delta_l);

-- SQL CHECK accepts UNKNOWN, so selected request fields must be explicitly present.
ALTER TABLE dispense_authorizations ADD CONSTRAINT dispense_request_required_value
  CHECK ((request_type='volume' AND requested_volume IS NOT NULL)
      OR (request_type='amount' AND requested_amount_usd IS NOT NULL));
