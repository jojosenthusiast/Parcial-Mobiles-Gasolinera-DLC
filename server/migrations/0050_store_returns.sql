-- Return against an exact sold allocation, with physical disposition separate from payment refund.
CREATE TABLE store_returns (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 sale_line_id uuid NOT NULL,source_lot_id uuid NOT NULL,return_lot_id uuid NOT NULL UNIQUE,
 quantity_units integer NOT NULL CHECK(quantity_units>0),disposition text NOT NULL CHECK(disposition IN('sellable','quarantine')),
 amount_eligible_usd numeric(18,2) NOT NULL CHECK(amount_eligible_usd>=0),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 accepted_by uuid NOT NULL,accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(sale_line_id) REFERENCES sale_lines(id),
 FOREIGN KEY(source_lot_id,organization_id,branch_id) REFERENCES pos_stock_lots(id,organization_id,branch_id),
 FOREIGN KEY(return_lot_id) REFERENCES pos_stock_lots(id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(accepted_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id),UNIQUE(id,organization_id,branch_id)
);
CREATE INDEX store_returns_allocation_idx ON store_returns(sale_line_id,source_lot_id);
CREATE OR REPLACE FUNCTION validate_pos_lot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE p pos_products%ROWTYPE; o pos_offer_versions%ROWTYPE; local_date date; r store_returns%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('pos-product:'||NEW.product_id,0));
 SELECT * INTO p FROM pos_products WHERE id=NEW.product_id;
 SELECT * INTO o FROM pos_offer_versions WHERE product_id=p.id ORDER BY version DESC LIMIT 1;
 SELECT (clock_timestamp() AT TIME ZONE timezone)::date INTO local_date FROM branches WHERE id=NEW.branch_id;
 SELECT * INTO r FROM store_returns WHERE return_lot_id=NEW.id AND NEW.source_reference='RETURN/'||id;
 IF r.id IS NOT NULL THEN
  IF p.kind IS DISTINCT FROM 'store' OR r.organization_id<>NEW.organization_id OR r.branch_id<>NEW.branch_id
   OR r.quantity_units<>NEW.quantity_received OR r.command_id<>NEW.command_id
   OR r.request_hash<>NEW.request_hash OR r.accepted_by<>NEW.received_by
   OR (SELECT pos_product_id FROM sale_lines WHERE id=r.sale_line_id)<>NEW.product_id
  THEN RAISE EXCEPTION 'Return lot mismatch' USING ERRCODE='23514'; END IF;
 ELSE
  IF p.kind IS DISTINCT FROM 'store' OR o.active IS DISTINCT FROM true
   OR NOT EXISTS(SELECT 1 FROM branch_assortments a JOIN store_catalog_products cp ON cp.id=a.catalog_product_id
     WHERE a.pos_product_id=p.id AND a.active AND cp.active)
   OR (p.expiry_required AND NEW.expires_on IS NULL) OR NEW.expires_on<local_date
  THEN RAISE EXCEPTION 'Invalid, disabled, undated or expired stock lot' USING ERRCODE='23514'; END IF;
 END IF;
 NEW.received_at:=clock_timestamp(); RETURN NEW;
END $$;

