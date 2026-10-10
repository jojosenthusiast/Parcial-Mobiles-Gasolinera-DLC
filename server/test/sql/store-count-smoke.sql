DO $tests$
DECLARE o uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();u uuid:=gen_random_uuid();
 cat uuid:=gen_random_uuid();pa uuid:=gen_random_uuid();pb uuid:=gen_random_uuid();lot uuid:=gen_random_uuid();
 tx uuid; rx uuid; count_id uuid; approver uuid:=gen_random_uuid(); cmd uuid:=gen_random_uuid(); local_day date;
BEGIN
 BEGIN
 INSERT INTO organizations(id,name) VALUES(o,'Transient transfer');
 INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES
  (a,o,'TRA','Transfer origin','central','active'),(b,o,'TRB','Transfer destination','central','active');
 INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status)
 VALUES(u,o,u::text||'@example.invalid','Transfer operator','NO_LOGIN','active');
 INSERT INTO store_catalog_products(id,organization_id,sku,kind,category,presentation,unit,created_by)
 VALUES(cat,o,'FILTER','part','Repuestos','Filtro unidad','unit',u);
 INSERT INTO pos_products(id,organization_id,branch_id,sku,kind,expiry_required,created_by)
 VALUES(pa,o,a,'FILTER','store',false,u),(pb,o,b,'FILTER','store',false,u);
 INSERT INTO branch_assortments(organization_id,branch_id,catalog_product_id,pos_product_id,created_by)
 VALUES(o,a,cat,pa,u),(o,b,cat,pb,u);
 INSERT INTO pos_offer_versions(organization_id,branch_id,product_id,version,description,active,price_usd,command_id,request_hash,created_by,correlation_id)
 VALUES(o,a,pa,1,'Filtro',true,5,gen_random_uuid(),repeat('a',64),u,gen_random_uuid()),
 (o,b,pb,1,'Filtro',true,6,gen_random_uuid(),repeat('b',64),u,gen_random_uuid());
 INSERT INTO pos_stock_lots(id,organization_id,branch_id,product_id,lot_code,quantity_received,unit_cost_usd,source_reference,command_id,request_hash,received_by,correlation_id)
 VALUES(lot,o,a,pa,'L1',10,2,'INVOICE-1',gen_random_uuid(),repeat('c',64),u,gen_random_uuid());
 INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status) VALUES(approver,o,approver::text||'@example.invalid','Approver','NO_LOGIN','active');
 SET LOCAL ROLE dlc_api_runtime;
 tx:=dispatch_store_transfer(o,a,b,u,lot,pb,7,'WAYBILL-1',cmd,repeat('d',64),gen_random_uuid());
 IF tx<>dispatch_store_transfer(o,a,b,u,lot,pb,7,'WAYBILL-1',cmd,repeat('d',64),gen_random_uuid())
 OR (SELECT sum(delta_units) FROM pos_stock_movements WHERE lot_id=lot)<>3
 OR (SELECT quantity_in_transit FROM store_transfer_status WHERE id=tx)<>7 THEN RAISE EXCEPTION 'Transfer dispatch/replay failed'; END IF;
 BEGIN
  PERFORM dispatch_store_transfer(o,a,b,u,lot,pb,4,'WAYBILL-2',gen_random_uuid(),repeat('e',64),gen_random_uuid());
  RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
 EXCEPTION WHEN check_violation THEN NULL; END;
 rx:=receive_store_transfer(o,b,u,tx,3,'RECEIPT-1',gen_random_uuid(),repeat('f',64),gen_random_uuid());
 IF (SELECT quantity_received FROM store_transfer_status WHERE id=tx)<>3
 OR (SELECT quantity_in_transit FROM store_transfer_status WHERE id=tx)<>4
 OR (SELECT sum(delta_units) FROM pos_stock_movements m JOIN pos_stock_lots l ON l.id=m.lot_id WHERE l.branch_id=b)<>3
 OR (SELECT condition FROM pos_stock_lots WHERE id=(SELECT destination_lot_id FROM store_transfer_receipts WHERE id=rx))<>'sellable'
 THEN RAISE EXCEPTION 'Partial receipt failed'; END IF;
 PERFORM close_store_transfer(o,b,u,tx,'Faltan cuatro unidades, iniciar investigación',gen_random_uuid(),repeat('1',64),gen_random_uuid());
 IF (SELECT quantity_missing FROM store_transfer_status WHERE id=tx)<>4 OR (SELECT status FROM store_transfer_status WHERE id=tx)<>'closed_difference'
 THEN RAISE EXCEPTION 'Difference not recorded'; END IF;
 BEGIN
  PERFORM receive_store_transfer(o,b,u,tx,1,'RECEIPT-2',gen_random_uuid(),repeat('2',64),gen_random_uuid());
  RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  INSERT INTO store_transfers(organization_id,source_branch_id,destination_branch_id,source_lot_id,destination_product_id,quantity_sent,source_document,command_id,request_hash,created_by,correlation_id)
  VALUES(o,a,b,lot,pb,1,'FORGED',gen_random_uuid(),repeat('3',64),u,gen_random_uuid());
  RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 count_id:=capture_store_count(o,a,u,lot,2,'Conteo físico detectó una unidad rota',gen_random_uuid(),repeat('5',64),gen_random_uuid());
 IF (SELECT expected_units FROM store_stock_counts WHERE id=count_id)<>3 THEN RAISE EXCEPTION 'Snapshot wrong'; END IF;
 BEGIN
  PERFORM approve_store_count(o,a,u,count_id,gen_random_uuid(),repeat('6',64),gen_random_uuid());
  RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
 EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM approve_store_count(o,a,approver,count_id,gen_random_uuid(),repeat('7',64),gen_random_uuid());
 IF (SELECT sum(delta_units) FROM pos_stock_movements WHERE lot_id=lot)<>2 THEN RAISE EXCEPTION 'Adjustment not applied'; END IF;
 PERFORM classify_store_stock_loss(o,a,approver,count_id,'damage','Unidad dañada confirmada durante conteo',gen_random_uuid(),repeat('7',64),gen_random_uuid());
 IF (SELECT sum(cost_usd) FROM store_stock_loss_classifications WHERE organization_id=o)<>2 THEN RAISE EXCEPTION 'Loss cost wrong'; END IF;
 count_id:=capture_store_count(o,a,u,lot,1,'Nuevo conteo pendiente de confirmación',gen_random_uuid(),repeat('8',64),gen_random_uuid());
 PERFORM dispatch_store_transfer(o,a,b,u,lot,pb,1,'WAYBILL-LATE',gen_random_uuid(),repeat('9',64),gen_random_uuid());
 BEGIN
  PERFORM approve_store_count(o,a,approver,count_id,gen_random_uuid(),repeat('a',64),gen_random_uuid());
  RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF (SELECT count(*) FROM store_count_approvals WHERE organization_id=o)<>1 THEN RAISE EXCEPTION 'Stale count approved'; END IF;
 RAISE EXCEPTION 'rollback fixtures' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
 END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=o) THEN RAISE EXCEPTION 'Fixture rollback failed'; END IF;
 RAISE NOTICE 'PASS transfer dispatch, retry, insufficient stock, partial receipt, difference, sealed closure, permissions and rollback';
END $tests$;
