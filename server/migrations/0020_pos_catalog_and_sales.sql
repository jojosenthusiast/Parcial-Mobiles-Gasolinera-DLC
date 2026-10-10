-- Branch POS catalog. Published offers and sale facts are append-only.
CREATE TABLE pos_products (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 sku text NOT NULL CHECK(sku ~ '^[A-Z0-9][A-Z0-9._-]{0,39}$'),
 kind text NOT NULL CHECK(kind IN('store','service')), expiry_required boolean NOT NULL DEFAULT false,
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(kind='store' OR NOT expiry_required), UNIQUE(organization_id,branch_id,sku), UNIQUE(id,organization_id,branch_id)
);
CREATE TABLE pos_offer_versions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, product_id uuid NOT NULL,
 version integer NOT NULL CHECK(version>0), description text NOT NULL CHECK(length(btrim(description)) BETWEEN 1 AND 120),
 active boolean NOT NULL, price_usd numeric(18,4) NOT NULL CHECK(price_usd>0 AND price_usd::text NOT IN('NaN','Infinity','-Infinity')),
 service_unit_cost_usd numeric(18,8) CHECK(service_unit_cost_usd>=0 AND service_unit_cost_usd::text NOT IN('NaN','Infinity','-Infinity')),
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(product_id,organization_id,branch_id) REFERENCES pos_products(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(product_id,version), UNIQUE(organization_id,command_id), UNIQUE(id,organization_id,branch_id)
);
CREATE INDEX pos_offer_latest_idx ON pos_offer_versions(product_id,version DESC);
CREATE TABLE pos_stock_lots (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, product_id uuid NOT NULL,
 lot_code text NOT NULL CHECK(length(btrim(lot_code)) BETWEEN 1 AND 80), expires_on date,
 quantity_received numeric(18,3) NOT NULL CHECK(quantity_received>0 AND quantity_received=trunc(quantity_received) AND quantity_received::text NOT IN('NaN','Infinity','-Infinity')),
 unit_cost_usd numeric(18,8) CHECK(unit_cost_usd>=0 AND unit_cost_usd::text NOT IN('NaN','Infinity','-Infinity')),
 source_reference text NOT NULL CHECK(length(btrim(source_reference)) BETWEEN 1 AND 300),
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 received_by uuid NOT NULL, received_at timestamptz NOT NULL DEFAULT clock_timestamp(), correlation_id uuid NOT NULL,
 FOREIGN KEY(product_id,organization_id,branch_id) REFERENCES pos_products(id,organization_id,branch_id),
 FOREIGN KEY(received_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id), UNIQUE(product_id,source_reference,lot_code), UNIQUE(id,organization_id,branch_id)
);
CREATE INDEX pos_lot_fefo_idx ON pos_stock_lots(product_id,expires_on,received_at,id);
ALTER TABLE sales ALTER COLUMN authorization_id DROP NOT NULL;
ALTER TABLE sale_lines ALTER COLUMN fuel_product_id DROP NOT NULL, ALTER COLUMN quantity_l DROP NOT NULL,
 ALTER COLUMN price_version_id DROP NOT NULL, ALTER COLUMN inventory_movement_id DROP NOT NULL;
ALTER TABLE sale_lines DROP CONSTRAINT sale_lines_kind_check, DROP CONSTRAINT sale_lines_line_number_check, DROP CONSTRAINT sale_lines_price_unit_check;
ALTER TABLE sale_lines ADD CONSTRAINT sale_lines_kind_check CHECK(kind IN('fuel','store','service')),
 ADD CONSTRAINT sale_lines_line_number_check CHECK(line_number BETWEEN 1 AND 50),
 ADD CONSTRAINT sale_lines_price_unit_check CHECK(price_unit IN('liter','us_gallon','unit')),
 ADD COLUMN pos_product_id uuid, ADD COLUMN offer_version_id uuid, ADD COLUMN quantity_units numeric(18,3),
 ADD COLUMN unit_cost_usd numeric(18,8),
 ADD CONSTRAINT sale_lines_pos_product_fk FOREIGN KEY(pos_product_id,organization_id,branch_id) REFERENCES pos_products(id,organization_id,branch_id),
 ADD CONSTRAINT sale_lines_pos_offer_fk FOREIGN KEY(offer_version_id,organization_id,branch_id) REFERENCES pos_offer_versions(id,organization_id,branch_id),
 ADD CONSTRAINT sale_lines_shape CHECK(
  (kind='fuel' AND fuel_product_id IS NOT NULL AND quantity_l IS NOT NULL AND price_version_id IS NOT NULL AND inventory_movement_id IS NOT NULL
   AND pos_product_id IS NULL AND offer_version_id IS NULL AND quantity_units IS NULL AND unit_cost_usd IS NULL)
  OR (kind IN('store','service') AND fuel_product_id IS NULL AND quantity_l IS NULL AND price_version_id IS NULL AND inventory_movement_id IS NULL
   AND pos_product_id IS NOT NULL AND offer_version_id IS NOT NULL AND quantity_units IS NOT NULL AND quantity_units>0 AND quantity_units::text NOT IN('NaN','Infinity','-Infinity')
   AND price_unit='unit' AND unit_cost_usd_per_l IS NULL AND (kind='service' OR quantity_units=trunc(quantity_units))
   AND (unit_cost_usd IS NULL OR unit_cost_usd>=0)));