CREATE FUNCTION accept_store_return(p_org uuid,p_branch uuid,p_actor uuid,p_sale_line uuid,p_source_lot uuid,
 p_quantity integer,p_disposition text,p_reason text,p_command uuid,p_hash text,p_correlation uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old store_returns%ROWTYPE; l sale_lines%ROWTYPE; src pos_stock_lots%ROWTYPE; sold integer; returned integer;
 result uuid; new_lot uuid:=gen_random_uuid(); local_date date; amount numeric(18,2); already_eligible numeric(18,2);
BEGIN
 IF p_quantity IS NULL OR p_quantity<=0 OR p_disposition NOT IN('sellable','quarantine')
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500 OR p_hash !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Invalid store return' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('store-return:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM store_returns WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.accepted_by<>p_actor THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.id;
 END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO l FROM sale_lines WHERE id=p_sale_line AND organization_id=p_org AND branch_id=p_branch AND kind='store';
 SELECT * INTO src FROM pos_stock_lots WHERE id=p_source_lot AND organization_id=p_org AND branch_id=p_branch;
 IF l.id IS NULL OR src.id IS NULL OR src.product_id<>l.pos_product_id
 THEN RAISE EXCEPTION 'Sale allocation unavailable' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('store-return-allocation:'||p_sale_line||':'||p_source_lot,0));
 SELECT -coalesce(sum(delta_units),0)::integer INTO sold FROM pos_stock_movements
 WHERE sale_line_id=p_sale_line AND lot_id=p_source_lot AND kind='sale';
 SELECT coalesce(sum(quantity_units),0)::integer INTO returned FROM store_returns
 WHERE sale_line_id=p_sale_line AND source_lot_id=p_source_lot;
 IF p_quantity>sold-returned THEN RAISE EXCEPTION 'Return exceeds sold allocation' USING ERRCODE='23514'; END IF;
 SELECT (clock_timestamp() AT TIME ZONE timezone)::date INTO local_date FROM branches WHERE id=p_branch;
 IF p_disposition='sellable' AND (src.condition<>'sellable' OR (src.expires_on IS NOT NULL AND src.expires_on<local_date)
  OR NOT EXISTS(SELECT 1 FROM branch_assortments a JOIN store_catalog_products cp ON cp.id=a.catalog_product_id
    WHERE a.pos_product_id=src.product_id AND a.active AND cp.active)
  OR (SELECT active FROM pos_offer_versions WHERE product_id=src.product_id ORDER BY version DESC LIMIT 1) IS DISTINCT FROM true)
 THEN RAISE EXCEPTION 'Return cannot reenter sellable stock' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(amount_eligible_usd),0) INTO already_eligible FROM store_returns WHERE sale_line_id=p_sale_line;
 amount:=least(round(l.total_usd*p_quantity/l.quantity_units,2),greatest(0,l.total_usd-already_eligible));
 INSERT INTO store_returns(organization_id,branch_id,sale_line_id,source_lot_id,return_lot_id,quantity_units,
  disposition,amount_eligible_usd,reason,command_id,request_hash,accepted_by,correlation_id)
 VALUES(p_org,p_branch,p_sale_line,p_source_lot,new_lot,p_quantity,p_disposition,amount,btrim(p_reason),p_command,p_hash,p_actor,p_correlation)
 RETURNING id INTO result;
 INSERT INTO pos_stock_lots(id,organization_id,branch_id,product_id,lot_code,expires_on,quantity_received,unit_cost_usd,
  source_reference,command_id,request_hash,received_by,correlation_id)
 VALUES(new_lot,p_org,p_branch,src.product_id,substr(src.lot_code,1,40)||'-RETURN-'||left(result::text,8),
  src.expires_on,p_quantity,src.unit_cost_usd,'RETURN/'||result,p_command,p_hash,p_actor,p_correlation);
 IF p_disposition='quarantine' THEN
  PERFORM set_config('dlc.pos_condition_transition','yes',true);
  UPDATE pos_stock_lots SET condition='quarantine' WHERE id=new_lot;
  PERFORM set_config('dlc.pos_condition_transition','',true);
 END IF;
 RETURN result;
END $$;
ALTER TABLE store_returns ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON store_returns FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON store_returns TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON store_returns FOR SELECT TO dlc_api_runtime USING(true);
CREATE TRIGGER store_return_immutable BEFORE UPDATE OR DELETE ON store_returns FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION accept_store_return(uuid,uuid,uuid,uuid,uuid,integer,text,text,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION accept_store_return(uuid,uuid,uuid,uuid,uuid,integer,text,text,uuid,text,uuid) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES('pos.stock.return','Aceptar devolución física de tienda') ON CONFLICT(code) DO NOTHING;
