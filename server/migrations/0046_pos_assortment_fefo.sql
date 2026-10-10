-- Only active assortments and sellable lots feed POS and FEFO allocations.
CREATE OR REPLACE FUNCTION validate_pos_lot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE p pos_products%ROWTYPE; o pos_offer_versions%ROWTYPE; local_date date;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||NEW.product_id,0));
 SELECT * INTO p FROM pos_products WHERE id=NEW.product_id;
 SELECT * INTO o FROM pos_offer_versions WHERE product_id=p.id ORDER BY version DESC LIMIT 1;
 SELECT (clock_timestamp() AT TIME ZONE timezone)::date INTO local_date FROM branches WHERE id=NEW.branch_id;
 IF p.kind IS DISTINCT FROM 'store' OR o.active IS DISTINCT FROM true OR NOT EXISTS(SELECT 1 FROM branch_assortments a JOIN store_catalog_products cp ON cp.id=a.catalog_product_id WHERE a.pos_product_id=p.id AND a.active AND cp.active) OR (p.expiry_required AND NEW.expires_on IS NULL)
   OR NEW.expires_on<local_date THEN RAISE EXCEPTION 'Invalid, disabled, undated or expired stock lot' USING ERRCODE='23514'; END IF;
 NEW.received_at:=clock_timestamp(); RETURN NEW;
END; $$;
CREATE OR REPLACE FUNCTION validate_pos_stock_movement() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
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
  IF l.condition<>'sellable' OR l.expires_on<local_date THEN RAISE EXCEPTION 'Expired lot cannot be sold' USING ERRCODE='23514'; END IF;
  SELECT * INTO s FROM sale_lines WHERE id=NEW.sale_line_id;
  IF s.kind IS DISTINCT FROM 'store' OR s.pos_product_id IS DISTINCT FROM l.product_id
    OR s.organization_id<>l.organization_id OR s.branch_id<>l.branch_id THEN
   RAISE EXCEPTION 'Sale allocation scope mismatch' USING ERRCODE='23514'; END IF;
 END IF;
 SELECT coalesce(sum(delta_units),0) INTO balance FROM pos_stock_movements WHERE lot_id=l.id;
 IF balance+NEW.delta_units<0 THEN RAISE EXCEPTION 'Insufficient lot stock' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE OR REPLACE FUNCTION post_pos_sale(org uuid,branch uuid,actor uuid,command uuid,request_hash_value text,items jsonb,correlation uuid)
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
    OR (p.kind='store' AND (quantity<>trunc(quantity) OR NOT EXISTS(SELECT 1 FROM branch_assortments a JOIN store_catalog_products cp ON cp.id=a.catalog_product_id WHERE a.pos_product_id=p.id AND a.active AND cp.active))) THEN RAISE EXCEPTION 'Product, price version or quantity is unavailable' USING ERRCODE='23514'; END IF;
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
   FOR lot IN SELECT * FROM pos_stock_lots WHERE product_id=p.id AND condition='sellable' AND (expires_on IS NULL OR expires_on>=local_date)
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
   FOR lot IN SELECT * FROM pos_stock_lots WHERE product_id=p.id AND condition='sellable' AND (expires_on IS NULL OR expires_on>=local_date)
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

