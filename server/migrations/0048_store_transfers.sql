-- A transfer sends units out of the source ledger, then receives confirmed units into new destination lots.
CREATE TABLE store_transfers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,source_branch_id uuid NOT NULL,destination_branch_id uuid NOT NULL,
 source_lot_id uuid NOT NULL,destination_product_id uuid NOT NULL,quantity_sent integer NOT NULL CHECK(quantity_sent>0),
 source_document text NOT NULL CHECK(length(btrim(source_document)) BETWEEN 3 AND 160),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(source_lot_id,organization_id,source_branch_id) REFERENCES pos_stock_lots(id,organization_id,branch_id),
 FOREIGN KEY(destination_product_id,organization_id,destination_branch_id) REFERENCES pos_products(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 FOREIGN KEY(source_branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(destination_branch_id,organization_id) REFERENCES branches(id,organization_id),
 CHECK(source_branch_id<>destination_branch_id),UNIQUE(organization_id,command_id),UNIQUE(id,organization_id)
);
CREATE TABLE store_transfer_receipts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,transfer_id uuid NOT NULL,destination_lot_id uuid NOT NULL,
 quantity_received integer NOT NULL CHECK(quantity_received>0),document text NOT NULL CHECK(length(btrim(document)) BETWEEN 3 AND 160),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 received_by uuid NOT NULL,received_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(transfer_id,organization_id) REFERENCES store_transfers(id,organization_id),
 FOREIGN KEY(destination_lot_id) REFERENCES pos_stock_lots(id),
 FOREIGN KEY(received_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id),UNIQUE(destination_lot_id)
);
CREATE TABLE store_transfer_closures (
 transfer_id uuid PRIMARY KEY,organization_id uuid NOT NULL,quantity_missing integer NOT NULL CHECK(quantity_missing>=0),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),command_id uuid NOT NULL,
 request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),closed_by uuid NOT NULL,
 closed_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(transfer_id,organization_id) REFERENCES store_transfers(id,organization_id),
 FOREIGN KEY(closed_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id)
);
ALTER TABLE pos_stock_movements ADD COLUMN transfer_id uuid,
 ADD CONSTRAINT stock_movement_transfer_fk FOREIGN KEY(transfer_id,organization_id) REFERENCES store_transfers(id,organization_id),
 DROP CONSTRAINT pos_stock_movements_kind_check,
 DROP CONSTRAINT pos_stock_movements_check,
 ADD CONSTRAINT pos_stock_movements_kind_check CHECK(kind IN('receipt','sale','transfer_out')),
 ADD CONSTRAINT pos_stock_movements_check CHECK(
 (kind='receipt' AND delta_units>0 AND sale_line_id IS NULL AND transfer_id IS NULL)
 OR (kind='sale' AND delta_units<0 AND sale_line_id IS NOT NULL AND transfer_id IS NULL)
 OR (kind='transfer_out' AND delta_units<0 AND sale_line_id IS NULL AND transfer_id IS NOT NULL));
CREATE UNIQUE INDEX pos_stock_transfer_out_once ON pos_stock_movements(transfer_id) WHERE kind='transfer_out';
CREATE INDEX store_transfers_destination_idx ON store_transfers(destination_branch_id,created_at DESC);
CREATE INDEX store_transfer_receipts_transfer_idx ON store_transfer_receipts(transfer_id);

CREATE OR REPLACE FUNCTION validate_pos_stock_movement() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE l pos_stock_lots%ROWTYPE; s sale_lines%ROWTYPE; t store_transfers%ROWTYPE; balance numeric; local_date date;
BEGIN
 SELECT * INTO l FROM pos_stock_lots WHERE id=NEW.lot_id;
 IF l.id IS NULL OR NEW.organization_id<>l.organization_id OR NEW.branch_id<>l.branch_id THEN
  RAISE EXCEPTION 'Stock scope mismatch' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||l.product_id,0));
 IF NEW.kind='receipt' THEN
  IF NEW.delta_units<>l.quantity_received THEN RAISE EXCEPTION 'Receipt differs from lot' USING ERRCODE='23514'; END IF;
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
CREATE OR REPLACE FUNCTION check_pos_allocation_total() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE l sale_lines%ROWTYPE; allocated numeric; amount numeric; unknown_count integer;
BEGIN
 IF NEW.kind<>'sale' THEN RETURN NULL; END IF;
 SELECT * INTO l FROM sale_lines WHERE id=NEW.sale_line_id;
 SELECT -sum(m.delta_units),sum(-m.delta_units*b.unit_cost_usd),count(*) FILTER(WHERE b.unit_cost_usd IS NULL)
 INTO allocated,amount,unknown_count FROM pos_stock_movements m JOIN pos_stock_lots b ON b.id=m.lot_id WHERE m.sale_line_id=l.id;
 IF allocated<>l.quantity_units OR l.cost_quality IS DISTINCT FROM (CASE WHEN unknown_count>0 THEN 'unknown' ELSE 'known' END)
  OR l.cost_usd IS DISTINCT FROM (CASE WHEN unknown_count>0 THEN NULL ELSE amount END) THEN
  RAISE EXCEPTION 'Store allocation quantity or cost mismatch' USING ERRCODE='23514'; END IF;
 RETURN NULL;
