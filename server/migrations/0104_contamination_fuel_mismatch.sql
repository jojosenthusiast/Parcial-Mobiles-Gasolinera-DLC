BEGIN;

-- Only incompatible fuel products enter the tank-contamination loss workflow.
CREATE OR REPLACE FUNCTION validate_contamination_scope() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM purchase_order_lines l JOIN purchase_orders o ON o.id=l.purchase_order_id
   WHERE l.id=NEW.purchase_order_line_id AND o.id=NEW.purchase_order_id AND o.organization_id=NEW.organization_id AND o.branch_id=NEW.branch_id
    AND l.fuel_product_id=NEW.incoming_product_id AND l.unit=NEW.unit)
 OR NOT EXISTS(SELECT 1 FROM tanks t WHERE t.id=NEW.tank_id AND t.organization_id=NEW.organization_id AND t.branch_id=NEW.branch_id AND t.fuel_product_id=NEW.original_product_id)
 OR NOT EXISTS(SELECT 1 FROM incidents i WHERE i.id=NEW.incident_id AND i.organization_id=NEW.organization_id AND i.branch_id=NEW.branch_id AND i.asset_id=NEW.tank_id AND i.category='wrong_tank_delivery')
 OR NOT EXISTS(SELECT 1 FROM users u WHERE u.id=NEW.reported_by AND u.organization_id=NEW.organization_id AND u.status='active') THEN
  RAISE EXCEPTION 'Contaminated delivery scope mismatch' USING ERRCODE='23514'; END IF;
 IF NEW.incoming_product_id=NEW.original_product_id THEN
  RAISE EXCEPTION 'Contamination requires incompatible fuel products' USING ERRCODE='23514'; END IF;
 IF NEW.incoming_quantity_l IS DISTINCT FROM round(NEW.actual_quantity*CASE WHEN NEW.unit='us_gallon' THEN 3.785411784 ELSE 1 END,9) THEN
  RAISE EXCEPTION 'Contaminated delivery unit mismatch' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION validate_contamination_scope() FROM PUBLIC;
REVOKE ALL ON FUNCTION validate_contamination_scope() FROM anon, authenticated, service_role, dlc_api_runtime;

COMMIT;
