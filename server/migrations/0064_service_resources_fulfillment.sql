-- A service sale has a published offer; its physical execution consumes real lots.
CREATE TABLE service_catalog_details (
 product_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 tax_code text,work_description text NOT NULL CHECK(length(btrim(work_description)) BETWEEN 5 AND 300),
 active boolean NOT NULL DEFAULT true,created_by uuid NOT NULL,
 FOREIGN KEY(product_id,organization_id,branch_id) REFERENCES pos_products(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(product_id,organization_id,branch_id)
);
CREATE FUNCTION validate_service_catalog() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pos_products p WHERE p.id=NEW.product_id AND p.organization_id=NEW.organization_id
  AND p.branch_id=NEW.branch_id AND p.kind='service') THEN
  RAISE EXCEPTION 'Service product mismatch' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER service_catalog_guard BEFORE INSERT OR UPDATE ON service_catalog_details
 FOR EACH ROW EXECUTE FUNCTION validate_service_catalog();
CREATE TABLE service_material_requirements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 offer_version_id uuid NOT NULL,catalog_product_id uuid NOT NULL,
 units_per_service numeric(18,3) NOT NULL CHECK(units_per_service>0 AND units_per_service=trunc(units_per_service)),
 created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(offer_version_id,organization_id,branch_id) REFERENCES pos_offer_versions(id,organization_id,branch_id),
 FOREIGN KEY(catalog_product_id,organization_id) REFERENCES store_catalog_products(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(offer_version_id,catalog_product_id)
);
CREATE FUNCTION validate_service_recipe() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE v pos_offer_versions%ROWTYPE;
BEGIN
 SELECT * INTO v FROM pos_offer_versions WHERE id=NEW.offer_version_id;
 IF v.id IS NULL OR v.organization_id<>NEW.organization_id OR v.branch_id<>NEW.branch_id
  OR NOT EXISTS(SELECT 1 FROM service_catalog_details d WHERE d.product_id=v.product_id AND d.active)
  OR NOT EXISTS(SELECT 1 FROM store_catalog_products c WHERE c.id=NEW.catalog_product_id
    AND c.organization_id=NEW.organization_id AND c.active AND c.kind IN('store','part','lubricant'))
  OR EXISTS(SELECT 1 FROM sale_lines l WHERE l.offer_version_id=v.id)
 THEN RAISE EXCEPTION 'Recipe cannot change after first sale or reference unavailable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER service_recipe_guard BEFORE INSERT ON service_material_requirements
 FOR EACH ROW EXECUTE FUNCTION validate_service_recipe();
CREATE TABLE service_fulfillments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,sale_line_id uuid NOT NULL,
 work_reference text NOT NULL CHECK(length(btrim(work_reference)) BETWEEN 5 AND 200),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 fulfilled_by uuid NOT NULL,fulfilled_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(sale_line_id) REFERENCES sale_lines(id),FOREIGN KEY(fulfilled_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(sale_line_id),UNIQUE(organization_id,command_id),UNIQUE(id,organization_id,branch_id)
);
ALTER TABLE pos_stock_movements ADD COLUMN service_fulfillment_id uuid,
 ADD CONSTRAINT stock_movement_service_fk FOREIGN KEY(service_fulfillment_id,organization_id,branch_id)
 REFERENCES service_fulfillments(id,organization_id,branch_id),
 DROP CONSTRAINT pos_stock_movements_kind_check,DROP CONSTRAINT pos_stock_movements_check,
 ADD CONSTRAINT pos_stock_movements_kind_check CHECK(kind IN('receipt','sale','transfer_out','count_adjustment','maintenance_use','service_use')),
 ADD CONSTRAINT pos_stock_movements_check CHECK(
  (kind='receipt' AND delta_units>0 AND sale_line_id IS NULL AND transfer_id IS NULL AND count_id IS NULL AND consumption_id IS NULL AND service_fulfillment_id IS NULL)
  OR (kind='sale' AND delta_units<0 AND sale_line_id IS NOT NULL AND transfer_id IS NULL AND count_id IS NULL AND consumption_id IS NULL AND service_fulfillment_id IS NULL)
  OR (kind='transfer_out' AND delta_units<0 AND sale_line_id IS NULL AND transfer_id IS NOT NULL AND count_id IS NULL AND consumption_id IS NULL AND service_fulfillment_id IS NULL)
  OR (kind='count_adjustment' AND delta_units<>0 AND sale_line_id IS NULL AND transfer_id IS NULL AND count_id IS NOT NULL AND consumption_id IS NULL AND service_fulfillment_id IS NULL)
  OR (kind='maintenance_use' AND delta_units<0 AND sale_line_id IS NULL AND transfer_id IS NULL AND count_id IS NULL AND consumption_id IS NOT NULL AND service_fulfillment_id IS NULL)
  OR (kind='service_use' AND delta_units<0 AND sale_line_id IS NULL AND transfer_id IS NULL AND count_id IS NULL AND consumption_id IS NULL AND service_fulfillment_id IS NOT NULL));

