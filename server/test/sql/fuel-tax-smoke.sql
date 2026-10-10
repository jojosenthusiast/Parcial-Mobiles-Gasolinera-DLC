-- Synthetic fixtures exist only inside an exception subtransaction.
-- An intentional Z0001 exception rolls back all rows before returning results.
DO $tests$
<<fixture>>
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
  tax_proposal uuid:=gen_random_uuid(); tax_version uuid:=gen_random_uuid(); old_sale uuid:=gen_random_uuid();
  rules jsonb:='[{"code":"TEST_FIXED","label":"Synthetic fixed","kind":"fixed_per_liter","base":"observed_volume","rate":"0.10"},{"code":"TEST_PCT","label":"Synthetic percentage","kind":"percentage","base":"net","rate":"0.10"}]';
  expiry_proposal uuid:=gen_random_uuid(); deadline timestamptz;
  result jsonb;
  audit bigint; results jsonb := '[]'::jsonb;
BEGIN
  BEGIN
    INSERT INTO organizations(id,name) VALUES(org,'DLC transient validation'),(other_org,'DLC transient other tenant');
    INSERT INTO branches(id,organization_id,code,name,zone) VALUES(branch,org,'TEST','Transient','occidental'),(other_branch,other_org,'OTHER','Other','central');
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
    INSERT INTO fuel_tax_proposals(id,organization_id,branch_id,fuel_product_id,command_id,request_hash,mode,rules,source_reference,reason,effective_at,proposed_by,correlation_id)
    VALUES(tax_proposal,org,branch,product,gen_random_uuid(),repeat('1',64),'included',rules,'SYNTHETIC ARITHMETIC FIXTURE','Not a jurisdictional tax policy',now()+interval '1 day',actor,gen_random_uuid());
    INSERT INTO fuel_tax_versions(id,organization_id,branch_id,fuel_product_id,proposal_id,version,command_id,request_hash,mode,rules,source_reference,effective_at,approved_by,correlation_id)
    VALUES(tax_version,org,branch,product,tax_proposal,1,gen_random_uuid(),repeat('2',64),'included',rules,'SYNTHETIC ARITHMETIC FIXTURE',now()+interval '1 day',approver,gen_random_uuid());
    RESET ROLE;
    -- Future dates are synthetic test fixtures; no clock manipulation in production.
    UPDATE dispense_authorizations SET completed_at=now()+interval '2 days' WHERE id=auth_id;
    SET LOCAL ROLE dlc_api_runtime;
    INSERT INTO sales(id,organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id)
    SELECT sale_id,org,branch,id,gen_random_uuid(),repeat('3',64),sale_amount_usd,actor,completed_at,gen_random_uuid() FROM dispense_authorizations WHERE id=auth_id;
    INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,fuel_product_id,description,quantity_l,price_usd_per_unit,price_unit,price_version_id,total_usd,inventory_movement_id,cost_usd,unit_cost_usd_per_l,cost_quality)
    VALUES(org,branch,sale_id,1,product,'Regular',10,4,'us_gallon',price,10.57,sale_movement,5,0.5,'known');
    SELECT t.result INTO result FROM sale_tax_snapshots t WHERE t.sale_id=fixture.sale_id;
    IF result->>'netUsd'<>'8.70' OR result->>'taxUsd'<>'1.87' THEN RAISE EXCEPTION 'Wrong tax result: %',result; END IF;
    results:=results || jsonb_build_object('test','runtime_automatically_captures_approved_snapshot','result','PASS');
    IF (result->>'netUsd')::numeric+(result->>'taxUsd')::numeric<>10.57 THEN RAISE EXCEPTION 'Net/tax do not reconcile'; END IF;
    results:=results || jsonb_build_object('test','components_reconcile_to_original_gross','result','PASS');
    INSERT INTO sales(id,organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id)
    SELECT old_sale,org,branch,id,gen_random_uuid(),repeat('4',64),sale_amount_usd,actor,completed_at,gen_random_uuid() FROM dispense_authorizations WHERE id=second_auth;
    INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,fuel_product_id,description,quantity_l,price_usd_per_unit,price_unit,price_version_id,total_usd,inventory_movement_id,cost_usd,unit_cost_usd_per_l,cost_quality)
    VALUES(org,branch,old_sale,1,product,'Regular',10,4,'us_gallon',price,10.57,second_movement,NULL,NULL,'unknown');
    IF EXISTS(SELECT 1 FROM sale_tax_snapshots t WHERE t.sale_id=old_sale) THEN RAISE EXCEPTION 'Future policy changed old dispatch'; END IF;
    results:=results || jsonb_build_object('test','future_policy_does_not_change_prior_dispatch','result','PASS');
    SET CONSTRAINTS ALL IMMEDIATE;
    RESET ROLE;
    BEGIN
      INSERT INTO fuel_tax_versions(organization_id,branch_id,fuel_product_id,proposal_id,version,command_id,request_hash,mode,rules,source_reference,effective_at,approved_by,correlation_id) VALUES(org,branch,product,tax_proposal,2,gen_random_uuid(),repeat('5',64),'included',rules,'SYNTHETIC ARITHMETIC FIXTURE',now()+interval '1 day',actor,gen_random_uuid());
      RAISE EXCEPTION 'FAIL: self_approval' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results:=results || jsonb_build_object('test','self_approval','result','PASS');
    END;
    BEGIN
      INSERT INTO fuel_tax_versions(organization_id,branch_id,fuel_product_id,proposal_id,version,command_id,request_hash,mode,rules,source_reference,effective_at,approved_by,correlation_id) VALUES(org,branch,product,tax_proposal,2,gen_random_uuid(),repeat('5',64),'exempt','[]','SYNTHETIC ARITHMETIC FIXTURE',now()+interval '1 day',approver,gen_random_uuid());
      RAISE EXCEPTION 'FAIL: changed_approved_rules' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results:=results || jsonb_build_object('test','changed_approved_rules','result','PASS');
    END;
    BEGIN
      INSERT INTO fuel_tax_proposals(organization_id,branch_id,fuel_product_id,command_id,request_hash,mode,rules,source_reference,reason,effective_at,proposed_by,correlation_id) VALUES(org,branch,product,gen_random_uuid(),repeat('6',64),'exempt','[]','Synthetic','Test',now()-interval '1 day',actor,gen_random_uuid());
      RAISE EXCEPTION 'FAIL: backdated_policy' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results:=results || jsonb_build_object('test','backdated_policy','result','PASS');
    END;
    BEGIN
      INSERT INTO fuel_tax_proposals(organization_id,branch_id,fuel_product_id,command_id,request_hash,mode,rules,source_reference,reason,effective_at,proposed_by,correlation_id) VALUES(org,branch,other_product,gen_random_uuid(),repeat('6',64),'exempt','[]','Synthetic','Test',now()+interval '1 day',actor,gen_random_uuid());
      RAISE EXCEPTION 'FAIL: foreign_tenant_product' USING ERRCODE='Z0002';
    EXCEPTION WHEN foreign_key_violation THEN
      results:=results || jsonb_build_object('test','foreign_tenant_product','result','PASS');
    END;
    BEGIN
      INSERT INTO fuel_tax_proposals(organization_id,branch_id,fuel_product_id,command_id,request_hash,mode,rules,source_reference,reason,effective_at,proposed_by,correlation_id) VALUES(org,branch,product,gen_random_uuid(),repeat('6',64),'included','[{"code":"TEST","label":"Test","kind":"percentage","base":null,"rate":"0.1"}]','Synthetic','Test',now()+interval '1 day',actor,gen_random_uuid());
      RAISE EXCEPTION 'FAIL: null_percentage_base' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results:=results || jsonb_build_object('test','null_percentage_base','result','PASS');
    END;
    BEGIN
      INSERT INTO sale_tax_snapshots(organization_id,branch_id,sale_id,policy_version_id,result) VALUES(org,branch,sale_id,tax_version,'{"netUsd":"99"}');
      RAISE EXCEPTION 'FAIL: wrong_snapshot' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results:=results || jsonb_build_object('test','wrong_snapshot','result','PASS');
    END;
    BEGIN
      INSERT INTO sale_tax_snapshots(organization_id,branch_id,sale_id,policy_version_id,result) VALUES(org,branch,old_sale,tax_version,calculate_fuel_tax(10.57,10,'included',rules));
      RAISE EXCEPTION 'FAIL: retroactive_snapshot' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results:=results || jsonb_build_object('test','retroactive_snapshot','result','PASS');
    END;
    BEGIN
      UPDATE sale_tax_snapshots SET result='{}' WHERE policy_version_id=tax_version;
      RAISE EXCEPTION 'FAIL: snapshot_immutable' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results:=results || jsonb_build_object('test','snapshot_immutable','result','PASS');
    END;
    BEGIN
      DELETE FROM fuel_tax_versions WHERE id=tax_version;
      RAISE EXCEPTION 'FAIL: policy_immutable' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results:=results || jsonb_build_object('test','policy_immutable','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE authenticated; PERFORM * FROM fuel_tax_versions;
      RAISE EXCEPTION 'FAIL: clients_cannot_read_policies' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results:=results || jsonb_build_object('test','clients_cannot_read_policies','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE anon; PERFORM calculate_fuel_tax(10,1,'exempt','[]');
      RAISE EXCEPTION 'FAIL: clients_cannot_call_tax_engine' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results:=results || jsonb_build_object('test','clients_cannot_call_tax_engine','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE dlc_api_runtime; UPDATE fuel_tax_versions SET mode='exempt' WHERE id=tax_version;
      RAISE EXCEPTION 'FAIL: runtime_cannot_rewrite_policy' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results:=results || jsonb_build_object('test','runtime_cannot_rewrite_policy','result','PASS');
    END;
    BEGIN
      PERFORM calculate_fuel_tax(0.01,10,'included',rules);
      RAISE EXCEPTION 'FAIL: tax_cannot_exceed_gross' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results:=results || jsonb_build_object('test','tax_cannot_exceed_gross','result','PASS');
    END;
    deadline:=clock_timestamp()+interval '200 milliseconds';
    INSERT INTO fuel_tax_proposals(id,organization_id,branch_id,fuel_product_id,command_id,request_hash,mode,rules,source_reference,reason,effective_at,proposed_by,proposed_at,correlation_id)
    VALUES(expiry_proposal,org,branch,product,gen_random_uuid(),repeat('7',64),'exempt','[]','Synthetic clock test','Expire while waiting',deadline,actor,'2000-01-01',gen_random_uuid());
    IF (SELECT proposed_at FROM fuel_tax_proposals WHERE id=expiry_proposal)<'2026-01-01' THEN RAISE EXCEPTION 'Caller forged proposal time'; END IF;
    results:=results || jsonb_build_object('test','proposal_time_is_server_stamped','result','PASS');
    PERFORM pg_sleep(0.25);
    BEGIN
      INSERT INTO fuel_tax_versions(organization_id,branch_id,fuel_product_id,proposal_id,version,command_id,request_hash,mode,rules,source_reference,effective_at,approved_by,approved_at,correlation_id)
      VALUES(org,branch,product,expiry_proposal,2,gen_random_uuid(),repeat('8',64),'exempt','[]','Synthetic clock test',deadline,approver,'2000-01-01',gen_random_uuid());
      RAISE EXCEPTION 'FAIL: approval past deadline' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results:=results || jsonb_build_object('test','expiry_rechecked_after_wait_using_wall_clock','result','PASS');
    END;
    IF EXISTS(SELECT 1 FROM pg_class WHERE relname IN('fuel_tax_proposals','fuel_tax_versions','sale_tax_snapshots') AND NOT relrowsecurity) THEN RAISE EXCEPTION 'Missing RLS'; END IF;
    results:=results || jsonb_build_object('test','tax_tables_rls','result','PASS');
    RAISE EXCEPTION 'Rollback synthetic fixtures' USING ERRCODE='Z0001';
  EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
  END;
  IF EXISTS(SELECT 1 FROM organizations WHERE id=org OR id=other_org) THEN RAISE EXCEPTION 'Fixture rollback failed'; END IF;
  results:=results || jsonb_build_object('test','fixtures_rolled_back','result','PASS');
  PERFORM set_config('dlc.test_results',results::text,false);
END;
$tests$;
SELECT current_setting('dlc.test_results')::jsonb AS tests;
