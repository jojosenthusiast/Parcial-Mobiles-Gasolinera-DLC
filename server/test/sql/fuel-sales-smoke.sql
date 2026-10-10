-- Synthetic fixtures exist only inside an exception subtransaction.
-- An intentional Z0001 exception rolls back all rows before returning results.
DO $tests$
DECLARE
  org uuid := gen_random_uuid(); other_org uuid := gen_random_uuid();
  branch uuid := gen_random_uuid(); other_branch uuid := gen_random_uuid();
  actor uuid := gen_random_uuid(); approver uuid := gen_random_uuid();
  product uuid := gen_random_uuid(); other_product uuid := gen_random_uuid();
  tank uuid := gen_random_uuid(); dispenser uuid := gen_random_uuid(); nozzle uuid := gen_random_uuid();
  proposal uuid := gen_random_uuid(); price uuid := gen_random_uuid();
  auth_id uuid := gen_random_uuid(); movement uuid := gen_random_uuid();
  reading uuid := gen_random_uuid(); event uuid := gen_random_uuid();
  sale_id uuid := gen_random_uuid(); sale_movement uuid := gen_random_uuid(); orphan_sale uuid := gen_random_uuid(); second_auth uuid := gen_random_uuid(); second_movement uuid := gen_random_uuid();
  pos_product uuid := gen_random_uuid(); pos_offer uuid := gen_random_uuid(); pos_sale_id uuid := gen_random_uuid(); combined_receipt_id uuid := gen_random_uuid();
  audit bigint; results jsonb := '[]'::jsonb;
