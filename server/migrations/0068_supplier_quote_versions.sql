-- Supplier quotations are separate from public fuel-price references.
CREATE TABLE supplier_fuel_quotes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,supplier_id uuid NOT NULL,
 fuel_product_id uuid NOT NULL,version integer NOT NULL CHECK(version>0),
 unit text NOT NULL CHECK(unit IN('liter','us_gallon')),
 unit_price_usd numeric(18,8) NOT NULL CHECK(unit_price_usd>0),
 transport_usd numeric(18,2) NOT NULL DEFAULT 0 CHECK(transport_usd>=0),
 financing_usd numeric(18,2) NOT NULL DEFAULT 0 CHECK(financing_usd>=0),
 minimum_delivery_l numeric(24,3) NOT NULL DEFAULT 0 CHECK(minimum_delivery_l>=0),
 lead_days integer NOT NULL CHECK(lead_days BETWEEN 0 AND 120),
 valid_from timestamptz NOT NULL,valid_until timestamptz NOT NULL,
 confidence text NOT NULL CHECK(confidence IN('confirmed','indicative')),
 document_reference text NOT NULL CHECK(length(btrim(document_reference)) BETWEEN 5 AND 200),
 recorded_by uuid NOT NULL,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(supplier_id,organization_id) REFERENCES suppliers(id,organization_id),
 FOREIGN KEY(fuel_product_id,organization_id) REFERENCES fuel_products(id,organization_id),
 FOREIGN KEY(recorded_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(supplier_id,fuel_product_id,version),UNIQUE(id,organization_id),
 CHECK(valid_until>valid_from)
);
CREATE FUNCTION guard_supplier_quote() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE last_version integer;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('supplier-quote:'||NEW.supplier_id||':'||NEW.fuel_product_id,0));
 SELECT coalesce(max(version),0) INTO last_version FROM supplier_fuel_quotes
  WHERE supplier_id=NEW.supplier_id AND fuel_product_id=NEW.fuel_product_id;
 IF NEW.version<>last_version+1 OR NOT EXISTS(SELECT 1 FROM suppliers WHERE id=NEW.supplier_id
  AND organization_id=NEW.organization_id AND status='active')
  OR NOT EXISTS(SELECT 1 FROM supplier_fuel_offers WHERE supplier_id=NEW.supplier_id
   AND fuel_product_id=NEW.fuel_product_id AND organization_id=NEW.organization_id AND is_active)
 THEN RAISE EXCEPTION 'Quote version or supplier unavailable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER supplier_quote_guard BEFORE INSERT ON supplier_fuel_quotes FOR EACH ROW EXECUTE FUNCTION guard_supplier_quote();
ALTER TABLE supplier_fuel_quotes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON supplier_fuel_quotes FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON supplier_fuel_quotes TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON supplier_fuel_quotes FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON supplier_fuel_quotes FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE TRIGGER quote_immutable BEFORE UPDATE OR DELETE ON supplier_fuel_quotes
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION guard_supplier_quote() FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO permissions(code,description) VALUES('purchase.quote.manage','Registrar cotización de proveedor') ON CONFLICT(code) DO NOTHING;