END $$;

CREATE FUNCTION dispatch_store_transfer(p_org uuid,p_source uuid,p_destination uuid,p_actor uuid,
 p_lot uuid,p_destination_product uuid,p_quantity integer,p_document text,p_command uuid,p_hash text,p_correlation uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE src pos_stock_lots%ROWTYPE; old store_transfers%ROWTYPE; result uuid; dst pos_products%ROWTYPE;
BEGIN
 IF p_quantity IS NULL OR p_quantity<=0 OR p_source=p_destination OR p_document IS NULL
  OR length(btrim(p_document)) NOT BETWEEN 3 AND 160 OR p_hash !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Invalid transfer request' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('store-transfer:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM store_transfers WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.created_by<>p_actor THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.id;
 END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO src FROM pos_stock_lots WHERE id=p_lot AND organization_id=p_org AND branch_id=p_source;
 SELECT * INTO dst FROM pos_products WHERE id=p_destination_product AND organization_id=p_org AND branch_id=p_destination;
 IF src.id IS NULL OR dst.id IS NULL OR dst.kind<>'store' OR src.condition<>'sellable'
  OR NOT EXISTS(SELECT 1 FROM branch_assortments a JOIN branch_assortments b ON a.catalog_product_id=b.catalog_product_id
    JOIN store_catalog_products c ON c.id=a.catalog_product_id
    WHERE a.pos_product_id=src.product_id AND b.pos_product_id=dst.id AND a.active AND b.active AND c.active)
 THEN RAISE EXCEPTION 'Source and destination assortment mismatch' USING ERRCODE='23514'; END IF;
 INSERT INTO store_transfers(organization_id,source_branch_id,destination_branch_id,source_lot_id,destination_product_id,
  quantity_sent,source_document,command_id,request_hash,created_by,correlation_id)
 VALUES(p_org,p_source,p_destination,p_lot,p_destination_product,p_quantity,btrim(p_document),p_command,p_hash,p_actor,p_correlation) RETURNING id INTO result;
 INSERT INTO pos_stock_movements(organization_id,branch_id,lot_id,delta_units,kind,transfer_id)
 VALUES(p_org,p_source,p_lot,-p_quantity,'transfer_out',result);
 RETURN result;
END $$;

CREATE FUNCTION receive_store_transfer(p_org uuid,p_destination uuid,p_actor uuid,p_transfer uuid,
 p_quantity integer,p_document text,p_command uuid,p_hash text,p_correlation uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t store_transfers%ROWTYPE; src pos_stock_lots%ROWTYPE; old store_transfer_receipts%ROWTYPE;
 received integer; lot uuid; receipt uuid;
BEGIN
 IF p_quantity IS NULL OR p_quantity<=0 OR p_document IS NULL OR length(btrim(p_document)) NOT BETWEEN 3 AND 160
  OR p_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid receipt' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('store-transfer-receipt:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM store_transfer_receipts WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.received_by<>p_actor OR old.transfer_id<>p_transfer THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.id;
 END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO t FROM store_transfers WHERE id=p_transfer AND organization_id=p_org AND destination_branch_id=p_destination FOR UPDATE;
 IF t.id IS NULL OR EXISTS(SELECT 1 FROM store_transfer_closures WHERE transfer_id=t.id) THEN RAISE EXCEPTION 'Transfer closed or unavailable' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(quantity_received),0) INTO received FROM store_transfer_receipts WHERE transfer_id=t.id;
 IF p_quantity>t.quantity_sent-received THEN RAISE EXCEPTION 'Receipt exceeds transit stock' USING ERRCODE='23514'; END IF;
 SELECT * INTO src FROM pos_stock_lots WHERE id=t.source_lot_id;
 INSERT INTO pos_stock_lots(organization_id,branch_id,product_id,lot_code,expires_on,quantity_received,
  unit_cost_usd,source_reference,command_id,request_hash,received_by,correlation_id)
 VALUES(p_org,p_destination,t.destination_product_id,src.lot_code,src.expires_on,p_quantity,src.unit_cost_usd,
  'TRANSFER/'||t.id||'/'||p_command,p_command,p_hash,p_actor,p_correlation) RETURNING id INTO lot;
 INSERT INTO store_transfer_receipts(organization_id,transfer_id,destination_lot_id,quantity_received,document,command_id,request_hash,received_by,correlation_id)
 VALUES(p_org,t.id,lot,p_quantity,btrim(p_document),p_command,p_hash,p_actor,p_correlation) RETURNING id INTO receipt;
 RETURN receipt;
END $$;

CREATE FUNCTION close_store_transfer(p_org uuid,p_destination uuid,p_actor uuid,p_transfer uuid,
 p_reason text,p_command uuid,p_hash text,p_correlation uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t store_transfers%ROWTYPE; old store_transfer_closures%ROWTYPE; received integer;
BEGIN
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500 OR p_hash !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Closure requires a reason' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('store-transfer-close:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM store_transfer_closures WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.closed_by<>p_actor OR old.transfer_id<>p_transfer THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.transfer_id;
 END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO t FROM store_transfers WHERE id=p_transfer AND organization_id=p_org AND destination_branch_id=p_destination FOR UPDATE;
 IF t.id IS NULL OR EXISTS(SELECT 1 FROM store_transfer_closures WHERE transfer_id=t.id) THEN RAISE EXCEPTION 'Transfer closed or unavailable' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(quantity_received),0) INTO received FROM store_transfer_receipts WHERE transfer_id=t.id;
 INSERT INTO store_transfer_closures(organization_id,transfer_id,quantity_missing,reason,command_id,request_hash,closed_by,correlation_id)
 VALUES(p_org,t.id,t.quantity_sent-received,btrim(p_reason),p_command,p_hash,p_actor,p_correlation);
 RETURN t.id;
END $$;

CREATE VIEW store_transfer_status WITH (security_invoker=true) AS
 SELECT t.*,coalesce(r.received,0) AS quantity_received,t.quantity_sent-coalesce(r.received,0) AS quantity_in_transit,
  c.quantity_missing,c.reason AS closure_reason,c.closed_at,
  CASE WHEN c.transfer_id IS NOT NULL AND c.quantity_missing>0 THEN 'closed_difference'
   WHEN c.transfer_id IS NOT NULL THEN 'closed' WHEN coalesce(r.received,0)>0 THEN 'partial' ELSE 'in_transit' END AS status
 FROM store_transfers t LEFT JOIN (SELECT transfer_id,sum(quantity_received)::integer AS received FROM store_transfer_receipts GROUP BY transfer_id) r ON r.transfer_id=t.id
 LEFT JOIN store_transfer_closures c ON c.transfer_id=t.id;
DO $$ DECLARE tab text; fn regprocedure; BEGIN
 FOREACH tab IN ARRAY ARRAY['store_transfers','store_transfer_receipts','store_transfer_closures'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('REVOKE ALL ON %I FROM PUBLIC,anon,authenticated,service_role',tab);
  EXECUTE format('GRANT SELECT ON %I TO dlc_api_runtime',tab);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',tab);
  EXECUTE format('CREATE TRIGGER store_transfer_immutable BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',tab);
 END LOOP;
 FOR fn IN SELECT oid::regprocedure FROM pg_proc WHERE proname IN('dispatch_store_transfer','receive_store_transfer','close_store_transfer') AND pronamespace='public'::regnamespace LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',fn);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO dlc_api_runtime',fn);
 END LOOP;
END $$;
REVOKE ALL ON store_transfer_status FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON store_transfer_status TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES
 ('pos.stock.transfer.send','Enviar productos a otra sucursal'),
 ('pos.stock.transfer.receive','Recibir productos transferidos'),
 ('pos.stock.transfer.close','Cerrar tránsito y documentar diferencias') ON CONFLICT(code) DO NOTHING;
