DO $test$
DECLARE o uuid:=gen_random_uuid();b uuid:=gen_random_uuid();u uuid:=gen_random_uuid();
 vendor uuid:=gen_random_uuid();po uuid:=gen_random_uuid();category uuid:=gen_random_uuid();local_date date;
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(o,'Transient crosscheck');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(b,o,'IV01','Invoice check','central','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status)
   VALUES(u,o,u::text||'@example.invalid','Accountant','NO_LOGIN','active');
  INSERT INTO suppliers(id,organization_id,legal_name,created_by) VALUES(vendor,o,'Vendor',u);
  INSERT INTO purchase_orders(id,organization_id,branch_id,supplier_id,order_number,created_by)
   VALUES(po,o,b,vendor,'PO-01',u);
  INSERT INTO expense_categories(id,organization_id,code,name,class,created_by)
   VALUES(category,o,'UTIL','Servicios generales','operating',u);
  SELECT (clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date INTO local_date;
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO supplier_invoices(organization_id,purchase_order_id,supplier_id,invoice_number,subtotal_usd,total_usd,created_by)
   VALUES(o,po,vendor,'GOODS-01',10,10,u);
  BEGIN
   INSERT INTO expense_claims(organization_id,branch_id,category_id,cost_center,supplier_id,invoice_reference,amount_usd,incurred_on,
    source_kind,description,evidence_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(o,b,category,'Sucursal',vendor,'goods-01',10,local_date,'other','Factura de bienes duplicada',
    'DOC-01',gen_random_uuid(),repeat('a',64),u,gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO expense_claims(organization_id,branch_id,category_id,cost_center,supplier_id,invoice_reference,amount_usd,incurred_on,
    source_kind,description,evidence_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(o,b,category,'Sucursal',vendor,'FEE-01',2,local_date,'other','Servicio externo facturado',
    'DOC-02',gen_random_uuid(),repeat('b',64),u,gen_random_uuid());
  BEGIN
   INSERT INTO supplier_invoices(organization_id,purchase_order_id,supplier_id,invoice_number,subtotal_usd,total_usd,created_by)
    VALUES(o,po,vendor,'fee-01',2,2,u);
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE EXCEPTION 'ROLLBACK' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=o) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
 RAISE NOTICE 'PASS invoice crosscheck both booking orders';
END $test$;
