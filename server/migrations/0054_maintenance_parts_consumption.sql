-- Actual spare-part usage is valued from the issued lot, not the order estimate.
CREATE TABLE maintenance_part_consumptions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 order_id uuid NOT NULL,lot_id uuid NOT NULL,quantity_units integer NOT NULL CHECK(quantity_units>0),
 cost_usd numeric(18,2),cost_quality text NOT NULL CHECK(cost_quality IN('known','unknown')),
 task_reference text NOT NULL CHECK(length(btrim(task_reference)) BETWEEN 5 AND 300),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 used_by uuid NOT NULL,used_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(order_id,organization_id,branch_id) REFERENCES maintenance_work_orders(id,organization_id,branch_id),
 FOREIGN KEY(lot_id,organization_id,branch_id) REFERENCES pos_stock_lots(id,organization_id,branch_id),
 FOREIGN KEY(used_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id),UNIQUE(id,organization_id,branch_id),
 CHECK((cost_quality='unknown' AND cost_usd IS NULL) OR (cost_quality='known' AND cost_usd IS NOT NULL))
);
ALTER TABLE pos_stock_movements ADD COLUMN consumption_id uuid,
 ADD CONSTRAINT stock_movement_consumption_fk FOREIGN KEY(consumption_id,organization_id,branch_id)
  REFERENCES maintenance_part_consumptions(id,organization_id,branch_id),
 DROP CONSTRAINT pos_stock_movements_kind_check,DROP CONSTRAINT pos_stock_movements_check,
 ADD CONSTRAINT pos_stock_movements_kind_check CHECK(kind IN('receipt','sale','transfer_out','count_adjustment','maintenance_use')),
 ADD CONSTRAINT pos_stock_movements_check CHECK(
  (kind='receipt' AND delta_units>0 AND sale_line_id IS NULL AND transfer_id IS NULL AND count_id IS NULL AND consumption_id IS NULL)
  OR (kind='sale' AND delta_units<0 AND sale_line_id IS NOT NULL AND transfer_id IS NULL AND count_id IS NULL AND consumption_id IS NULL)
  OR (kind='transfer_out' AND delta_units<0 AND sale_line_id IS NULL AND transfer_id IS NOT NULL AND count_id IS NULL AND consumption_id IS NULL)
  OR (kind='count_adjustment' AND delta_units<>0 AND sale_line_id IS NULL AND transfer_id IS NULL AND count_id IS NOT NULL AND consumption_id IS NULL)
  OR (kind='maintenance_use' AND delta_units<0 AND sale_line_id IS NULL AND transfer_id IS NULL AND count_id IS NULL AND consumption_id IS NOT NULL));
CREATE UNIQUE INDEX pos_stock_maintenance_once ON pos_stock_movements(consumption_id) WHERE kind='maintenance_use';

CREATE OR REPLACE FUNCTION validate_pos_stock_movement() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE l pos_stock_lots%ROWTYPE; s sale_lines%ROWTYPE; t store_transfers%ROWTYPE; c store_count_approvals%ROWTYPE; mc maintenance_part_consumptions%ROWTYPE; balance numeric; local_date date;
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
CREATE FUNCTION use_maintenance_part(p_org uuid,p_branch uuid,p_actor uuid,p_order uuid,p_lot uuid,p_quantity integer,
 p_reference text,p_command uuid,p_hash text,p_correlation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old maintenance_part_consumptions%ROWTYPE; w maintenance_work_orders%ROWTYPE;
 l pos_stock_lots%ROWTYPE; result uuid;
BEGIN
 IF p_quantity IS NULL OR p_quantity<=0 OR p_reference IS NULL OR length(btrim(p_reference)) NOT BETWEEN 5 AND 300
  OR p_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid spare-part use' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('maintenance-part:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM maintenance_part_consumptions WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.used_by<>p_actor THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.id;
 END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO w FROM maintenance_work_orders WHERE id=p_order AND organization_id=p_org AND branch_id=p_branch;
 SELECT * INTO l FROM pos_stock_lots WHERE id=p_lot AND organization_id=p_org AND branch_id=p_branch;
 IF w.id IS NULL OR w.status<>'in_progress' OR l.id IS NULL OR l.condition<>'sellable'
  OR NOT EXISTS(SELECT 1 FROM branch_assortments a JOIN store_catalog_products c ON c.id=a.catalog_product_id
    WHERE a.pos_product_id=l.product_id AND c.kind='part' AND a.active AND c.active)
 THEN RAISE EXCEPTION 'Order or spare part unavailable' USING ERRCODE='23514'; END IF;
 INSERT INTO maintenance_part_consumptions(organization_id,branch_id,order_id,lot_id,quantity_units,cost_usd,
  cost_quality,task_reference,command_id,request_hash,used_by,correlation_id)
 VALUES(p_org,p_branch,p_order,p_lot,p_quantity,
  CASE WHEN l.unit_cost_usd IS NULL THEN NULL ELSE round(l.unit_cost_usd*p_quantity,2) END,
  CASE WHEN l.unit_cost_usd IS NULL THEN 'unknown' ELSE 'known' END,
  btrim(p_reference),p_command,p_hash,p_actor,p_correlation) RETURNING id INTO result;
 INSERT INTO pos_stock_movements(organization_id,branch_id,lot_id,kind,delta_units,consumption_id)
 VALUES(p_org,p_branch,p_lot,'maintenance_use',-p_quantity,result);
 RETURN result;
END $$;
ALTER TABLE maintenance_part_consumptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON maintenance_part_consumptions FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON maintenance_part_consumptions TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON maintenance_part_consumptions FOR SELECT TO dlc_api_runtime USING(true);
CREATE TRIGGER maintenance_part_immutable BEFORE UPDATE OR DELETE ON maintenance_part_consumptions FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION use_maintenance_part(uuid,uuid,uuid,uuid,uuid,integer,text,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION use_maintenance_part(uuid,uuid,uuid,uuid,uuid,integer,text,uuid,text,uuid) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES('maintenance.part.use','Consumir repuestos trazados en orden de mantenimiento') ON CONFLICT(code) DO NOTHING;
