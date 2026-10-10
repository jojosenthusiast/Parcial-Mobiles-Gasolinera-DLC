DO $test$
DECLARE o uuid:=gen_random_uuid();b uuid:=gen_random_uuid();maker uuid:=gen_random_uuid();reviewer uuid:=gen_random_uuid();
 fuel uuid:=gen_random_uuid();tank uuid:=gen_random_uuid();vendor uuid:=gen_random_uuid();quote uuid:=gen_random_uuid();
 scenario uuid:=gen_random_uuid();po uuid:=gen_random_uuid();
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(o,'Transient purchasing plan');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(b,o,'PL01','Planning','central','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status) VALUES
   (maker,o,maker::text||'@example.invalid','Purchaser','NO_LOGIN','active'),
   (reviewer,o,reviewer::text||'@example.invalid','Approver','NO_LOGIN','active');
  INSERT INTO fuel_products(id,organization_id,sku,display_name,family) VALUES(fuel,o,'DIESEL','Diésel','diesel');
  INSERT INTO branch_fuel_offers(organization_id,branch_id,fuel_product_id,created_by) VALUES(o,b,fuel,maker);
  INSERT INTO tanks(id,organization_id,branch_id,code,name,fuel_product_id,nominal_capacity_l,safe_fill_limit_l,unusable_reserve_l)
   VALUES(tank,o,b,'T1','Tanque diésel',fuel,10000,9500,500);
  INSERT INTO tank_inventory_balances(tank_id,organization_id,branch_id,fuel_product_id,on_hand_l,valuation_quality)
   VALUES(tank,o,b,fuel,4000,'unknown');
  INSERT INTO suppliers(id,organization_id,legal_name,created_by) VALUES(vendor,o,'Fuel vendor',maker);
  INSERT INTO supplier_fuel_offers(organization_id,supplier_id,fuel_product_id,is_active)
   VALUES(o,vendor,fuel,true);
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO supplier_fuel_quotes(id,organization_id,supplier_id,fuel_product_id,version,unit,unit_price_usd,
   transport_usd,financing_usd,minimum_delivery_l,lead_days,valid_from,valid_until,confidence,document_reference,recorded_by)
   VALUES(quote,o,vendor,fuel,1,'liter',1.25,20,0,1000,2,clock_timestamp()-interval '1 day',
    clock_timestamp()+interval '3 days','confirmed','QUOTE-001',maker);
  BEGIN
   INSERT INTO purchase_scenarios(organization_id,branch_id,fuel_product_id,tank_id,quote_id,quantity_l,snapshot,valid_until,
    command_id,request_hash,created_by,correlation_id)
   VALUES(o,b,fuel,tank,quote,6000,'{}',clock_timestamp()+interval '2 days',
    gen_random_uuid(),repeat('a',64),maker,gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO purchase_scenarios(id,organization_id,branch_id,fuel_product_id,tank_id,quote_id,quantity_l,snapshot,valid_until,
   command_id,request_hash,created_by,correlation_id)
   VALUES(scenario,o,b,fuel,tank,quote,5000,'{"sampleDays":7}',clock_timestamp()+interval '2 days',
    gen_random_uuid(),repeat('b',64),maker,gen_random_uuid());
  BEGIN
   INSERT INTO purchase_scenario_approvals(scenario_id,organization_id,branch_id,outcome,reason,
    command_id,request_hash,approved_by,correlation_id)
   VALUES(scenario,o,b,'approved','Autoaprobación no permitida',gen_random_uuid(),repeat('c',64),maker,gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO purchase_scenario_approvals(scenario_id,organization_id,branch_id,outcome,reason,
   command_id,request_hash,approved_by,correlation_id)
   VALUES(scenario,o,b,'approved','Cotización y capacidad revisadas',gen_random_uuid(),repeat('d',64),reviewer,gen_random_uuid());
  INSERT INTO purchase_orders(id,organization_id,branch_id,supplier_id,order_number,notes,created_by)
   VALUES(po,o,b,vendor,'PLAN-'||replace(scenario::text,'-',''),'Escenario '||scenario,maker);
  INSERT INTO purchase_order_lines(organization_id,purchase_order_id,branch_id,fuel_product_id,quantity_ordered,unit,agreed_unit_price_usd,tank_id)
   VALUES(o,po,b,fuel,5000,'liter',1.25,tank);
  INSERT INTO purchase_scenario_orders(scenario_id,organization_id,branch_id,order_id,linked_by)
   VALUES(scenario,o,b,po,maker);
  IF (SELECT count(*) FROM purchase_scenario_orders WHERE scenario_id=scenario)<>1
   OR (SELECT status FROM purchase_orders WHERE id=po)<>'draft' THEN RAISE EXCEPTION 'Scenario order not draft'; END IF;
  RAISE EXCEPTION 'ROLLBACK' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=o) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
 RAISE NOTICE 'PASS capacity, independent approval and linked draft order';
END $test$;