CREATE INDEX sale_lines_pos_product_idx ON sale_lines(pos_product_id);
CREATE INDEX sale_lines_offer_idx ON sale_lines(offer_version_id);
CREATE TABLE pos_stock_movements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, lot_id uuid NOT NULL,
 sale_line_id uuid, delta_units numeric(18,3) NOT NULL CHECK(delta_units<>0 AND delta_units=trunc(delta_units)),
 kind text NOT NULL CHECK(kind IN('receipt','sale')), created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(lot_id,organization_id,branch_id) REFERENCES pos_stock_lots(id,organization_id,branch_id),
 FOREIGN KEY(sale_line_id) REFERENCES sale_lines(id), UNIQUE(lot_id,sale_line_id),
 CHECK((kind='receipt' AND delta_units>0 AND sale_line_id IS NULL) OR (kind='sale' AND delta_units<0 AND sale_line_id IS NOT NULL))
);
CREATE UNIQUE INDEX pos_stock_receipt_unique ON pos_stock_movements(lot_id) WHERE kind='receipt';
CREATE INDEX pos_stock_line_idx ON pos_stock_movements(sale_line_id);

CREATE FUNCTION validate_pos_offer() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE p pos_products%ROWTYPE; last_version integer;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||NEW.product_id,0));
 SELECT * INTO p FROM pos_products WHERE id=NEW.product_id;
 SELECT coalesce(max(version),0) INTO last_version FROM pos_offer_versions WHERE product_id=NEW.product_id;
 IF p.id IS NULL OR NEW.version<>last_version+1 OR (p.kind='store' AND NEW.service_unit_cost_usd IS NOT NULL) THEN
  RAISE EXCEPTION 'Invalid POS offer version or service cost' USING ERRCODE='23514';
 END IF;
 NEW.created_at:=clock_timestamp(); RETURN NEW;
END; $$;
CREATE TRIGGER pos_offer_validate BEFORE INSERT ON pos_offer_versions FOR EACH ROW EXECUTE FUNCTION validate_pos_offer();
CREATE FUNCTION validate_pos_lot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE p pos_products%ROWTYPE; o pos_offer_versions%ROWTYPE; local_date date;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||NEW.product_id,0));
 SELECT * INTO p FROM pos_products WHERE id=NEW.product_id;
 SELECT * INTO o FROM pos_offer_versions WHERE product_id=p.id ORDER BY version DESC LIMIT 1;
 SELECT (clock_timestamp() AT TIME ZONE timezone)::date INTO local_date FROM branches WHERE id=NEW.branch_id;
 IF p.kind IS DISTINCT FROM 'store' OR o.active IS DISTINCT FROM true OR (p.expiry_required AND NEW.expires_on IS NULL)
   OR NEW.expires_on<local_date THEN RAISE EXCEPTION 'Invalid, disabled, undated or expired stock lot' USING ERRCODE='23514'; END IF;
 NEW.received_at:=clock_timestamp(); RETURN NEW;
END; $$;
CREATE TRIGGER pos_lot_validate BEFORE INSERT ON pos_stock_lots FOR EACH ROW EXECUTE FUNCTION validate_pos_lot();
CREATE FUNCTION capture_pos_receipt() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 INSERT INTO pos_stock_movements(organization_id,branch_id,lot_id,delta_units,kind)
 VALUES(NEW.organization_id,NEW.branch_id,NEW.id,NEW.quantity_received,'receipt'); RETURN NULL;
