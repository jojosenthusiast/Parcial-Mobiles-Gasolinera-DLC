BEGIN;
DO $test$
DECLARE
 org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); reporter uuid:=gen_random_uuid(); checker uuid:=gen_random_uuid();
 gasoline uuid:=gen_random_uuid(); diesel uuid:=gen_random_uuid(); gas_tank uuid:=gen_random_uuid(); diesel_tank uuid:=gen_random_uuid();
 supplier uuid:=gen_random_uuid(); order_id uuid:=gen_random_uuid(); gas_line uuid:=gen_random_uuid(); diesel_line uuid:=gen_random_uuid();
 same_incident uuid:=gen_random_uuid(); mixed_incident uuid:=gen_random_uuid(); same_row uuid:=gen_random_uuid(); mixed_row uuid:=gen_random_uuid();
BEGIN
 BEGIN
 INSERT INTO organizations(id,name) VALUES(org,'Contamination transient');
 INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(branch,org,'CM01','Contamination QA','central','active');
 INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status) VALUES
  (reporter,org,reporter::text||'@example.invalid','Reporter','NO_LOGIN','active'),
  (checker,org,checker::text||'@example.invalid','Checker','NO_LOGIN','active');
 INSERT INTO fuel_products(id,organization_id,sku,display_name,family) VALUES
  (gasoline,org,'GAS','Gasolina','regular'),(diesel,org,'DSL','Diésel','diesel');
 INSERT INTO branch_fuel_offers(organization_id,branch_id,fuel_product_id,created_by) VALUES
  (org,branch,gasoline,reporter),(org,branch,diesel,reporter);
 INSERT INTO tanks(id,organization_id,branch_id,code,name,fuel_product_id,nominal_capacity_l,safe_fill_limit_l,unusable_reserve_l) VALUES
  (gas_tank,org,branch,'GAS-TANK','Tanque gasolina',gasoline,20000,19000,500),
  (diesel_tank,org,branch,'DIESEL-TANK','Tanque diésel',diesel,20000,19000,500);
 INSERT INTO tank_inventory_balances(tank_id,organization_id,branch_id,fuel_product_id,on_hand_l,valuation_quality) VALUES
  (gas_tank,org,branch,gasoline,4000,'unknown'),(diesel_tank,org,branch,diesel,1000,'unknown');
 INSERT INTO suppliers(id,organization_id,legal_name,created_by) VALUES(supplier,org,'Transient supplier',reporter);
 INSERT INTO purchase_orders(id,organization_id,branch_id,supplier_id,order_number,status,notes,created_by,approved_by,approved_at)
  VALUES(order_id,org,branch,supplier,'CONT-'||replace(order_id::text,'-',''),'ordered','QA',reporter,checker,clock_timestamp());
 INSERT INTO purchase_order_lines(id,organization_id,purchase_order_id,branch_id,fuel_product_id,quantity_ordered,unit,agreed_unit_price_usd,tank_id) VALUES
  (gas_line,org,order_id,branch,gasoline,1000,'liter',1.25,gas_tank),
  (diesel_line,org,order_id,branch,diesel,1000,'liter',1.35,diesel_tank);
 INSERT INTO incidents(id,organization_id,branch_id,code,category,severity,asset_type,asset_id,description,occurred_at,reported_by,command_id,request_hash) VALUES
  (same_incident,org,branch,'INC-SAME-'||substr(replace(same_incident::text,'-',''),1,8),'wrong_tank_delivery','critical','tank',gas_tank,'Misma gasolina descargada en el tanque; no es mezcla incompatible.',clock_timestamp(),reporter,gen_random_uuid(),repeat('a',64)),
  (mixed_incident,org,branch,'INC-MIX-'||substr(replace(mixed_incident::text,'-',''),1,8),'wrong_tank_delivery','critical','tank',gas_tank,'Se descargó diésel en tanque de gasolina y debe quedar en cuarentena.',clock_timestamp(),reporter,gen_random_uuid(),repeat('b',64));
 SET LOCAL ROLE dlc_api_runtime;
 BEGIN
  INSERT INTO contaminated_deliveries(id,organization_id,branch_id,purchase_order_id,purchase_order_line_id,incident_id,tank_id,
   original_product_id,incoming_product_id,prior_quantity_l,actual_quantity,unit,incoming_quantity_l,prior_cost_usd,incoming_cost_usd,
   remaining_order_quantity,balance_version,document_reference,description,command_id,request_hash,reported_by)
  VALUES(same_row,org,branch,order_id,gas_line,same_incident,gas_tank,gasoline,gasoline,4000,100,'liter',100,NULL,125,900,1,
   'DEL-SAME','Same fuel must not use the contamination workflow.',gen_random_uuid(),repeat('c',64),reporter);
  RAISE EXCEPTION 'Same-fuel contamination was accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO contaminated_deliveries(id,organization_id,branch_id,purchase_order_id,purchase_order_line_id,incident_id,tank_id,
  original_product_id,incoming_product_id,prior_quantity_l,actual_quantity,unit,incoming_quantity_l,prior_cost_usd,incoming_cost_usd,
  remaining_order_quantity,balance_version,document_reference,description,command_id,request_hash,reported_by)
 VALUES(mixed_row,org,branch,order_id,diesel_line,mixed_incident,gas_tank,gasoline,diesel,4000,100,'liter',100,NULL,135,900,1,
  'DEL-MIXED','Different fuel must record and quarantine the real contamination.',gen_random_uuid(),repeat('d',64),reporter);
 IF NOT EXISTS(SELECT 1 FROM contaminated_deliveries WHERE id=mixed_row) THEN RAISE EXCEPTION 'Incompatible fuel event was not recorded'; END IF;
 RAISE EXCEPTION 'ROLLBACK_FIXTURE' USING ERRCODE='Z0001';
EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
ROLLBACK;