BEGIN
  BEGIN
    INSERT INTO organizations(id,name) VALUES(org,'DLC transient validation'),(other_org,'DLC transient other tenant');
    INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(branch,org,'TEST','Transient','occidental','active'),(other_branch,other_org,'OTHER','Other','central','active');
    INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash) VALUES
      (actor,org,actor::text||'@example.invalid','Test actor','NOT_A_LOGIN_HASH'),
      (approver,org,approver::text||'@example.invalid','Test approver','NOT_A_LOGIN_HASH');
    INSERT INTO fuel_products(id,organization_id,sku,display_name,family) VALUES(product,org,'TEST','Regular','regular'),(other_product,other_org,'TEST','Other','regular');
    INSERT INTO branch_fuel_offers(organization_id,branch_id,fuel_product_id,created_by) VALUES(org,branch,product,actor);
    INSERT INTO tanks(id,organization_id,branch_id,code,name,fuel_product_id,nominal_capacity_l,safe_fill_limit_l) VALUES(tank,org,branch,'T1','Test tank',product,1000,900);
    INSERT INTO dispensers(id,organization_id,branch_id,code) VALUES(dispenser,org,branch,'D1');
    INSERT INTO nozzles(id,organization_id,branch_id,dispenser_id,code,product_code,fuel_product_id,service_mode) VALUES(nozzle,org,branch,dispenser,'N1','REG',product,'full_service');
    INSERT INTO branch_operating_profiles(branch_id,organization_id,profile,expected_dispenser_count) VALUES(branch,org,'academicLab22',6);
    INSERT INTO tank_inventory_balances(tank_id,organization_id,branch_id,fuel_product_id,on_hand_l,valuation_quality) VALUES(tank,org,branch,product,100,'unknown');
    INSERT INTO inventory_movements(id,organization_id,branch_id,tank_id,fuel_product_id,movement_type,command_id,request_hash,source_type,quantity_entered,unit_entered,conversion_factor_to_l,observed_l,delta_l,volume_basis,valuation_quality,before_quantity_l,after_quantity_l,actor_user_id,correlation_id)
    VALUES(movement,org,branch,tank,product,'opening',gen_random_uuid(),repeat('a',64),'opening_balance',100,'liter',1,100,100,'observed','unknown',0,100,actor,gen_random_uuid());
    INSERT INTO fuel_price_proposals(id,organization_id,branch_id,fuel_product_id,service_mode,proposed_price_usd_per_unit,unit,effective_at,reason,created_by) VALUES(proposal,org,branch,product,'full_service',4,'us_gallon',now(),'Transient validation',actor);
    UPDATE fuel_price_proposals SET status='approved',approved_by=approver WHERE id=proposal;
    INSERT INTO fuel_price_versions(id,organization_id,branch_id,fuel_product_id,service_mode,version,price_usd_per_unit,unit,effective_at,proposal_id,created_by) VALUES(price,org,branch,product,'full_service',1,4,'us_gallon',now(),proposal,approver);
    INSERT INTO dispense_authorizations(id,organization_id,branch_id,nozzle_id,tank_id,fuel_product_id,price_version_id,service_mode,requested_by,command_id,request_hash,request_type,requested_volume,requested_volume_unit,reserved_l,price_usd_per_unit,price_unit,expires_at)
    VALUES(auth_id,org,branch,nozzle,tank,product,price,'full_service',actor,gen_random_uuid(),repeat('b',64),'volume',10,'liter',10,4,'us_gallon',now()+interval '10 minutes');
    INSERT INTO inventory_movements(id,organization_id,branch_id,tank_id,fuel_product_id,movement_type,command_id,request_hash,source_type,source_id,quantity_entered,unit_entered,conversion_factor_to_l,observed_l,delta_l,volume_basis,valuation_quality,unit_cost_usd_per_l,cost_recognized_usd,before_quantity_l,after_quantity_l,actor_user_id,correlation_id)
    VALUES(sale_movement,org,branch,tank,product,'sale',gen_random_uuid(),repeat('f',64),'dispense_session',auth_id::text,10,'liter',1,10,-10,'observed','known',0.5,5,100,90,actor,gen_random_uuid());
    UPDATE dispense_authorizations SET status='completed',actual_l=10,sale_amount_usd=10.57,inventory_movement_id=sale_movement,completed_at=now() WHERE id=auth_id;

    INSERT INTO inventory_movements(id,organization_id,branch_id,tank_id,fuel_product_id,movement_type,command_id,request_hash,source_type,source_id,quantity_entered,unit_entered,conversion_factor_to_l,observed_l,delta_l,volume_basis,valuation_quality,before_quantity_l,after_quantity_l,actor_user_id,correlation_id)
    VALUES(second_movement,org,branch,tank,product,'sale',gen_random_uuid(),repeat('f',64),'dispense_session',second_auth::text,10,'liter',1,10,-10,'observed','unknown',90,80,actor,gen_random_uuid());
    INSERT INTO dispense_authorizations(id,organization_id,branch_id,nozzle_id,tank_id,fuel_product_id,price_version_id,service_mode,requested_by,command_id,request_hash,request_type,requested_volume,requested_volume_unit,reserved_l,price_usd_per_unit,price_unit,expires_at,status,actual_l,sale_amount_usd,inventory_movement_id,completed_at)
    VALUES(second_auth,org,branch,nozzle,tank,product,price,'full_service',actor,gen_random_uuid(),repeat('b',64),'volume',10,'liter',10,4,'us_gallon',now()+interval '10 minutes','completed',10,10.57,second_movement,now());
    SET LOCAL ROLE dlc_api_runtime;
    INSERT INTO sales(id,organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id)
    SELECT sale_id,org,branch,id,gen_random_uuid(),repeat('1',64),sale_amount_usd,actor,completed_at,gen_random_uuid() FROM dispense_authorizations WHERE id=auth_id;
    INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,fuel_product_id,description,quantity_l,price_usd_per_unit,price_unit,price_version_id,total_usd,inventory_movement_id,cost_usd,unit_cost_usd_per_l,cost_quality)
    VALUES(org,branch,sale_id,1,product,'Regular',10,4,'us_gallon',price,10.57,sale_movement,5,0.5,'known');
    SET CONSTRAINTS ALL IMMEDIATE;
    RESET ROLE;
    SET CONSTRAINTS ALL DEFERRED;
    INSERT INTO pos_products(id,organization_id,branch_id,sku,kind,expiry_required,created_by)
      VALUES(pos_product,org,branch,'WASH1','service',false,actor);
    INSERT INTO pos_offer_versions(id,organization_id,branch_id,product_id,version,description,active,price_usd,service_unit_cost_usd,command_id,request_hash,created_by,correlation_id)
      VALUES(pos_offer,org,branch,pos_product,1,'Lavado',true,4,NULL,gen_random_uuid(),repeat('8',64),actor,gen_random_uuid());
    SET LOCAL ROLE dlc_api_runtime;
    pos_sale_id:=post_pos_sale(org,branch,actor,gen_random_uuid(),repeat('9',64),
      jsonb_build_array(jsonb_build_object('productId',pos_product,'offerVersionId',pos_offer,'quantity','1')),gen_random_uuid());
    SET CONSTRAINTS ALL IMMEDIATE;
    INSERT INTO combined_internal_receipts(id,organization_id,branch_id,fuel_sale_id,pos_sale_id,command_id,request_hash,created_by,correlation_id)
      VALUES(combined_receipt_id,org,branch,sale_id,pos_sale_id,gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());
    RESET ROLE;
    SET CONSTRAINTS ALL DEFERRED;
    IF (SELECT total_usd+ (SELECT total_usd FROM sales WHERE id=pos_sale_id) FROM sales WHERE id=sale_id)<>14.57 THEN
      RAISE EXCEPTION 'Combined internal total is incorrect';
    END IF;
    results := results || jsonb_build_object('test','runtime_combines_fuel_and_pos_as_separate_source_sales','result','PASS');
    IF (SELECT count(*) FROM combined_internal_receipts WHERE id=combined_receipt_id)<>1
      OR (SELECT authorization_id FROM sales WHERE id=sale_id) IS NULL
      OR (SELECT authorization_id FROM sales WHERE id=pos_sale_id) IS NOT NULL THEN
      RAISE EXCEPTION 'Combined receipt changed source sale identity';
    END IF;
    results := results || jsonb_build_object('test','combined_document_preserves_source_sales','result','PASS');
    BEGIN
      SET LOCAL ROLE dlc_api_runtime;
      INSERT INTO combined_internal_receipts(organization_id,branch_id,fuel_sale_id,pos_sale_id,command_id,request_hash,created_by,correlation_id)
        VALUES(org,branch,sale_id,pos_sale_id,gen_random_uuid(),repeat('b',64),actor,gen_random_uuid());
      RAISE EXCEPTION 'FAIL: duplicate combined receipt accepted' USING ERRCODE='Z0002';
    EXCEPTION WHEN unique_violation THEN
      RESET ROLE;
      results := results || jsonb_build_object('test','source_ticket_cannot_be_grouped_twice','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE dlc_api_runtime;
      INSERT INTO combined_internal_receipts(organization_id,branch_id,fuel_sale_id,pos_sale_id,command_id,request_hash,created_by,correlation_id)
        VALUES(org,branch,pos_sale_id,sale_id,gen_random_uuid(),repeat('c',64),actor,gen_random_uuid());
      RAISE EXCEPTION 'FAIL: reversed sale kinds accepted' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      RESET ROLE;
      results := results || jsonb_build_object('test','combined_receipt_requires_correct_sale_kinds','result','PASS');
    END;
    BEGIN
      UPDATE combined_internal_receipts SET correlation_id=gen_random_uuid() WHERE id=combined_receipt_id;
      RAISE EXCEPTION 'FAIL: combined receipt mutable' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','combined_receipt_is_immutable','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE authenticated; PERFORM * FROM combined_internal_receipts;
      RAISE EXCEPTION 'FAIL: client can read combined receipts' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      RESET ROLE;
      results := results || jsonb_build_object('test','client_cannot_read_combined_receipts','result','PASS');
    END;
    results := results || jsonb_build_object('test','runtime_creates_ticket_and_original_snapshot','result','PASS');
    IF (SELECT count(*) FROM inventory_movements WHERE organization_id=org)<>3 THEN RAISE EXCEPTION 'Ticket posted inventory twice'; END IF;
    results := results || jsonb_build_object('test','sale_does_not_duplicate_inventory','result','PASS');
    IF (SELECT net_usd IS NOT NULL OR tax_usd IS NOT NULL FROM sales WHERE id=sale_id) THEN RAISE EXCEPTION 'Invented tax'; END IF;
    results := results || jsonb_build_object('test','unconfigured_tax_is_null','result','PASS');
    BEGIN
      INSERT INTO sales(organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id) SELECT org,branch,id,gen_random_uuid(),repeat('2',64),sale_amount_usd,actor,completed_at,gen_random_uuid() FROM dispense_authorizations WHERE id=auth_id;
      RAISE EXCEPTION 'FAIL: duplicate_dispatch' USING ERRCODE='Z0002';
    EXCEPTION WHEN unique_violation THEN
      results := results || jsonb_build_object('test','duplicate_dispatch','result','PASS');
    END;
    BEGIN
      INSERT INTO sales(organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id) SELECT org,branch,id,gen_random_uuid(),repeat('2',64),99,actor,completed_at,gen_random_uuid() FROM dispense_authorizations WHERE id=auth_id;
      RAISE EXCEPTION 'FAIL: changed_dispatch_amount' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','changed_dispatch_amount','result','PASS');
    END;
    BEGIN
      INSERT INTO sales(organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id) SELECT other_org,other_branch,id,gen_random_uuid(),repeat('2',64),sale_amount_usd,actor,completed_at,gen_random_uuid() FROM dispense_authorizations WHERE id=second_auth;
      RAISE EXCEPTION 'FAIL: cross_tenant_sale' USING ERRCODE='Z0002';
    EXCEPTION WHEN foreign_key_violation THEN
      results := results || jsonb_build_object('test','cross_tenant_sale','result','PASS');
    END;
    BEGIN
      INSERT INTO sales(organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,tax_usd,created_by,occurred_at,correlation_id) SELECT org,branch,id,gen_random_uuid(),repeat('2',64),sale_amount_usd,0,actor,completed_at,gen_random_uuid() FROM dispense_authorizations WHERE id=auth_id;
      RAISE EXCEPTION 'FAIL: tax_not_assumed_zero' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','tax_not_assumed_zero','result','PASS');
    END;
    BEGIN
      INSERT INTO sales(organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,status,created_by,occurred_at,correlation_id) SELECT org,branch,id,gen_random_uuid(),repeat('2',64),sale_amount_usd,'paid',actor,completed_at,gen_random_uuid() FROM dispense_authorizations WHERE id=auth_id;
      RAISE EXCEPTION 'FAIL: paid_not_available_before_payments' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','paid_not_available_before_payments','result','PASS');
    END;
    BEGIN
      INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,fuel_product_id,description,quantity_l,price_usd_per_unit,price_unit,price_version_id,total_usd,inventory_movement_id,cost_usd,unit_cost_usd_per_l,cost_quality) VALUES(org,branch,sale_id,1,product,'Regular',10,9,'us_gallon',price,10.57,sale_movement,5,0.5,'known');
      RAISE EXCEPTION 'FAIL: changed_original_price' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','changed_original_price','result','PASS');
    END;
    BEGIN
      INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,fuel_product_id,description,quantity_l,price_usd_per_unit,price_unit,price_version_id,total_usd,inventory_movement_id,cost_usd,unit_cost_usd_per_l,cost_quality) VALUES(org,branch,sale_id,1,product,'Regular',10,4,'us_gallon',price,10.57,sale_movement,1,0.5,'known');
      RAISE EXCEPTION 'FAIL: changed_original_cost' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','changed_original_cost','result','PASS');
    END;
    BEGIN
      INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,fuel_product_id,description,quantity_l,price_usd_per_unit,price_unit,price_version_id,total_usd,inventory_movement_id,cost_usd,unit_cost_usd_per_l,cost_quality) VALUES(org,branch,sale_id,1,product,'Regular',11,4,'us_gallon',price,10.57,sale_movement,5,0.5,'known');
      RAISE EXCEPTION 'FAIL: changed_original_volume' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','changed_original_volume','result','PASS');
    END;
    BEGIN
      UPDATE sales SET total_usd=99 WHERE id=sale_id;
      RAISE EXCEPTION 'FAIL: immutable_ticket' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','immutable_ticket','result','PASS');
    END;
    BEGIN
      DELETE FROM sale_lines WHERE inventory_movement_id=sale_movement;
      RAISE EXCEPTION 'FAIL: immutable_line' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','immutable_line','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE dlc_api_runtime; UPDATE sales SET total_usd=99 WHERE id=sale_id;
      RAISE EXCEPTION 'FAIL: runtime_cannot_edit_ticket' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results := results || jsonb_build_object('test','runtime_cannot_edit_ticket','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE authenticated; PERFORM * FROM sales;
      RAISE EXCEPTION 'FAIL: client_cannot_read' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results := results || jsonb_build_object('test','client_cannot_read','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE service_role; PERFORM * FROM sale_lines;
      RAISE EXCEPTION 'FAIL: service_key_cannot_read' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results := results || jsonb_build_object('test','service_key_cannot_read','result','PASS');
    END;
    BEGIN
      INSERT INTO sales(id,organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id)
      SELECT orphan_sale,org,branch,id,gen_random_uuid(),repeat('3',64),sale_amount_usd,actor,completed_at,gen_random_uuid() FROM dispense_authorizations WHERE id=second_auth;
      SET CONSTRAINTS ALL IMMEDIATE;
      RAISE EXCEPTION 'FAIL: orphan sale accepted' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','ticket_without_line_cannot_commit','result','PASS');
    END;
    IF EXISTS(SELECT 1 FROM pg_class WHERE relname IN('sales','sale_lines') AND NOT relrowsecurity) THEN RAISE EXCEPTION 'RLS missing'; END IF;
    results := results || jsonb_build_object('test','sales_rls','result','PASS');
    RAISE EXCEPTION 'rollback test fixtures' USING ERRCODE='Z0001';
  EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
  END;
  IF EXISTS(SELECT 1 FROM organizations WHERE id=org OR id=other_org) THEN RAISE EXCEPTION 'Fixture rollback failed'; END IF;
  results := results || jsonb_build_object('test','fixtures_rolled_back','result','PASS');
  PERFORM set_config('dlc.test_results',results::text,false);
END;
$tests$;
SELECT current_setting('dlc.test_results')::jsonb AS tests;