END; $$;
CREATE TRIGGER pos_lot_receipt AFTER INSERT ON pos_stock_lots FOR EACH ROW EXECUTE FUNCTION capture_pos_receipt();
CREATE FUNCTION validate_pos_stock_movement() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE l pos_stock_lots%ROWTYPE; s sale_lines%ROWTYPE; balance numeric; local_date date;
BEGIN
 SELECT * INTO l FROM pos_stock_lots WHERE id=NEW.lot_id;
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||l.product_id,0));
 IF l.id IS NULL OR NEW.organization_id<>l.organization_id OR NEW.branch_id<>l.branch_id THEN
  RAISE EXCEPTION 'Stock scope mismatch' USING ERRCODE='23514'; END IF;
 IF NEW.kind='receipt' THEN
  IF NEW.delta_units<>l.quantity_received THEN RAISE EXCEPTION 'Receipt differs from lot' USING ERRCODE='23514'; END IF;
 ELSE
  SELECT (clock_timestamp() AT TIME ZONE timezone)::date INTO local_date FROM branches WHERE id=l.branch_id;
  IF l.expires_on<local_date THEN RAISE EXCEPTION 'Expired lot cannot be sold' USING ERRCODE='23514'; END IF;
  SELECT * INTO s FROM sale_lines WHERE id=NEW.sale_line_id;
  IF s.kind IS DISTINCT FROM 'store' OR s.pos_product_id IS DISTINCT FROM l.product_id
    OR s.organization_id<>l.organization_id OR s.branch_id<>l.branch_id THEN
   RAISE EXCEPTION 'Sale allocation scope mismatch' USING ERRCODE='23514'; END IF;
 END IF;
 SELECT coalesce(sum(delta_units),0) INTO balance FROM pos_stock_movements WHERE lot_id=l.id;
 IF balance+NEW.delta_units<0 THEN RAISE EXCEPTION 'Insufficient lot stock' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER pos_stock_validate BEFORE INSERT ON pos_stock_movements FOR EACH ROW EXECUTE FUNCTION validate_pos_stock_movement();
CREATE FUNCTION validate_pos_sale_line() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE p pos_products%ROWTYPE; o pos_offer_versions%ROWTYPE; s sales%ROWTYPE; current_offer uuid;
BEGIN
 IF NEW.kind='fuel' THEN RETURN NEW; END IF;
 SELECT * INTO s FROM sales WHERE id=NEW.sale_id;
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||NEW.pos_product_id,0));
 SELECT * INTO p FROM pos_products WHERE id=NEW.pos_product_id;
 SELECT * INTO o FROM pos_offer_versions WHERE id=NEW.offer_version_id;
 SELECT id INTO current_offer FROM pos_offer_versions WHERE product_id=p.id ORDER BY version DESC LIMIT 1;
 IF s.authorization_id IS NOT NULL OR NEW.kind IS DISTINCT FROM p.kind OR o.product_id IS DISTINCT FROM p.id
  OR o.id IS DISTINCT FROM current_offer OR o.active IS DISTINCT FROM true
  OR NEW.description IS DISTINCT FROM o.description OR NEW.price_usd_per_unit IS DISTINCT FROM o.price_usd
  OR NEW.total_usd IS DISTINCT FROM round(NEW.quantity_units*o.price_usd,2)
  OR (p.kind='service' AND (NEW.unit_cost_usd IS DISTINCT FROM o.service_unit_cost_usd
      OR NEW.cost_usd IS DISTINCT FROM round(NEW.quantity_units*o.service_unit_cost_usd,8)
      OR NEW.cost_quality IS DISTINCT FROM (CASE WHEN o.service_unit_cost_usd IS NULL THEN 'unknown' ELSE 'known' END))) THEN
  RAISE EXCEPTION 'POS line differs from current offer/cost or sale kind' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER pos_sale_line_validate BEFORE INSERT ON sale_lines FOR EACH ROW EXECUTE FUNCTION validate_pos_sale_line();

