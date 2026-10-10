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
  audit bigint; results jsonb := '[]'::jsonb;
  default_function_name text := 'dlc_default_exec_smoke_' || replace(gen_random_uuid()::text,'-','');
BEGIN
  BEGIN
    EXECUTE format('CREATE FUNCTION public.%I() RETURNS integer LANGUAGE sql AS %L',default_function_name,'SELECT 1');
    IF EXISTS(
      SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) AS roles(role_name)
      WHERE has_function_privilege(role_name,to_regprocedure(format('public.%I()',default_function_name)),'EXECUTE')
    ) THEN RAISE EXCEPTION 'New function inherited client EXECUTE'; END IF;
    EXECUTE format('DROP FUNCTION public.%I()',default_function_name);
    results := results || jsonb_build_object('test','new_functions_default_to_server_only','result','PASS');

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
    INSERT INTO nozzle_meter_readings(id,organization_id,branch_id,nozzle_id,command_id,request_hash,reading_type,value,unit,source,captured_by,correlation_id)
    VALUES(reading,org,branch,nozzle,gen_random_uuid(),repeat('d',64),'baseline',100,'gallon_us','manual',actor,gen_random_uuid());
    INSERT INTO dispense_authorization_events(id,organization_id,branch_id,authorization_id,command_id,request_hash,event_type,next_status,actor_user_id,correlation_id)
    VALUES(event,org,branch,auth_id,gen_random_uuid(),repeat('e',64),'authorized','authorized',actor,gen_random_uuid());
    INSERT INTO audit_events(organization_id,branch_id,actor_user_id,correlation_id,action,entity_type,entity_id) VALUES(org,branch,actor,gen_random_uuid(),'test','test',branch::text) RETURNING id INTO audit;

    BEGIN
      UPDATE branch_fuel_offers SET fuel_product_id=other_product WHERE branch_id=branch;
      RAISE EXCEPTION 'FAIL: cross_tenant_offer accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN foreign_key_violation THEN
      results := results || jsonb_build_object('test','cross_tenant_offer','result','PASS');
    END;

    BEGIN
      UPDATE branches SET organization_id=other_org WHERE id=branch;
      RAISE EXCEPTION 'FAIL: cross_tenant_actor accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN foreign_key_violation THEN
      results := results || jsonb_build_object('test','cross_tenant_actor','result','PASS');
    END;

    BEGIN
      UPDATE tank_inventory_balances SET on_hand_l=-1 WHERE tank_id=tank;
      RAISE EXCEPTION 'FAIL: negative_inventory accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','negative_inventory','result','PASS');
    END;

    BEGIN
      UPDATE tank_inventory_balances SET average_cost_per_l_usd=1 WHERE tank_id=tank;
      RAISE EXCEPTION 'FAIL: unknown_cost_not_invented accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','unknown_cost_not_invented','result','PASS');
    END;

    BEGIN
      UPDATE tank_inventory_balances SET valuation_quality='known' WHERE tank_id=tank;
      RAISE EXCEPTION 'FAIL: known_cost_requires_value accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','known_cost_requires_value','result','PASS');
    END;

    BEGIN
      UPDATE branch_operating_profiles SET expected_dispenser_count=4 WHERE branch_id=branch;
      RAISE EXCEPTION 'FAIL: academic_profile_requires_six accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','academic_profile_requires_six','result','PASS');
    END;

    BEGIN
      UPDATE fuel_price_proposals SET approved_by=actor WHERE id=proposal;
      RAISE EXCEPTION 'FAIL: price_cannot_self_approve accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','price_cannot_self_approve','result','PASS');
    END;

    BEGIN
      INSERT INTO fuel_price_proposals(organization_id,branch_id,fuel_product_id,service_mode,proposed_price_usd_per_unit,unit,effective_at,reason,created_by) VALUES(org,branch,product,'full_service',0,'liter',now(),'test',actor);
      RAISE EXCEPTION 'FAIL: price_positive accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','price_positive','result','PASS');
    END;

    BEGIN
      UPDATE dispense_authorizations SET progress_l=11 WHERE id=auth_id;
      RAISE EXCEPTION 'FAIL: progress_cannot_exceed_reservation accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','progress_cannot_exceed_reservation','result','PASS');
    END;

    BEGIN
      UPDATE dispense_authorizations SET status='completed' WHERE id=auth_id;
      RAISE EXCEPTION 'FAIL: completed_requires_evidence accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','completed_requires_evidence','result','PASS');
    END;

    BEGIN
      INSERT INTO dispense_authorizations(organization_id,branch_id,nozzle_id,tank_id,fuel_product_id,price_version_id,service_mode,requested_by,command_id,request_hash,request_type,requested_volume,requested_volume_unit,reserved_l,price_usd_per_unit,price_unit,expires_at) VALUES(org,branch,nozzle,tank,product,price,'full_service',actor,gen_random_uuid(),repeat('c',64),'volume',1,'liter',1,4,'us_gallon',now()+interval '10 minutes');
      RAISE EXCEPTION 'FAIL: one_active_authorization_per_nozzle accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN unique_violation THEN
      results := results || jsonb_build_object('test','one_active_authorization_per_nozzle','result','PASS');
    END;

    BEGIN
      UPDATE audit_events SET action='changed' WHERE id=audit;
      RAISE EXCEPTION 'FAIL: audit_update_blocked accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','audit_update_blocked','result','PASS');
    END;

    BEGIN
      DELETE FROM audit_events WHERE id=audit;
      RAISE EXCEPTION 'FAIL: audit_delete_blocked accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','audit_delete_blocked','result','PASS');
    END;

    BEGIN
      UPDATE inventory_movements SET source_type='changed' WHERE id=movement;
      RAISE EXCEPTION 'FAIL: ledger_update_blocked accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','ledger_update_blocked','result','PASS');
    END;

    BEGIN
      DELETE FROM inventory_movements WHERE id=movement;
      RAISE EXCEPTION 'FAIL: ledger_delete_blocked accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','ledger_delete_blocked','result','PASS');
    END;

    BEGIN
      UPDATE fuel_price_versions SET price_usd_per_unit=5 WHERE id=price;
      RAISE EXCEPTION 'FAIL: price_version_update_blocked accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','price_version_update_blocked','result','PASS');
    END;

    BEGIN
      DELETE FROM fuel_price_versions WHERE id=price;
      RAISE EXCEPTION 'FAIL: price_version_delete_blocked accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','price_version_delete_blocked','result','PASS');
    END;

    BEGIN
      SET LOCAL ROLE anon; PERFORM count(*) FROM organizations;
      RAISE EXCEPTION 'FAIL: anon_direct_read_denied accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results := results || jsonb_build_object('test','anon_direct_read_denied','result','PASS');
    END;

    BEGIN
      SET LOCAL ROLE authenticated; PERFORM count(*) FROM organizations;
      RAISE EXCEPTION 'FAIL: authenticated_direct_read_denied accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results := results || jsonb_build_object('test','authenticated_direct_read_denied','result','PASS');
    END;

    BEGIN
      SET LOCAL ROLE service_role; PERFORM count(*) FROM organizations;
      RAISE EXCEPTION 'FAIL: service_role_direct_read_denied accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results := results || jsonb_build_object('test','service_role_direct_read_denied','result','PASS');
    END;

    BEGIN
      INSERT INTO employees(organization_id,branch_id,employee_code,legal_name) VALUES(org,other_branch,'TEST','Transient');
      RAISE EXCEPTION 'FAIL: employee_cannot_cross_tenant accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN foreign_key_violation THEN
      results := results || jsonb_build_object('test','employee_cannot_cross_tenant','result','PASS');
    END;
    BEGIN
      UPDATE nozzles SET organization_id=other_org WHERE id=nozzle;
      RAISE EXCEPTION 'FAIL: nozzle_cannot_cross_tenant accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN foreign_key_violation THEN
      results := results || jsonb_build_object('test','nozzle_cannot_cross_tenant','result','PASS');
    END;
    BEGIN
      INSERT INTO inventory_movements(id,organization_id,branch_id,tank_id,fuel_product_id,movement_type,command_id,request_hash,source_type,quantity_entered,unit_entered,conversion_factor_to_l,observed_l,delta_l,volume_basis,valuation_quality,before_quantity_l,after_quantity_l,actor_user_id,correlation_id)
    VALUES(gen_random_uuid(),org,branch,tank,product,'opening',gen_random_uuid(),repeat('a',64),'opening_balance',100,'liter',1,100,100,'observed','unknown',0,99,actor,gen_random_uuid());
      RAISE EXCEPTION 'FAIL: inventory_equation_enforced accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','inventory_equation_enforced','result','PASS');
    END;
    BEGIN
      UPDATE dispense_authorizations SET requested_volume=NULL WHERE id=auth_id;
      RAISE EXCEPTION 'FAIL: volume_request_cannot_be_null accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','volume_request_cannot_be_null','result','PASS');
    END;
    BEGIN
      UPDATE dispense_authorizations SET request_type='amount',requested_volume=NULL,requested_volume_unit=NULL,requested_amount_usd=NULL WHERE id=auth_id;
      RAISE EXCEPTION 'FAIL: amount_request_cannot_be_null accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN check_violation THEN
      results := results || jsonb_build_object('test','amount_request_cannot_be_null','result','PASS');
    END;
    BEGIN
      UPDATE nozzle_meter_readings SET value=101 WHERE id=reading;
      RAISE EXCEPTION 'FAIL: meter_update_blocked accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','meter_update_blocked','result','PASS');
    END;
    BEGIN
      DELETE FROM nozzle_meter_readings WHERE id=reading;
      RAISE EXCEPTION 'FAIL: meter_delete_blocked accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','meter_delete_blocked','result','PASS');
    END;
    BEGIN
      UPDATE dispense_authorization_events SET reason='changed' WHERE id=event;
      RAISE EXCEPTION 'FAIL: dispense_event_update_blocked accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','dispense_event_update_blocked','result','PASS');
    END;
    BEGIN
      DELETE FROM dispense_authorization_events WHERE id=event;
      RAISE EXCEPTION 'FAIL: dispense_event_delete_blocked accepted invalid operation' USING ERRCODE='Z0002';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      results := results || jsonb_build_object('test','dispense_event_delete_blocked','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE dlc_api_runtime;
      IF NOT EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Runtime cannot read fixtures'; END IF;
      PERFORM id FROM nozzles WHERE id=nozzle FOR UPDATE;
      UPDATE tank_inventory_balances SET version=version+1 WHERE tank_id=tank;
      IF NOT FOUND THEN RAISE EXCEPTION 'Runtime cannot update inventory balance'; END IF;
      INSERT INTO audit_events(organization_id,branch_id,actor_user_id,correlation_id,action,entity_type,entity_id)
      VALUES(org,branch,actor,gen_random_uuid(),'runtime-test','test',branch::text);
      INSERT INTO dispense_authorization_events(organization_id,branch_id,authorization_id,command_id,request_hash,event_type,next_status,actor_user_id,correlation_id)
      VALUES(org,branch,auth_id,gen_random_uuid(),repeat('f',64),'started','dispensing',actor,gen_random_uuid());
      RAISE EXCEPTION 'rollback runtime changes' USING ERRCODE='Z0003';
    EXCEPTION WHEN SQLSTATE 'Z0003' THEN
      results := results || jsonb_build_object('test','runtime_read_lock_update_append_allowed','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE dlc_api_runtime;
      UPDATE audit_events SET action='changed' WHERE id=audit;
      RAISE EXCEPTION 'FAIL: runtime_cannot_edit_audit' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results := results || jsonb_build_object('test','runtime_cannot_edit_audit','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE dlc_api_runtime;
      DELETE FROM inventory_movements WHERE id=movement;
      RAISE EXCEPTION 'FAIL: runtime_cannot_delete_ledger' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results := results || jsonb_build_object('test','runtime_cannot_delete_ledger','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE dlc_api_runtime;
      UPDATE schema_migrations SET checksum='wrong' WHERE version='0001_platform.sql';
      RAISE EXCEPTION 'FAIL: runtime_cannot_edit_migrations' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results := results || jsonb_build_object('test','runtime_cannot_edit_migrations','result','PASS');
    END;
    BEGIN
      SET LOCAL ROLE dlc_api_runtime;
      INSERT INTO permissions(code,description) VALUES('test.forbidden','Forbidden');
      RAISE EXCEPTION 'FAIL: runtime_cannot_edit_permissions' USING ERRCODE='Z0002';
    EXCEPTION WHEN insufficient_privilege THEN
      results := results || jsonb_build_object('test','runtime_cannot_edit_permissions','result','PASS');
    END;
    IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='dlc_api_runtime' AND (rolcanlogin OR rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb)) OR has_schema_privilege('dlc_api_runtime','public','create') THEN
      RAISE EXCEPTION 'Runtime role has excess administrative privileges';
    END IF;
    results := results || jsonb_build_object('test','runtime_no_admin_or_schema_create','result','PASS');
    IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND (has_function_privilege('anon',p.oid,'execute') OR has_function_privilege('authenticated',p.oid,'execute') OR has_function_privilege('service_role',p.oid,'execute'))) THEN
      RAISE EXCEPTION 'Client function execution grant remains';
    END IF;
    results := results || jsonb_build_object('test','client_function_grants_revoked','result','PASS');
    IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity)<>0 THEN
      RAISE EXCEPTION 'Some application tables lack RLS';
    END IF;
    results := results || jsonb_build_object('test','all_tables_rls','result','PASS');
    RAISE EXCEPTION 'rollback test fixtures' USING ERRCODE='Z0001';
  EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
  END;
  IF EXISTS(SELECT 1 FROM organizations WHERE id=org OR id=other_org) THEN
    RAISE EXCEPTION 'Fixture rollback failed';
  END IF;
  results := results || jsonb_build_object('test','fixtures_rolled_back','result','PASS');
  PERFORM set_config('dlc.test_results',results::text,false);
END;
$tests$;
SELECT current_setting('dlc.test_results')::jsonb AS tests;