CREATE OR REPLACE FUNCTION validate_pos_stock_movement() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE l pos_stock_lots%ROWTYPE; s sale_lines%ROWTYPE; t store_transfers%ROWTYPE; c store_count_approvals%ROWTYPE;
 mc maintenance_part_consumptions%ROWTYPE; sf service_fulfillments%ROWTYPE; balance numeric; local_date date;
BEGIN
 SELECT * INTO l FROM pos_stock_lots WHERE id=NEW.lot_id;
 IF l.id IS NULL OR NEW.organization_id<>l.organization_id OR NEW.branch_id<>l.branch_id THEN
  RAISE EXCEPTION 'Stock scope mismatch' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||l.product_id,0));
 IF NEW.kind='receipt' THEN
  IF NEW.delta_units<>l.quantity_received THEN RAISE EXCEPTION 'Receipt differs from lot' USING ERRCODE='23514'; END IF;
 ELSIF NEW.kind='count_adjustment' THEN
  SELECT * INTO c FROM store_count_approvals WHERE count_id=NEW.count_id;
  IF c.count_id IS NULL OR c.organization_id<>l.organization_id OR c.branch_id<>l.branch_id OR c.delta_units<>NEW.delta_units
   OR NOT EXISTS(SELECT 1 FROM store_stock_counts WHERE id=c.count_id AND lot_id=l.id)
   THEN RAISE EXCEPTION 'Count adjustment mismatch' USING ERRCODE='23514'; END IF;
 ELSE
  SELECT (clock_timestamp() AT TIME ZONE timezone)::date INTO local_date FROM branches WHERE id=l.branch_id;
  IF l.condition<>'sellable' OR l.expires_on<local_date THEN RAISE EXCEPTION 'Unavailable lot cannot leave stock' USING ERRCODE='23514'; END IF;
  IF NEW.kind='maintenance_use' THEN
   SELECT * INTO mc FROM maintenance_part_consumptions WHERE id=NEW.consumption_id;
   IF mc.id IS NULL OR mc.organization_id<>l.organization_id OR mc.branch_id<>l.branch_id
    OR mc.lot_id<>l.id OR NEW.delta_units<>-mc.quantity_units
   THEN RAISE EXCEPTION 'Spare-part issue mismatch' USING ERRCODE='23514'; END IF;
  ELSIF NEW.kind='service_use' THEN
   SELECT * INTO sf FROM service_fulfillments WHERE id=NEW.service_fulfillment_id;
   SELECT * INTO s FROM sale_lines WHERE id=sf.sale_line_id;
   IF sf.id IS NULL OR sf.organization_id<>l.organization_id OR sf.branch_id<>l.branch_id OR s.kind<>'service'
    OR NOT EXISTS(SELECT 1 FROM service_material_requirements req
       JOIN branch_assortments a ON a.catalog_product_id=req.catalog_product_id AND a.branch_id=l.branch_id
       WHERE req.offer_version_id=s.offer_version_id AND a.pos_product_id=l.product_id AND a.active)
   THEN RAISE EXCEPTION 'Service material mismatch' USING ERRCODE='23514'; END IF;
  ELSIF NEW.kind='sale' THEN
   SELECT * INTO s FROM sale_lines WHERE id=NEW.sale_line_id;
   IF s.kind IS DISTINCT FROM 'store' OR s.pos_product_id IS DISTINCT FROM l.product_id OR s.organization_id<>l.organization_id OR s.branch_id<>l.branch_id
    THEN RAISE EXCEPTION 'Sale allocation scope mismatch' USING ERRCODE='23514'; END IF;
  ELSIF NEW.kind='transfer_out' THEN
   SELECT * INTO t FROM store_transfers WHERE id=NEW.transfer_id;
   IF t.id IS NULL OR t.organization_id<>l.organization_id OR t.source_lot_id<>l.id OR t.source_branch_id<>l.branch_id
     OR NEW.delta_units<>-t.quantity_sent THEN RAISE EXCEPTION 'Transfer allocation mismatch' USING ERRCODE='23514'; END IF;
  END IF;
 END IF;
 SELECT coalesce(sum(delta_units),0) INTO balance FROM pos_stock_movements WHERE lot_id=l.id;
 IF balance+NEW.delta_units<0 THEN RAISE EXCEPTION 'Insufficient lot stock' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;

