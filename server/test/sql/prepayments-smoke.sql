-- Execute after migration 0022 inside a transaction that is rolled back.
-- The inner exception subtransaction also removes all synthetic rows.
DO $test$
<<fixture>>
DECLARE
 org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); approver uuid:=gen_random_uuid();
 product uuid:=gen_random_uuid(); tank uuid:=gen_random_uuid(); dispenser uuid:=gen_random_uuid(); nozzle uuid:=gen_random_uuid();
 proposal uuid:=gen_random_uuid(); price uuid:=gen_random_uuid(); auth_id uuid:=gen_random_uuid(); movement uuid:=gen_random_uuid();
 sale_id uuid:=gen_random_uuid(); register_id uuid:=gen_random_uuid(); session_id uuid:=gen_random_uuid();
 advance_id uuid:=gen_random_uuid(); unknown_id uuid:=gen_random_uuid(); confirmed_later_id uuid:=gen_random_uuid(); allocation_id uuid:=gen_random_uuid();
 approval_id uuid:=gen_random_uuid(); refund_id uuid:=gen_random_uuid(); hold_id uuid:=gen_random_uuid();
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(org,'Prepayment transient check');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(branch,org,'PREPAY','Prepay','occidental','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash) VALUES
   (actor,org,actor::text||'@example.invalid','Cashier','NOT_A_LOGIN_HASH'),
   (approver,org,approver::text||'@example.invalid','Approver','NOT_A_LOGIN_HASH');
  INSERT INTO fuel_products(id,organization_id,sku,display_name,family) VALUES(product,org,'TEST','Regular','regular');
  INSERT INTO branch_fuel_offers(organization_id,branch_id,fuel_product_id,created_by) VALUES(org,branch,product,actor);
  INSERT INTO tanks(id,organization_id,branch_id,code,name,fuel_product_id,nominal_capacity_l,safe_fill_limit_l) VALUES(tank,org,branch,'T1','Tank',product,1000,900);
  INSERT INTO dispensers(id,organization_id,branch_id,code) VALUES(dispenser,org,branch,'D1');
  INSERT INTO nozzles(id,organization_id,branch_id,dispenser_id,code,product_code,fuel_product_id,service_mode) VALUES(nozzle,org,branch,dispenser,'N1','REG',product,'full_service');
  INSERT INTO branch_operating_profiles(branch_id,organization_id,profile,expected_dispenser_count) VALUES(branch,org,'academicLab22',6);
  INSERT INTO tank_inventory_balances(tank_id,organization_id,branch_id,fuel_product_id,on_hand_l,valuation_quality) VALUES(tank,org,branch,product,100,'unknown');
  INSERT INTO inventory_movements(organization_id,branch_id,tank_id,fuel_product_id,movement_type,command_id,request_hash,source_type,quantity_entered,unit_entered,conversion_factor_to_l,observed_l,delta_l,volume_basis,valuation_quality,before_quantity_l,after_quantity_l,actor_user_id,correlation_id)
   VALUES(org,branch,tank,product,'opening',gen_random_uuid(),repeat('a',64),'opening_balance',100,'liter',1,100,100,'observed','unknown',0,100,actor,gen_random_uuid());
  INSERT INTO fuel_price_proposals(id,organization_id,branch_id,fuel_product_id,service_mode,proposed_price_usd_per_unit,unit,effective_at,reason,created_by)
   VALUES(proposal,org,branch,product,'full_service',4,'us_gallon',now(),'Transient check',actor);
  UPDATE fuel_price_proposals SET status='approved',approved_by=approver WHERE id=proposal;
  INSERT INTO fuel_price_versions(id,organization_id,branch_id,fuel_product_id,service_mode,version,price_usd_per_unit,unit,effective_at,proposal_id,created_by)
   VALUES(price,org,branch,product,'full_service',1,4,'us_gallon',now(),proposal,approver);
  INSERT INTO dispense_authorizations(id,organization_id,branch_id,nozzle_id,tank_id,fuel_product_id,price_version_id,service_mode,requested_by,command_id,request_hash,request_type,requested_volume,requested_volume_unit,reserved_l,price_usd_per_unit,price_unit,expires_at)
   VALUES(auth_id,org,branch,nozzle,tank,product,price,'full_service',actor,gen_random_uuid(),repeat('b',64),'volume',10,'liter',10,4,'us_gallon',now()+interval '10 minutes');
  INSERT INTO cash_registers(id,organization_id,branch_id,code,created_by) VALUES(register_id,org,branch,'REG1',actor);
  INSERT INTO cash_sessions(id,organization_id,branch_id,register_id,cashier_id,opening_usd,command_id,request_hash,correlation_id)
   VALUES(session_id,org,branch,register_id,actor,100,gen_random_uuid(),repeat('c',64),gen_random_uuid());
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO prepayment_advances(id,organization_id,branch_id,authorization_id,method,mode,tender_kind,outcome,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
   VALUES(advance_id,org,branch,auth_id,'cash','manual','captured','confirmed',20,session_id,gen_random_uuid(),repeat('d',64),actor,gen_random_uuid());
  INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,amount_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,advance_id,'received',20,gen_random_uuid(),repeat('e',64),actor,gen_random_uuid());
  IF (SELECT count(*) FROM cash_movements m WHERE m.advance_id=fixture.advance_id AND m.delta_usd=20)<>1 THEN RAISE EXCEPTION 'Cash advance did not post exactly once'; END IF;
  INSERT INTO prepayment_advances(id,organization_id,branch_id,authorization_id,method,mode,tender_kind,outcome,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
   VALUES(unknown_id,org,branch,auth_id,'cash','manual','captured','unknown',8,session_id,gen_random_uuid(),repeat('f',64),actor,gen_random_uuid());
  IF EXISTS(SELECT 1 FROM cash_movements m WHERE m.advance_id=unknown_id) THEN RAISE EXCEPTION 'Unknown advance posted cash'; END IF;
  BEGIN
   INSERT INTO cash_closures(organization_id,branch_id,session_id,counted_cash_usd,settled_card_usd,expected_cash_usd,expected_card_usd,variance_cash_usd,variance_card_usd,review_status,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,session_id,120,0,0,0,0,0,'balanced',gen_random_uuid(),repeat('1',64),actor,gen_random_uuid());
   RAISE EXCEPTION 'Unknown advance was allowed to close cash';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,outcome,outcome_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,unknown_id,'outcomeResolved','declined','DECLINED-8',gen_random_uuid(),repeat('2',64),actor,gen_random_uuid());
  INSERT INTO prepayment_advances(id,organization_id,branch_id,authorization_id,method,mode,tender_kind,outcome,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
   VALUES(confirmed_later_id,org,branch,auth_id,'cash','manual','captured','unknown',3,session_id,gen_random_uuid(),repeat('2',64),actor,gen_random_uuid());
  INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,outcome,outcome_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,confirmed_later_id,'outcomeResolved','confirmed','CONFIRMED-3',gen_random_uuid(),repeat('2',64),actor,gen_random_uuid());
  IF (SELECT count(*) FROM cash_movements m WHERE m.advance_id=confirmed_later_id AND m.delta_usd=3)<>1 THEN RAISE EXCEPTION 'Resolved cash advance did not post exactly once'; END IF;
  RESET ROLE;
  INSERT INTO inventory_movements(id,organization_id,branch_id,tank_id,fuel_product_id,movement_type,command_id,request_hash,source_type,source_id,quantity_entered,unit_entered,conversion_factor_to_l,observed_l,delta_l,volume_basis,valuation_quality,unit_cost_usd_per_l,cost_recognized_usd,before_quantity_l,after_quantity_l,actor_user_id,correlation_id)
   VALUES(movement,org,branch,tank,product,'sale',gen_random_uuid(),repeat('3',64),'dispense_session',auth_id::text,10,'liter',1,10,-10,'observed','known',0.5,5,100,90,actor,gen_random_uuid());
  UPDATE dispense_authorizations SET status='completed',actual_l=10,sale_amount_usd=10.57,inventory_movement_id=movement,completed_at=now() WHERE id=auth_id;
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO sales(id,organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id)
   VALUES(sale_id,org,branch,auth_id,gen_random_uuid(),repeat('4',64),10.57,actor,now(),gen_random_uuid());
  INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,fuel_product_id,description,quantity_l,price_usd_per_unit,price_unit,price_version_id,total_usd,inventory_movement_id,cost_usd,unit_cost_usd_per_l,cost_quality)
   VALUES(org,branch,sale_id,1,product,'Regular',10,4,'us_gallon',price,10.57,movement,5,0.5,'known');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO prepayment_allocations(id,organization_id,branch_id,advance_id,sale_id,amount_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(allocation_id,org,branch,advance_id,sale_id,10.57,gen_random_uuid(),repeat('5',64),actor,gen_random_uuid());
  INSERT INTO prepayment_events(organization_id,branch_id,advance_id,allocation_id,event_type,amount_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,advance_id,allocation_id,'allocated',10.57,gen_random_uuid(),repeat('6',64),actor,gen_random_uuid());
  IF (SELECT b.collected_usd FROM sale_collection_balances b WHERE b.id=sale_id)<>10.57 THEN RAISE EXCEPTION 'Allocation did not pay the sale'; END IF;
  IF (SELECT r.remaining_usd FROM prepayment_residuals r WHERE r.advance_id=fixture.advance_id)<>9.43 THEN RAISE EXCEPTION 'Remainder incorrect'; END IF;
  BEGIN
   INSERT INTO payment_attempts(organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,sale_id,'cash','manual',0.01,session_id,gen_random_uuid(),repeat('7',64),actor,gen_random_uuid());
   RAISE EXCEPTION 'Paid sale accepted another attempt';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,disposition,amount_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,advance_id,'refundPending','refund',9.43,gen_random_uuid(),repeat('8',64),actor,gen_random_uuid());
  INSERT INTO approval_requests(id,organization_id,branch_id,action,entity_type,entity_id,requested_by,decided_by,status,payload)
   VALUES(approval_id,org,branch,'sale.refund.approve','payment_refund',advance_id::text,actor,approver,'approved','{"amountUsd":"9.43","reason":"Remainder"}');
  INSERT INTO payment_refunds(id,approval_id,organization_id,branch_id,advance_id,amount_usd,cash_session_id,evidence_reference,reason,command_id,request_hash,created_by,correlation_id)
   VALUES(refund_id,approval_id,org,branch,advance_id,9.43,session_id,'RECEIPT-9-43','Remainder',gen_random_uuid(),repeat('9',64),actor,gen_random_uuid());
  INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,disposition,amount_usd,confirmation_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,advance_id,'refunded','refund',9.43,'RECEIPT-9-43',gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());
  IF (SELECT count(*) FROM cash_movements m WHERE m.refund_id=fixture.refund_id AND m.delta_usd=-9.43)<>1 THEN RAISE EXCEPTION 'Cash refund not posted'; END IF;
  IF (SELECT 100+coalesce(sum(m.delta_usd),0) FROM cash_movements m WHERE m.session_id=fixture.session_id)<>113.57 THEN RAISE EXCEPTION 'Cash balance wrong'; END IF;
  IF (SELECT b.refunded_usd FROM sale_collection_balances b WHERE b.id=sale_id)<>0 THEN RAISE EXCEPTION 'Advance refund changed sale refund total'; END IF;
  INSERT INTO prepayment_advances(id,organization_id,branch_id,authorization_id,method,mode,tender_kind,outcome,amount_usd,cash_session_id,evidence_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(hold_id,org,branch,auth_id,'card','manual','authorization_hold','confirmed',15,session_id,'HOLD-15',gen_random_uuid(),repeat('b',64),actor,gen_random_uuid());
  INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,amount_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,hold_id,'received',15,gen_random_uuid(),repeat('c',64),actor,gen_random_uuid());
  IF EXISTS(SELECT 1 FROM cash_movements m WHERE m.advance_id=hold_id) THEN RAISE EXCEPTION 'Card hold posted cash'; END IF;
  INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,disposition,amount_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,hold_id,'refundPending','release',15,gen_random_uuid(),repeat('d',64),actor,gen_random_uuid());
  INSERT INTO prepayment_events(organization_id,branch_id,advance_id,event_type,disposition,amount_usd,confirmation_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,hold_id,'released','release',15,'RELEASE-15',gen_random_uuid(),repeat('e',64),actor,gen_random_uuid());
  IF (SELECT r.residual_state FROM prepayment_residuals r WHERE r.advance_id=hold_id)<>'released' THEN RAISE EXCEPTION 'Release state not derived'; END IF;
  IF has_table_privilege('anon','prepayment_advances','SELECT') OR has_table_privilege('authenticated','prepayment_events','INSERT') THEN RAISE EXCEPTION 'Public prepayment access'; END IF;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Synthetic fixture persisted'; END IF;
END $test$;
