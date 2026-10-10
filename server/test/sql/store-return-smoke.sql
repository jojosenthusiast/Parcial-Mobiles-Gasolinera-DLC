DO $tests$
DECLARE org uuid:=gen_random_uuid(); org2 uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); branch2 uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid();
 product uuid:=gen_random_uuid(); unknown_product uuid:=gen_random_uuid(); service uuid:=gen_random_uuid();
 offer uuid:=gen_random_uuid(); unknown_offer uuid:=gen_random_uuid(); service_offer uuid:=gen_random_uuid();
 early_lot uuid:=gen_random_uuid(); late_lot uuid:=gen_random_uuid(); unknown_lot uuid:=gen_random_uuid();
 ticket_id uuid; command uuid:=gen_random_uuid(); line_id uuid; local_date date; items jsonb; n bigint; results jsonb:='[]';
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(org,'POS transient'),(org2,'Other transient');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(branch,org,'TESTPOS','Test POS','occidental','active'),(branch2,org2,'OTHER','Other','central','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status) VALUES(actor,org,actor::text||'@example.invalid','Test actor','NOT_A_LOGIN_HASH','active');
  SELECT (clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date INTO local_date;
  INSERT INTO pos_products(id,organization_id,branch_id,sku,kind,expiry_required,created_by) VALUES
   (product,org,branch,'DRINK','store',true,actor),(unknown_product,org,branch,'OIL','store',false,actor),(service,org,branch,'WASH','service',false,actor);
  INSERT INTO pos_offer_versions(id,organization_id,branch_id,product_id,version,description,active,price_usd,service_unit_cost_usd,command_id,request_hash,created_by,correlation_id) VALUES
   (offer,org,branch,product,1,'Drink',true,2.50,NULL,gen_random_uuid(),repeat('a',64),actor,gen_random_uuid()),
   (unknown_offer,org,branch,unknown_product,1,'Oil',true,5,NULL,gen_random_uuid(),repeat('b',64),actor,gen_random_uuid()),
   (service_offer,org,branch,service,1,'Wash',true,7,3,gen_random_uuid(),repeat('c',64),actor,gen_random_uuid());
  INSERT INTO store_catalog_products(organization_id,sku,kind,category,presentation,unit,created_by)
   VALUES(org,'DRINK','store','Bebidas','Botella','unit',actor),(org,'OIL','lubricant','Lubricantes','Envase','bottle',actor);
  INSERT INTO branch_assortments(organization_id,branch_id,catalog_product_id,pos_product_id,created_by)
   SELECT org,branch,c.id,CASE WHEN c.sku='DRINK' THEN product ELSE unknown_product END,actor
   FROM store_catalog_products c WHERE c.organization_id=org;
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO pos_stock_lots(id,organization_id,branch_id,product_id,lot_code,expires_on,quantity_received,unit_cost_usd,source_reference,command_id,request_hash,received_by,correlation_id) VALUES
   (late_lot,org,branch,product,'LATER',local_date+3,5,2,'DOC2',gen_random_uuid(),repeat('d',64),actor,gen_random_uuid()),
   (early_lot,org,branch,product,'EARLY',local_date+1,2,1,'DOC1',gen_random_uuid(),repeat('e',64),actor,gen_random_uuid()),
   (unknown_lot,org,branch,unknown_product,'UNKNOWN',NULL,3,NULL,'DOC3',gen_random_uuid(),repeat('f',64),actor,gen_random_uuid());
  IF (SELECT count(*) FROM pos_stock_movements WHERE organization_id=org AND kind='receipt')<>3 THEN RAISE EXCEPTION 'Receipt ledger missing'; END IF;
  results:=results||jsonb_build_object('test','runtime_receipts_create_one_movement_each','result','PASS');
  items:=jsonb_build_array(jsonb_build_object('productId',product,'offerVersionId',offer,'quantity','3'),jsonb_build_object('productId',service,'offerVersionId',service_offer,'quantity','1'));
  ticket_id:=post_pos_sale(org,branch,actor,command,repeat('1',64),items,gen_random_uuid());
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT id INTO line_id FROM sale_lines WHERE sale_id=ticket_id AND kind='store';
  PERFORM accept_store_return(org,branch,actor,line_id,early_lot,1,'quarantine','El empaque regresó dañado',gen_random_uuid(),repeat('a',64),gen_random_uuid());
  IF NOT EXISTS(SELECT 1 FROM store_returns r JOIN pos_stock_lots l ON l.id=r.return_lot_id
    WHERE r.sale_line_id=line_id AND l.condition='quarantine' AND l.quantity_received=1) THEN RAISE EXCEPTION 'Quarantine return missing'; END IF;
  PERFORM accept_store_return(org,branch,actor,line_id,early_lot,1,'sellable','Envase intacto y verificado',gen_random_uuid(),repeat('b',64),gen_random_uuid());
  IF (SELECT count(*) FROM store_returns WHERE sale_line_id=line_id)<>2 THEN RAISE EXCEPTION 'Second return missing'; END IF;
  BEGIN
   PERFORM accept_store_return(org,branch,actor,line_id,early_lot,1,'sellable','Duplicado indebido de retorno',gen_random_uuid(),repeat('c',64),gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE EXCEPTION 'rollback fixtures' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
 END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org OR id=org2) THEN RAISE EXCEPTION 'Fixture rollback failed'; END IF;
 RAISE NOTICE 'PASS return allocation, quarantine, sellable and duplicate rejection';
END $tests$;
