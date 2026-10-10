-- Physical count snapshots; a second actor approves a difference against a fresh ledger.
CREATE TABLE store_stock_counts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,lot_id uuid NOT NULL,
 expected_units integer NOT NULL CHECK(expected_units>=0),observed_units integer NOT NULL CHECK(observed_units>=0),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 counted_by uuid NOT NULL,counted_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(lot_id,organization_id,branch_id) REFERENCES pos_stock_lots(id,organization_id,branch_id),
 FOREIGN KEY(counted_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id),
 UNIQUE(id,organization_id,branch_id)
);
CREATE TABLE store_count_approvals (
 count_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 delta_units integer NOT NULL,command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 approved_by uuid NOT NULL,approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(count_id,organization_id,branch_id) REFERENCES store_stock_counts(id,organization_id,branch_id),
 FOREIGN KEY(approved_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id),
 UNIQUE(count_id,organization_id,branch_id)
);
ALTER TABLE pos_stock_movements ADD COLUMN count_id uuid,
 ADD CONSTRAINT stock_movement_count_fk FOREIGN KEY(count_id,organization_id,branch_id) REFERENCES store_count_approvals(count_id,organization_id,branch_id),
 DROP CONSTRAINT pos_stock_movements_kind_check,DROP CONSTRAINT pos_stock_movements_check,
 ADD CONSTRAINT pos_stock_movements_kind_check CHECK(kind IN('receipt','sale','transfer_out','count_adjustment')),
 ADD CONSTRAINT pos_stock_movements_check CHECK(
 (kind='receipt' AND delta_units>0 AND sale_line_id IS NULL AND transfer_id IS NULL AND count_id IS NULL)
 OR (kind='sale' AND delta_units<0 AND sale_line_id IS NOT NULL AND transfer_id IS NULL AND count_id IS NULL)
 OR (kind='transfer_out' AND delta_units<0 AND sale_line_id IS NULL AND transfer_id IS NOT NULL AND count_id IS NULL)
 OR (kind='count_adjustment' AND delta_units<>0 AND sale_line_id IS NULL AND transfer_id IS NULL AND count_id IS NOT NULL));
CREATE UNIQUE INDEX pos_stock_count_adjustment_once ON pos_stock_movements(count_id) WHERE kind='count_adjustment';

CREATE OR REPLACE FUNCTION validate_pos_stock_movement() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE l pos_stock_lots%ROWTYPE; s sale_lines%ROWTYPE; t store_transfers%ROWTYPE; c store_count_approvals%ROWTYPE; balance numeric; local_date date;
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
  IF NEW.kind='sale' THEN
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
CREATE FUNCTION capture_store_count(p_org uuid,p_branch uuid,p_actor uuid,p_lot uuid,p_observed integer,
 p_reason text,p_command uuid,p_hash text,p_correlation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE l pos_stock_lots%ROWTYPE; old store_stock_counts%ROWTYPE; expected integer; count_id uuid;
BEGIN
 IF p_observed IS NULL OR p_observed<0 OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500
  OR p_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid count' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('store-count:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM store_stock_counts WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.counted_by<>p_actor THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.id;
 END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO l FROM pos_stock_lots WHERE id=p_lot AND organization_id=p_org AND branch_id=p_branch;
 IF l.id IS NULL THEN RAISE EXCEPTION 'Lot unavailable' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||l.product_id,0));
 SELECT coalesce(sum(delta_units),0)::integer INTO expected FROM pos_stock_movements WHERE lot_id=p_lot;
 INSERT INTO store_stock_counts(organization_id,branch_id,lot_id,expected_units,observed_units,reason,command_id,request_hash,counted_by,correlation_id)
 VALUES(p_org,p_branch,p_lot,expected,p_observed,btrim(p_reason),p_command,p_hash,p_actor,p_correlation) RETURNING id INTO count_id;
 RETURN count_id;
END $$;

CREATE FUNCTION approve_store_count(p_org uuid,p_branch uuid,p_actor uuid,p_count uuid,p_command uuid,p_hash text,p_correlation uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE c store_stock_counts%ROWTYPE; old store_count_approvals%ROWTYPE; l pos_stock_lots%ROWTYPE; balance integer; diff integer;
BEGIN
 IF p_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid command' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('store-count-approve:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM store_count_approvals WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.approved_by<>p_actor OR old.count_id<>p_count THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.count_id;
 END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO c FROM store_stock_counts WHERE id=p_count AND organization_id=p_org AND branch_id=p_branch FOR UPDATE;
 IF c.id IS NULL OR c.counted_by=p_actor OR EXISTS(SELECT 1 FROM store_count_approvals WHERE count_id=p_count)
  THEN RAISE EXCEPTION 'Count unavailable or approval must be independent' USING ERRCODE='23514'; END IF;
 SELECT * INTO l FROM pos_stock_lots WHERE id=c.lot_id;
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||l.product_id,0));
 SELECT coalesce(sum(delta_units),0)::integer INTO balance FROM pos_stock_movements WHERE lot_id=c.lot_id;
 IF balance<>c.expected_units THEN RAISE EXCEPTION 'Count became stale; recount required' USING ERRCODE='23514'; END IF;
 diff:=c.observed_units-balance;
 INSERT INTO store_count_approvals(count_id,organization_id,branch_id,delta_units,command_id,request_hash,approved_by,correlation_id)
 VALUES(c.id,p_org,p_branch,diff,p_command,p_hash,p_actor,p_correlation);
 IF diff<>0 THEN
  INSERT INTO pos_stock_movements(organization_id,branch_id,lot_id,kind,delta_units,count_id)
  VALUES(p_org,p_branch,c.lot_id,'count_adjustment',diff,c.id);
 END IF;
 RETURN c.id;
END $$;

DO $$ DECLARE tab text; fn regprocedure; BEGIN
 FOREACH tab IN ARRAY ARRAY['store_stock_counts','store_count_approvals'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('REVOKE ALL ON %I FROM PUBLIC,anon,authenticated,service_role',tab);
  EXECUTE format('GRANT SELECT ON %I TO dlc_api_runtime',tab);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',tab);
  EXECUTE format('CREATE TRIGGER store_count_immutable BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',tab);
 END LOOP;
 FOR fn IN SELECT oid::regprocedure FROM pg_proc WHERE proname IN('capture_store_count','approve_store_count') AND pronamespace='public'::regnamespace LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',fn);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO dlc_api_runtime',fn);
 END LOOP;
END $$;
INSERT INTO permissions(code,description) VALUES('pos.stock.count','Registrar conteo físico de tienda'),
 ('pos.stock.adjust.approve','Aprobar diferencias de inventario de tienda') ON CONFLICT(code) DO NOTHING;