CREATE OR REPLACE FUNCTION validate_fuel_sale_snapshot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a dispense_authorizations%ROWTYPE; m inventory_movements%ROWTYPE; s sales%ROWTYPE;
BEGIN
 IF TG_TABLE_NAME='sales' THEN
  IF NEW.authorization_id IS NULL THEN NEW.occurred_at:=clock_timestamp(); RETURN NEW; END IF;
  SELECT * INTO a FROM dispense_authorizations WHERE id=NEW.authorization_id;
  IF a.status IS DISTINCT FROM 'completed' OR NEW.total_usd IS DISTINCT FROM a.sale_amount_usd
    OR NEW.occurred_at IS DISTINCT FROM a.completed_at THEN
   RAISE EXCEPTION 'Sale requires a completed dispatch and its original amount/time' USING ERRCODE='23514';
  END IF;
 ELSE
  IF NEW.kind<>'fuel' THEN RETURN NEW; END IF;
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
CREATE OR REPLACE FUNCTION validate_fuel_sale_line_count() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE n integer; total numeric; l sale_lines%ROWTYPE; allocated numeric; amount numeric; unknown_count integer;
BEGIN
 SELECT count(*),sum(total_usd) INTO n,total FROM sale_lines WHERE sale_id=NEW.id;
 IF n<1 OR n>50 OR total IS DISTINCT FROM NEW.total_usd THEN
  RAISE EXCEPTION 'Sale requires 1-50 lines whose amounts sum to the header' USING ERRCODE='23514'; END IF;
 IF NEW.authorization_id IS NOT NULL THEN
  IF n<>1 OR EXISTS(SELECT 1 FROM sale_lines WHERE sale_id=NEW.id AND kind<>'fuel') THEN
   RAISE EXCEPTION 'Fuel sale requires exactly one original dispatch line' USING ERRCODE='23514'; END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM sale_lines WHERE sale_id=NEW.id AND kind='fuel') THEN
   RAISE EXCEPTION 'POS sale cannot contain fuel without dispatch' USING ERRCODE='23514'; END IF;
  FOR l IN SELECT * FROM sale_lines WHERE sale_id=NEW.id AND kind='store' LOOP
   SELECT -coalesce(sum(m.delta_units),0),sum(-m.delta_units*b.unit_cost_usd),count(*) FILTER(WHERE b.unit_cost_usd IS NULL)
    INTO allocated,amount,unknown_count FROM pos_stock_movements m JOIN pos_stock_lots b ON b.id=m.lot_id WHERE m.sale_line_id=l.id;
   IF allocated<>l.quantity_units OR l.cost_quality IS DISTINCT FROM (CASE WHEN unknown_count>0 THEN 'unknown' ELSE 'known' END)
     OR l.cost_usd IS DISTINCT FROM (CASE WHEN unknown_count>0 THEN NULL ELSE amount END) OR l.unit_cost_usd IS NOT NULL THEN
    RAISE EXCEPTION 'Store allocation quantity or cost mismatch' USING ERRCODE='23514'; END IF;
  END LOOP;
 END IF;
 RETURN NULL;
END; $$;
-- Allocations cannot be appended to an old sale and bypass the deferred header check.
CREATE FUNCTION check_pos_allocation_total() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE l sale_lines%ROWTYPE; allocated numeric; amount numeric; unknown_count integer;
BEGIN
 IF NEW.kind='receipt' THEN RETURN NULL; END IF;
 SELECT * INTO l FROM sale_lines WHERE id=NEW.sale_line_id;
 SELECT -sum(m.delta_units),sum(-m.delta_units*b.unit_cost_usd),count(*) FILTER(WHERE b.unit_cost_usd IS NULL)
 INTO allocated,amount,unknown_count FROM pos_stock_movements m JOIN pos_stock_lots b ON b.id=m.lot_id WHERE m.sale_line_id=l.id;
 IF allocated<>l.quantity_units OR l.cost_quality IS DISTINCT FROM (CASE WHEN unknown_count>0 THEN 'unknown' ELSE 'known' END)
   OR l.cost_usd IS DISTINCT FROM (CASE WHEN unknown_count>0 THEN NULL ELSE amount END) THEN
  RAISE EXCEPTION 'Store allocation quantity or cost mismatch' USING ERRCODE='23514'; END IF;
 RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER pos_allocation_complete AFTER INSERT ON pos_stock_movements DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION check_pos_allocation_total();

CREATE FUNCTION post_pos_sale(org uuid,branch uuid,actor uuid,command uuid,request_hash_value text,items jsonb,correlation uuid)
 RETURNS uuid LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE ticket uuid; existing sales%ROWTYPE; item jsonb; p pos_products%ROWTYPE; o pos_offer_versions%ROWTYPE;
 line_id uuid; quantity numeric; total numeric:=0; line_total numeric; n integer:=0;
 remaining numeric; available numeric; take numeric; lot pos_stock_lots%ROWTYPE; cost numeric; quality text; local_date date;
