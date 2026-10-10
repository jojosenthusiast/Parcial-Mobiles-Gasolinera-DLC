DO $test$
DECLARE o uuid:=gen_random_uuid();b uuid:=gen_random_uuid();u uuid:=gen_random_uuid();
 material uuid:=gen_random_uuid();svc uuid:=gen_random_uuid();offer uuid:=gen_random_uuid();cat uuid:=gen_random_uuid();
 lot uuid:=gen_random_uuid();sale uuid;line uuid;command uuid:=gen_random_uuid();fulfillment uuid;other_sale uuid;other_line uuid;
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(o,'Transient service');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(b,o,'SV01','Service branch','central','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status) VALUES(u,o,u::text||'@example.invalid','Service worker','NO_LOGIN','active');
  INSERT INTO pos_products(id,organization_id,branch_id,sku,kind,created_by)
   VALUES(material,o,b,'SOAP','store',u),(svc,o,b,'WASH','service',u);
  INSERT INTO pos_offer_versions(id,organization_id,branch_id,product_id,version,description,active,price_usd,service_unit_cost_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(offer,o,b,svc,1,'Lavado de automóvil',true,7,3,gen_random_uuid(),repeat('a',64),u,gen_random_uuid()),
   (gen_random_uuid(),o,b,material,1,'Jabón',true,2,NULL,gen_random_uuid(),repeat('b',64),u,gen_random_uuid());
  INSERT INTO store_catalog_products(id,organization_id,sku,kind,category,presentation,unit,created_by)
   VALUES(cat,o,'SOAP','store','Limpieza','Unidad','unit',u);
  INSERT INTO branch_assortments(organization_id,branch_id,catalog_product_id,pos_product_id,created_by)
   VALUES(o,b,cat,material,u);
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO service_catalog_details(product_id,organization_id,branch_id,work_description,created_by)
   VALUES(svc,o,b,'Lavado manual completo',u);
  INSERT INTO service_material_requirements(organization_id,branch_id,offer_version_id,catalog_product_id,units_per_service,created_by)
   VALUES(o,b,offer,cat,2,u);
  INSERT INTO pos_stock_lots(id,organization_id,branch_id,product_id,lot_code,quantity_received,unit_cost_usd,
   source_reference,command_id,request_hash,received_by,correlation_id)
   VALUES(lot,o,b,material,'S1',3,1.25,'DOC-S1',gen_random_uuid(),repeat('c',64),u,gen_random_uuid());
  sale:=post_pos_sale(o,b,u,gen_random_uuid(),repeat('d',64),
   jsonb_build_array(jsonb_build_object('productId',svc,'offerVersionId',offer,'quantity','1')),gen_random_uuid());
  SET CONSTRAINTS ALL IMMEDIATE;SET CONSTRAINTS ALL DEFERRED;
  SELECT id INTO line FROM sale_lines WHERE sale_id=sale;
  fulfillment:=fulfill_pos_service(o,b,u,line,'Lavado completado',command,repeat('e',64),gen_random_uuid());
  IF (SELECT sum(delta_units) FROM pos_stock_movements WHERE lot_id=lot)<>1
   OR (SELECT count(*) FROM service_fulfillments WHERE id=fulfillment)<>1
  THEN RAISE EXCEPTION 'Service stock not consumed'; END IF;
  IF fulfill_pos_service(o,b,u,line,'Lavado completado',command,repeat('e',64),gen_random_uuid())<>fulfillment
   OR (SELECT count(*) FROM pos_stock_movements WHERE lot_id=lot AND kind='service_use')<>1
  THEN RAISE EXCEPTION 'Service replay consumed twice'; END IF;
  other_sale:=post_pos_sale(o,b,u,gen_random_uuid(),repeat('f',64),
   jsonb_build_array(jsonb_build_object('productId',svc,'offerVersionId',offer,'quantity','1')),gen_random_uuid());
  SET CONSTRAINTS ALL IMMEDIATE;SET CONSTRAINTS ALL DEFERRED;
  SELECT id INTO other_line FROM sale_lines WHERE sale_id=other_sale;
  BEGIN
   PERFORM fulfill_pos_service(o,b,u,other_line,'Segundo lavado',gen_random_uuid(),repeat('1',64),gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  IF EXISTS(SELECT 1 FROM service_fulfillments WHERE sale_line_id=other_line)
   OR (SELECT sum(delta_units) FROM pos_stock_movements WHERE lot_id=lot)<>1
  THEN RAISE EXCEPTION 'Failed service persisted'; END IF;
  BEGIN
   INSERT INTO service_material_requirements(organization_id,branch_id,offer_version_id,catalog_product_id,units_per_service,created_by)
   VALUES(o,b,offer,cat,1,u);
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE EXCEPTION 'ROLLBACK' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=o) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
 RAISE NOTICE 'PASS service resources, ledger, replay, shortage rollback, recipe lock';
END $test$;