CREATE FUNCTION fulfill_pos_service(p_org uuid,p_branch uuid,p_actor uuid,p_line uuid,p_reference text,
 p_command uuid,p_hash text,p_correlation uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old service_fulfillments%ROWTYPE; line sale_lines%ROWTYPE; req record; lot record; remaining numeric;
 result uuid; local_date date;
BEGIN
 IF p_hash !~ '^[0-9a-f]{64}$' OR length(btrim(p_reference)) NOT BETWEEN 5 AND 200
  THEN RAISE EXCEPTION 'Invalid service execution' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('service-command:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM service_fulfillments WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.fulfilled_by<>p_actor OR old.sale_line_id<>p_line THEN
   RAISE EXCEPTION 'Command reused' USING ERRCODE='23514'; END IF;
  RETURN old.id;
 END IF;
 SELECT * INTO line FROM sale_lines WHERE id=p_line AND organization_id=p_org AND branch_id=p_branch AND kind='service';
 SELECT (clock_timestamp() AT TIME ZONE timezone)::date INTO local_date FROM branches WHERE id=p_branch;
 IF line.id IS NULL OR NOT EXISTS(SELECT 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active')
  OR NOT EXISTS(SELECT 1 FROM service_catalog_details WHERE product_id=line.pos_product_id AND active)
  THEN RAISE EXCEPTION 'Service unavailable' USING ERRCODE='23514'; END IF;
 INSERT INTO service_fulfillments(organization_id,branch_id,sale_line_id,work_reference,command_id,request_hash,fulfilled_by,correlation_id)
 VALUES(p_org,p_branch,p_line,btrim(p_reference),p_command,p_hash,p_actor,p_correlation) RETURNING id INTO result;
 FOR req IN SELECT a.pos_product_id,ceil(r.units_per_service*line.quantity_units) AS need
  FROM service_material_requirements r JOIN branch_assortments a ON a.catalog_product_id=r.catalog_product_id
   AND a.branch_id=p_branch AND a.active
  WHERE r.offer_version_id=line.offer_version_id ORDER BY a.pos_product_id
 LOOP
  remaining:=req.need;
  PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||req.pos_product_id,0));
  FOR lot IN SELECT l.id, l.quantity_received+coalesce(sum(m.delta_units) FILTER(WHERE m.kind<>'receipt'),0) AS available
   FROM pos_stock_lots l LEFT JOIN pos_stock_movements m ON m.lot_id=l.id
   WHERE l.product_id=req.pos_product_id AND l.branch_id=p_branch AND l.condition='sellable'
    AND (l.expires_on IS NULL OR l.expires_on>=local_date)
   GROUP BY l.id ORDER BY l.expires_on NULLS LAST,l.received_at,l.id
  LOOP
   IF remaining<=0 THEN EXIT; END IF;
   IF lot.available>0 THEN
    INSERT INTO pos_stock_movements(organization_id,branch_id,lot_id,kind,delta_units,service_fulfillment_id)
    VALUES(p_org,p_branch,lot.id,'service_use',-least(remaining,lot.available),result);
    remaining:=remaining-least(remaining,lot.available);
   END IF;
  END LOOP;
  IF remaining>0 THEN RAISE EXCEPTION 'Insufficient service materials' USING ERRCODE='23514'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM service_material_requirements r WHERE r.offer_version_id=line.offer_version_id
  AND NOT EXISTS(SELECT 1 FROM branch_assortments a WHERE a.catalog_product_id=r.catalog_product_id
   AND a.branch_id=p_branch AND a.active))
 THEN RAISE EXCEPTION 'Required material not assigned to branch' USING ERRCODE='23514'; END IF;
 RETURN result;
END $$;
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['service_catalog_details','service_material_requirements','service_fulfillments'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('REVOKE ALL ON %I FROM PUBLIC,anon,authenticated,service_role',tab);
  EXECUTE format('GRANT SELECT ON %I TO dlc_api_runtime',tab);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',tab);
 END LOOP;
END $$;
GRANT INSERT ON service_catalog_details,service_material_requirements TO dlc_api_runtime;
CREATE POLICY dlc_api_insert ON service_catalog_details FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_insert ON service_material_requirements FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE TRIGGER service_recipe_immutable BEFORE UPDATE OR DELETE ON service_material_requirements
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE TRIGGER service_fulfillment_immutable BEFORE UPDATE OR DELETE ON service_fulfillments
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION validate_service_catalog(),validate_service_recipe(),
 fulfill_pos_service(uuid,uuid,uuid,uuid,text,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION fulfill_pos_service(uuid,uuid,uuid,uuid,text,uuid,text,uuid) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES
 ('pos.service.catalog.manage','Administrar servicio y recursos'),
 ('pos.service.fulfill','Ejecutar servicio y consumir materiales') ON CONFLICT(code) DO NOTHING;