BEGIN
 IF items IS NULL OR jsonb_typeof(items)<>'array' OR jsonb_array_length(items) NOT BETWEEN 1 AND 50 THEN
  RAISE EXCEPTION 'POS sale requires 1-50 items' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(items) i WHERE jsonb_typeof(i)<>'object' OR NOT i ?& ARRAY['productId','offerVersionId','quantity']
  OR (SELECT count(*) FROM jsonb_object_keys(i))<>3 OR jsonb_typeof(i->'quantity')<>'string'
  OR (i->>'quantity')!~'^[0-9]{1,9}(\.[0-9]{1,3})?$') THEN RAISE EXCEPTION 'Invalid sale item' USING ERRCODE='23514'; END IF;
 IF (SELECT count(DISTINCT (i->>'productId')::uuid) FROM jsonb_array_elements(items) i)<>jsonb_array_length(items) THEN
  RAISE EXCEPTION 'Combine repeated products in one line' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('sale:'||org||':'||command,0));
 SELECT * INTO existing FROM sales WHERE organization_id=org AND command_id=command;
 IF existing.id IS NOT NULL THEN
  IF existing.request_hash<>request_hash_value OR existing.branch_id<>branch OR existing.authorization_id IS NOT NULL THEN
   RAISE EXCEPTION 'Command was reused with a different sale' USING ERRCODE='23514'; END IF;
  RETURN existing.id;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM branches WHERE id=branch AND organization_id=org AND status='active') THEN
  RAISE EXCEPTION 'Branch is unavailable' USING ERRCODE='23514'; END IF;
 SELECT (clock_timestamp() AT TIME ZONE timezone)::date INTO local_date FROM branches WHERE id=branch;
 -- One consistent lock order for offers, receipts and sales prevents reverse basket deadlocks.
 FOR p IN SELECT * FROM pos_products WHERE organization_id=org AND branch_id=branch
  AND id IN(SELECT (i->>'productId')::uuid FROM jsonb_array_elements(items) i) ORDER BY id LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||p.id,0));
 END LOOP;
 FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
  SELECT * INTO p FROM pos_products WHERE id=(item->>'productId')::uuid AND organization_id=org AND branch_id=branch;
  SELECT * INTO o FROM pos_offer_versions WHERE product_id=p.id ORDER BY version DESC LIMIT 1;
  quantity:=(item->>'quantity')::numeric;
  IF p.id IS NULL OR o.id IS DISTINCT FROM (item->>'offerVersionId')::uuid OR o.active IS DISTINCT FROM true OR quantity<=0
    OR (p.kind='store' AND quantity<>trunc(quantity)) THEN RAISE EXCEPTION 'Product, price version or quantity is unavailable' USING ERRCODE='23514'; END IF;
  total:=total+round(quantity*o.price_usd,2);
 END LOOP;
 IF total>9999999999999999.99 THEN RAISE EXCEPTION 'Sale total exceeds supported amount' USING ERRCODE='23514'; END IF;
 INSERT INTO sales(organization_id,branch_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id)
 VALUES(org,branch,command,request_hash_value,total,actor,clock_timestamp(),correlation) RETURNING id INTO ticket;
 FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
  n:=n+1; quantity:=(item->>'quantity')::numeric;
  SELECT * INTO p FROM pos_products WHERE id=(item->>'productId')::uuid;
  SELECT * INTO o FROM pos_offer_versions WHERE product_id=p.id ORDER BY version DESC LIMIT 1;
  cost:=NULL; quality:='unknown';
  IF p.kind='service' THEN cost:=round(quantity*o.service_unit_cost_usd,8); quality:=CASE WHEN cost IS NULL THEN 'unknown' ELSE 'known' END;
  ELSE
   -- Cost the same FEFO allocation that will be posted below; locked product excludes competing receipts/sales.
   remaining:=quantity; cost:=0; quality:='known';
   FOR lot IN SELECT * FROM pos_stock_lots WHERE product_id=p.id AND (expires_on IS NULL OR expires_on>=local_date)
     ORDER BY expires_on NULLS LAST,received_at,id LOOP
    SELECT coalesce(sum(delta_units),0) INTO available FROM pos_stock_movements WHERE lot_id=lot.id;
    take:=least(remaining,available); IF take<=0 THEN CONTINUE; END IF;
    IF lot.unit_cost_usd IS NULL THEN quality:='unknown'; ELSE cost:=cost+take*lot.unit_cost_usd; END IF;
    remaining:=remaining-take; EXIT WHEN remaining=0;
   END LOOP;
   IF remaining>0 THEN RAISE EXCEPTION 'Insufficient unexpired stock' USING ERRCODE='23514'; END IF;
   IF quality='unknown' THEN cost:=NULL; END IF;
  END IF;
  INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,kind,pos_product_id,offer_version_id,description,quantity_units,
    price_usd_per_unit,price_unit,total_usd,cost_usd,unit_cost_usd,cost_quality)
  VALUES(org,branch,ticket,n,p.kind,p.id,o.id,o.description,quantity,o.price_usd,'unit',round(quantity*o.price_usd,2),cost,
    CASE WHEN p.kind='service' THEN o.service_unit_cost_usd END,quality) RETURNING id INTO line_id;
  IF p.kind='store' THEN
   remaining:=quantity;
   FOR lot IN SELECT * FROM pos_stock_lots WHERE product_id=p.id AND (expires_on IS NULL OR expires_on>=local_date)
     ORDER BY expires_on NULLS LAST,received_at,id LOOP
    SELECT coalesce(sum(delta_units),0) INTO available FROM pos_stock_movements WHERE lot_id=lot.id;
    take:=least(remaining,available); IF take<=0 THEN CONTINUE; END IF;
    INSERT INTO pos_stock_movements(organization_id,branch_id,lot_id,sale_line_id,delta_units,kind) VALUES(org,branch,lot.id,line_id,-take,'sale');
    remaining:=remaining-take; EXIT WHEN remaining=0;
   END LOOP;
  END IF;
 END LOOP;
 RETURN ticket;
