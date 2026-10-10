DO $test$
DECLARE o uuid:=gen_random_uuid();b uuid:=gen_random_uuid();seller uuid:=gen_random_uuid();reviewer uuid:=gen_random_uuid();
 material uuid:=gen_random_uuid();svc uuid:=gen_random_uuid();offer uuid:=gen_random_uuid();cat uuid:=gen_random_uuid();
 sale uuid;line uuid;expense uuid:=gen_random_uuid();category uuid:=gen_random_uuid();
 revenue numeric;cost numeric;materials numeric;expenses numeric;
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(o,'Transient operating report');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(b,o,'RP01','Report','central','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status) VALUES
   (seller,o,seller::text||'@example.invalid','Seller','NO_LOGIN','active'),
   (reviewer,o,reviewer::text||'@example.invalid','Reviewer','NO_LOGIN','active');
  INSERT INTO pos_products(id,organization_id,branch_id,sku,kind,created_by)
   VALUES(material,o,b,'SOAP','store',seller),(svc,o,b,'WASH','service',seller);
  INSERT INTO pos_offer_versions(id,organization_id,branch_id,product_id,version,description,active,price_usd,service_unit_cost_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(offer,o,b,svc,1,'Lavado',true,7,3,gen_random_uuid(),repeat('a',64),seller,gen_random_uuid()),
   (gen_random_uuid(),o,b,material,1,'Jabón',true,2,NULL,gen_random_uuid(),repeat('b',64),seller,gen_random_uuid());
  INSERT INTO store_catalog_products(id,organization_id,sku,kind,category,presentation,unit,created_by)
   VALUES(cat,o,'SOAP','store','Limpieza','Unidad','unit',seller);
  INSERT INTO branch_assortments(organization_id,branch_id,catalog_product_id,pos_product_id,created_by)
   VALUES(o,b,cat,material,seller);
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO service_catalog_details(product_id,organization_id,branch_id,work_description,created_by)
   VALUES(svc,o,b,'Lavado manual completo',seller);
  INSERT INTO service_material_requirements(organization_id,branch_id,offer_version_id,catalog_product_id,units_per_service,created_by)
   VALUES(o,b,offer,cat,2,seller);
  INSERT INTO pos_stock_lots(organization_id,branch_id,product_id,lot_code,quantity_received,unit_cost_usd,source_reference,command_id,request_hash,received_by,correlation_id)
   VALUES(o,b,material,'SOAP-1',3,1.25,'DOC-SOAP',gen_random_uuid(),repeat('c',64),seller,gen_random_uuid());
  sale:=post_pos_sale(o,b,seller,gen_random_uuid(),repeat('d',64),
   jsonb_build_array(jsonb_build_object('productId',svc,'offerVersionId',offer,'quantity','1')),gen_random_uuid());
  SET CONSTRAINTS ALL IMMEDIATE;SET CONSTRAINTS ALL DEFERRED;
  SELECT id INTO line FROM sale_lines WHERE sale_id=sale;
  PERFORM fulfill_pos_service(o,b,seller,line,'Trabajo terminado',gen_random_uuid(),repeat('e',64),gen_random_uuid());
  INSERT INTO expense_categories(id,organization_id,code,name,class,created_by)
   VALUES(category,o,'WATER','Agua y energía','operating',reviewer);
  INSERT INTO expense_claims(id,organization_id,branch_id,category_id,cost_center,invoice_reference,amount_usd,incurred_on,
   source_kind,description,evidence_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(expense,o,b,category,'Lavado','WATER-01',1,(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date,
    'other','Consumo de agua del servicio','WATER-01-DOC',gen_random_uuid(),repeat('f',64),seller,gen_random_uuid());
  INSERT INTO expense_decisions(expense_id,organization_id,branch_id,outcome,reason,command_id,request_hash,decided_by,correlation_id)
   VALUES(expense,o,b,'approved','Comprobante de agua revisado',gen_random_uuid(),repeat('1',64),reviewer,gen_random_uuid());
  SELECT sum(l.total_usd),sum(l.cost_usd) INTO revenue,cost FROM sale_lines l JOIN sales s ON s.id=l.sale_id WHERE s.organization_id=o;
  SELECT sum(-m.delta_units*l.unit_cost_usd) INTO materials FROM pos_stock_movements m
   JOIN pos_stock_lots l ON l.id=m.lot_id WHERE m.organization_id=o AND m.kind='service_use';
  SELECT sum(e.amount_usd) INTO expenses FROM expense_claims e JOIN expense_decisions d ON d.expense_id=e.id
   WHERE e.organization_id=o AND d.outcome='approved';
  IF revenue<>7 OR cost<>3 OR materials<>2.5 OR expenses<>1 OR revenue-cost-materials-expenses<>0.5
   THEN RAISE EXCEPTION 'Operating components did not reconcile'; END IF;
  RAISE EXCEPTION 'ROLLBACK' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=o) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
 RAISE NOTICE 'PASS revenue 7, service cost 3, material 2.50, approved expense 1, known result 0.50';
END $test$;
