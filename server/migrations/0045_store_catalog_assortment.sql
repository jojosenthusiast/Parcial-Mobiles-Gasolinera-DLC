CREATE TABLE store_catalog_products (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL REFERENCES organizations(id),
 sku text NOT NULL CHECK(sku~'^[A-Z0-9][A-Z0-9._-]{0,39}$'),barcode text,
 kind text NOT NULL CHECK(kind IN('store','lubricant','part')),
 category text NOT NULL CHECK(length(btrim(category)) BETWEEN 2 AND 80),
 presentation text NOT NULL CHECK(length(btrim(presentation)) BETWEEN 2 AND 120),
 unit text NOT NULL CHECK(unit IN('unit','bottle','liter','case','pack','kg')),
 tax_code text,default_supplier_id uuid,active boolean NOT NULL DEFAULT true,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(default_supplier_id,organization_id) REFERENCES suppliers(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,sku),UNIQUE(id,organization_id),
 CHECK(barcode IS NULL OR barcode~'^[0-9]{8,14}$')
);
CREATE UNIQUE INDEX store_catalog_barcode_idx ON store_catalog_products(organization_id,barcode) WHERE barcode IS NOT NULL;
CREATE TABLE branch_assortments (
 organization_id uuid NOT NULL,branch_id uuid NOT NULL,catalog_product_id uuid NOT NULL,
 pos_product_id uuid NOT NULL,min_stock_units integer NOT NULL DEFAULT 0 CHECK(min_stock_units>=0),
 active boolean NOT NULL DEFAULT true,created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(branch_id,catalog_product_id),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(catalog_product_id,organization_id) REFERENCES store_catalog_products(id,organization_id),
 FOREIGN KEY(pos_product_id,organization_id,branch_id) REFERENCES pos_products(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(pos_product_id)
);
CREATE FUNCTION validate_assortment() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE catalog store_catalog_products%ROWTYPE; pos pos_products%ROWTYPE;
BEGIN
 SELECT x.* INTO catalog FROM store_catalog_products x WHERE x.id=NEW.catalog_product_id;
 SELECT x.* INTO pos FROM pos_products x WHERE x.id=NEW.pos_product_id;
 IF catalog.id IS NULL OR pos.id IS NULL OR catalog.organization_id<>NEW.organization_id OR
  pos.branch_id<>NEW.branch_id OR catalog.sku<>pos.sku OR pos.kind<>'store' THEN
  RAISE EXCEPTION 'Assortment product and branch POS identity differ' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER assortment_validate BEFORE INSERT OR UPDATE ON branch_assortments FOR EACH ROW EXECUTE FUNCTION validate_assortment();
ALTER TABLE pos_stock_lots ADD COLUMN condition text NOT NULL DEFAULT 'sellable'
 CHECK(condition IN('sellable','quarantine','damaged','expired'));
CREATE INDEX pos_lots_sellable_fefo_idx ON pos_stock_lots(product_id,expires_on,received_at,id) WHERE condition='sellable';
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['store_catalog_products','branch_assortments'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_update ON %I FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true)',t);
 END LOOP;
END $$;
GRANT UPDATE ON pos_stock_lots TO dlc_api_runtime;
CREATE POLICY dlc_api_update ON pos_stock_lots FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
REVOKE ALL ON FUNCTION validate_assortment() FROM PUBLIC,anon,authenticated,service_role;