END; $$;

DO $$ DECLARE t text; f regprocedure; BEGIN
 FOREACH t IN ARRAY ARRAY['pos_products','pos_offer_versions','pos_stock_lots','pos_stock_movements'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
  EXECUTE format('CREATE TRIGGER pos_fact_immutable BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',t);
 END LOOP;
 FOR f IN SELECT oid::regprocedure FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('validate_pos_offer','validate_pos_lot','capture_pos_receipt','validate_pos_stock_movement','validate_pos_sale_line','check_pos_allocation_total','post_pos_sale') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f);
 END LOOP;
END; $$;
GRANT EXECUTE ON FUNCTION post_pos_sale(uuid,uuid,uuid,uuid,text,jsonb,uuid) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES('pos.catalog.read','Consultar catálogo de tienda y servicios'),
 ('pos.catalog.manage','Publicar versiones del catálogo de tienda y servicios'),('pos.stock.receive','Registrar lotes de tienda') ON CONFLICT(code) DO NOTHING;

CREATE FUNCTION check_sale_line_header_total() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE s sales%ROWTYPE; n integer; total numeric;
BEGIN
 SELECT * INTO s FROM sales WHERE id=NEW.sale_id;
 SELECT count(*),sum(total_usd) INTO n,total FROM sale_lines WHERE sale_id=s.id;
 IF n NOT BETWEEN 1 AND 50 OR total IS DISTINCT FROM s.total_usd OR
   (s.authorization_id IS NOT NULL AND (n<>1 OR NEW.kind<>'fuel')) OR
   (s.authorization_id IS NULL AND NEW.kind='fuel') THEN
  RAISE EXCEPTION 'Sale lines must preserve original header total/kind' USING ERRCODE='23514'; END IF;
 RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER sale_line_header_total AFTER INSERT ON sale_lines DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION check_sale_line_header_total();
REVOKE ALL ON FUNCTION check_sale_line_header_total() FROM PUBLIC,anon,authenticated,service_role;
-- Even a line that rounds to $0 must not be added to an already issued ticket.
ALTER TABLE sales ADD COLUMN created_xid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE FUNCTION stamp_sale_transaction() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN NEW.created_xid:=pg_current_xact_id(); RETURN NEW; END; $$;
CREATE TRIGGER sales_transaction BEFORE INSERT ON sales FOR EACH ROW EXECUTE FUNCTION stamp_sale_transaction();
CREATE FUNCTION validate_sale_line_transaction() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF (SELECT created_xid FROM sales WHERE id=NEW.sale_id) IS DISTINCT FROM pg_current_xact_id() THEN
  RAISE EXCEPTION 'Issued ticket lines cannot be appended in a later transaction' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER sale_line_transaction BEFORE INSERT ON sale_lines FOR EACH ROW EXECUTE FUNCTION validate_sale_line_transaction();
REVOKE ALL ON FUNCTION stamp_sale_transaction(),validate_sale_line_transaction() FROM PUBLIC,anon,authenticated,service_role;
