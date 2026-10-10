DO $tests$
DECLARE org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); other_actor uuid:=gen_random_uuid();
 reg uuid:=gen_random_uuid(); session uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); offer uuid:=gen_random_uuid(); sale uuid;
 cash_attempt uuid:=gen_random_uuid(); card_attempt uuid:=gen_random_uuid(); cash_event uuid:=gen_random_uuid(); card_event uuid:=gen_random_uuid();
 pending_attempt uuid:=gen_random_uuid(); unknown_event uuid:=gen_random_uuid(); second_sale uuid; second_session uuid:=gen_random_uuid(); sim_attempt uuid:=gen_random_uuid(); card_approval uuid:=gen_random_uuid();
 approval uuid:=gen_random_uuid(); excess_approval uuid:=gen_random_uuid(); result jsonb:='[]'; n bigint; closure uuid:=gen_random_uuid();
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(org,'Payment transient');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(branch,org,'PAYTEST','Pay test','occidental','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash) VALUES
   (actor,org,actor::text||'@example.invalid','Cashier','NOT_A_LOGIN_HASH'),(other_actor,org,other_actor::text||'@example.invalid','Other','NOT_A_LOGIN_HASH');
  INSERT INTO pos_products(id,organization_id,branch_id,sku,kind,expiry_required,created_by) VALUES(product,org,branch,'SERVICE','service',false,actor);
  INSERT INTO pos_offer_versions(id,organization_id,branch_id,product_id,version,description,active,price_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(offer,org,branch,product,1,'Service',true,280,gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());
  SET LOCAL ROLE dlc_api_runtime;
  sale:=post_pos_sale(org,branch,actor,gen_random_uuid(),repeat('b',64),jsonb_build_array(jsonb_build_object('productId',product,'offerVersionId',offer,'quantity','1')),gen_random_uuid());
  second_sale:=post_pos_sale(org,branch,actor,gen_random_uuid(),repeat('c',64),jsonb_build_array(jsonb_build_object('productId',product,'offerVersionId',offer,'quantity','1')),gen_random_uuid());
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO cash_registers(id,organization_id,branch_id,code,created_by) VALUES(reg,org,branch,'REG1',actor);
  INSERT INTO cash_sessions(id,organization_id,branch_id,register_id,cashier_id,opening_usd,command_id,request_hash,correlation_id)
   VALUES(session,org,branch,reg,actor,100,gen_random_uuid(),repeat('d',64),gen_random_uuid());
  BEGIN
   INSERT INTO cash_sessions(organization_id,branch_id,register_id,cashier_id,opening_usd,command_id,request_hash,correlation_id)
    VALUES(org,branch,reg,other_actor,0,gen_random_uuid(),repeat('d',64),gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','one_open_session_per_register','result','PASS');END;
  INSERT INTO payment_attempts(id,organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
   VALUES(cash_attempt,org,branch,sale,'cash','manual',200,session,gen_random_uuid(),repeat('e',64),actor,gen_random_uuid());
  INSERT INTO payment_events(id,organization_id,branch_id,attempt_id,outcome,command_id,request_hash,created_by,correlation_id)
   VALUES(cash_event,org,branch,cash_attempt,'confirmed',gen_random_uuid(),repeat('e',64),actor,gen_random_uuid());
  IF (SELECT sum(delta_usd) FROM cash_movements WHERE session_id=session)<>200 THEN RAISE EXCEPTION 'Cash missing'; END IF;
  result:=result||jsonb_build_object('test','cash_confirmation_posts_one_movement','result','PASS');
  IF (SELECT collection_status FROM sale_collection_balances WHERE id=sale)<>'pending_collection' THEN RAISE EXCEPTION 'Partial paid incorrectly'; END IF;
  result:=result||jsonb_build_object('test','partial_payment_keeps_balance','result','PASS');
  BEGIN
   INSERT INTO payment_events(organization_id,branch_id,attempt_id,outcome,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,cash_attempt,'confirmed',gen_random_uuid(),repeat('e',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','terminal_payment_cannot_confirm_twice','result','PASS');END;
  BEGIN
   INSERT INTO payment_attempts(organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,sale,'cash','manual',81,session,gen_random_uuid(),repeat('e',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','overcollection_rejected','result','PASS');END;
  BEGIN
   INSERT INTO payment_attempts(organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,sale,'cash','manual',80,session,gen_random_uuid(),repeat('e',64),other_actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','foreign_cashier_session_rejected','result','PASS');END;
  INSERT INTO payment_attempts(id,organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
   VALUES(card_attempt,org,branch,sale,'card','manual',80,session,gen_random_uuid(),repeat('f',64),actor,gen_random_uuid());
  BEGIN
   INSERT INTO payment_events(organization_id,branch_id,attempt_id,outcome,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,card_attempt,'confirmed',gen_random_uuid(),repeat('f',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','card_confirmation_requires_evidence','result','PASS');END;
  INSERT INTO payment_events(id,organization_id,branch_id,attempt_id,outcome,evidence_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(card_event,org,branch,card_attempt,'confirmed','TERMINAL-80',gen_random_uuid(),repeat('f',64),actor,gen_random_uuid());
  IF (SELECT sum(delta_usd) FROM cash_movements WHERE session_id=session)<>200 THEN RAISE EXCEPTION 'Card in cash'; END IF;
  result:=result||jsonb_build_object('test','card_does_not_add_cash','result','PASS');
  IF (SELECT collection_status FROM sale_collection_balances WHERE id=sale)<>'paid' THEN RAISE EXCEPTION 'Mixed not paid'; END IF;
  result:=result||jsonb_build_object('test','mixed_payment_pays_exact_total','result','PASS');
  INSERT INTO approval_requests(id,organization_id,branch_id,action,entity_type,entity_id,requested_by,decided_by,status,payload) VALUES
   (approval,org,branch,'sale.refund.approve','payment_refund',cash_event::text,actor,other_actor,'approved','{"amountUsd":"30.00","reason":"Correction"}'),
   (excess_approval,org,branch,'sale.refund.approve','payment_refund',cash_event::text,actor,other_actor,'approved','{"amountUsd":"171.00","reason":"Too much"}');
  SELECT count(*) INTO n FROM inventory_movements WHERE organization_id=org;
  INSERT INTO payment_refunds(approval_id,organization_id,branch_id,payment_event_id,amount_usd,cash_session_id,reason,command_id,request_hash,created_by,correlation_id)
   VALUES(approval,org,branch,cash_event,30.00,session,'Correction',gen_random_uuid(),repeat('1',64),actor,gen_random_uuid());
  IF (SELECT count(*) FROM inventory_movements WHERE organization_id=org)<>n THEN RAISE EXCEPTION 'Refund stock mutation'; END IF;
  result:=result||jsonb_build_object('test','financial_refund_never_returns_fuel','result','PASS');
  IF (SELECT refund_status FROM sale_collection_balances WHERE id=sale)<>'partial' OR (SELECT outstanding_usd FROM sale_collection_balances WHERE id=sale)<>0 THEN RAISE EXCEPTION 'Refund reopened debt'; END IF;
  result:=result||jsonb_build_object('test','refund_does_not_reopen_sale_debt','result','PASS');
  BEGIN
   INSERT INTO payment_refunds(approval_id,organization_id,branch_id,payment_event_id,amount_usd,cash_session_id,reason,command_id,request_hash,created_by,correlation_id)
    VALUES(excess_approval,org,branch,cash_event,171.00,session,'Too much',gen_random_uuid(),repeat('2',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','refund_cannot_exceed_original_net','result','PASS');END;
  INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,reason,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,session,'deposit',-50,'Bank deposit',gen_random_uuid(),repeat('3',64),actor,gen_random_uuid());
  IF (SELECT 100+sum(delta_usd) FROM cash_movements WHERE session_id=session)<>220 THEN RAISE EXCEPTION 'V05 failed'; END IF;
  result:=result||jsonb_build_object('test','V05_100_plus_200_minus_30_minus_50_equals_220','result','PASS');
  BEGIN
   INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,reason,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,session,'withdrawal',-221,'Excess',gen_random_uuid(),repeat('3',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','cash_outflow_cannot_exceed_balance','result','PASS');END;
  INSERT INTO payment_attempts(id,organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
   VALUES(pending_attempt,org,branch,second_sale,'card','manual',280,session,gen_random_uuid(),repeat('4',64),actor,gen_random_uuid());
  INSERT INTO payment_events(id,organization_id,branch_id,attempt_id,outcome,command_id,request_hash,created_by,correlation_id)
   VALUES(unknown_event,org,branch,pending_attempt,'unknown',gen_random_uuid(),repeat('4',64),actor,gen_random_uuid());
  BEGIN
   INSERT INTO payment_attempts(organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,second_sale,'card','manual',1,session,gen_random_uuid(),repeat('4',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','unknown_attempt_reserves_balance','result','PASS');END;
  BEGIN
   INSERT INTO cash_closures(organization_id,branch_id,session_id,counted_cash_usd,settled_card_usd,expected_cash_usd,expected_card_usd,variance_cash_usd,variance_card_usd,review_status,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,session,220,80,0,0,0,0,'balanced',gen_random_uuid(),repeat('5',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','unknown_payment_blocks_cash_closure','result','PASS');END;
  INSERT INTO payment_events(organization_id,branch_id,attempt_id,outcome,evidence_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,pending_attempt,'declined','TERMINAL-CANCELLED',gen_random_uuid(),repeat('4',64),actor,gen_random_uuid());
  IF (SELECT reserved_usd FROM sale_collection_balances WHERE id=second_sale)<>0 THEN RAISE EXCEPTION 'Declined reservation retained'; END IF;
  result:=result||jsonb_build_object('test','documented_decline_releases_reservation','result','PASS');
  INSERT INTO cash_closures(id,organization_id,branch_id,session_id,counted_cash_usd,settled_card_usd,expected_cash_usd,expected_card_usd,variance_cash_usd,variance_card_usd,review_status,command_id,request_hash,created_by,correlation_id)
   VALUES(closure,org,branch,session,220,80,999,999,999,999,'pending_review',gen_random_uuid(),repeat('5',64),actor,gen_random_uuid());
  IF NOT EXISTS(SELECT 1 FROM cash_closures WHERE id=closure AND expected_cash_usd=220 AND expected_card_usd=80 AND variance_cash_usd=0 AND variance_card_usd=0 AND review_status='balanced') THEN RAISE EXCEPTION 'Closure trusted client totals'; END IF;
  result:=result||jsonb_build_object('test','closure_recomputes_authoritative_cash_and_card','result','PASS');
  BEGIN
   INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,reason,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,session,'cash_in',1,'Late',gen_random_uuid(),repeat('6',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','closed_session_rejects_movement','result','PASS');END;
  INSERT INTO cash_sessions(id,organization_id,branch_id,register_id,cashier_id,opening_usd,command_id,request_hash,correlation_id)
   VALUES(second_session,org,branch,reg,actor,0,gen_random_uuid(),repeat('6',64),gen_random_uuid());
  result:=result||jsonb_build_object('test','closed_register_can_open_next_session','result','PASS');
  BEGIN
   UPDATE payment_attempts SET amount_usd=1 WHERE id=cash_attempt;RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN insufficient_privilege THEN result:=result||jsonb_build_object('test','runtime_cannot_rewrite_payment','result','PASS');END;
  IF has_table_privilege('anon','payment_attempts','SELECT') OR has_table_privilege('authenticated','cash_movements','INSERT') OR has_function_privilege('anon','lock_owned_open_cash(uuid,uuid,uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Public access'; END IF;
  result:=result||jsonb_build_object('test','no_public_payment_or_cash_access','result','PASS');
  BEGIN
   INSERT INTO payment_attempts(organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,second_sale,'card','manual','NaN',second_session,gen_random_uuid(),repeat('7',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','numeric_nan_rejected_at_database','result','PASS');END;
  BEGIN
   INSERT INTO payment_attempts(organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,second_sale,'card','manual',1.001,second_session,gen_random_uuid(),repeat('7',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','fractional_cent_rejected_before_rounding','result','PASS');END;
  BEGIN
   INSERT INTO payment_refunds(approval_id,organization_id,branch_id,payment_event_id,amount_usd,cash_session_id,reason,command_id,request_hash,created_by,correlation_id)
    VALUES(approval,org,branch,cash_event,30.00,second_session,'Correction',gen_random_uuid(),repeat('7',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN unique_violation THEN result:=result||jsonb_build_object('test','one_approval_cannot_execute_two_refunds','result','PASS');END;
  INSERT INTO approval_requests(id,organization_id,branch_id,action,entity_type,entity_id,requested_by,payload)
   VALUES(card_approval,org,branch,'sale.refund.approve','payment_refund',card_event::text,actor,'{"amountUsd":"5.00","reason":"Card correction"}');
  BEGIN
   INSERT INTO payment_refunds(approval_id,organization_id,branch_id,payment_event_id,amount_usd,cash_session_id,evidence_reference,reason,command_id,request_hash,created_by,correlation_id)
    VALUES(card_approval,org,branch,card_event,5.00,second_session,'TERMINAL-R5','Card correction',gen_random_uuid(),repeat('8',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','unapproved_refund_rejected','result','PASS');END;
  UPDATE approval_requests SET status='approved',decided_by=other_actor,decided_at=clock_timestamp() WHERE id=card_approval;
  INSERT INTO payment_refunds(approval_id,organization_id,branch_id,payment_event_id,amount_usd,cash_session_id,evidence_reference,reason,command_id,request_hash,created_by,correlation_id)
   VALUES(card_approval,org,branch,card_event,5.00,second_session,'TERMINAL-R5','Card correction',gen_random_uuid(),repeat('8',64),actor,gen_random_uuid());
  IF EXISTS(SELECT 1 FROM cash_movements WHERE session_id=second_session) THEN RAISE EXCEPTION 'Card refund converted to cash'; END IF;
  result:=result||jsonb_build_object('test','card_refund_does_not_withdraw_cash','result','PASS');
  INSERT INTO payment_attempts(id,organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
   VALUES(sim_attempt,org,branch,second_sale,'card','simulated',20,second_session,gen_random_uuid(),repeat('9',64),actor,gen_random_uuid());
  INSERT INTO payment_events(organization_id,branch_id,attempt_id,outcome,evidence_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,sim_attempt,'confirmed','SIMULATED:test',gen_random_uuid(),repeat('9',64),actor,gen_random_uuid());
  IF (SELECT collected_usd FROM sale_collection_balances WHERE id=second_sale)<>0 THEN RAISE EXCEPTION 'Simulator recognized real money'; END IF;
  result:=result||jsonb_build_object('test','simulated_confirmation_is_not_real_collection','result','PASS');
  BEGIN
   INSERT INTO payment_attempts(id,organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
    VALUES(gen_random_uuid(),org,branch,second_sale,'card','manual',1,second_session,gen_random_uuid(),repeat('b',64),actor,gen_random_uuid());
   INSERT INTO payment_events(organization_id,branch_id,attempt_id,outcome,evidence_reference,command_id,request_hash,created_by,correlation_id)
    SELECT org,branch,a.id,'confirmed','TERMINAL-80',gen_random_uuid(),repeat('b',64),actor,gen_random_uuid() FROM payment_attempts a WHERE a.sale_id=second_sale AND a.amount_usd=1;
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN unique_violation THEN result:=result||jsonb_build_object('test','same_terminal_confirmation_cannot_pay_another_attempt','result','PASS');END;
  BEGIN
   INSERT INTO cash_closures(organization_id,branch_id,session_id,counted_cash_usd,settled_card_usd,expected_cash_usd,expected_card_usd,variance_cash_usd,variance_card_usd,review_status,command_id,request_hash,created_by,correlation_id)
    VALUES(org,branch,second_session,1,-5,0,0,0,0,'balanced',gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','closure_discrepancy_requires_reason','result','PASS');END;
  INSERT INTO cash_closures(organization_id,branch_id,session_id,counted_cash_usd,settled_card_usd,expected_cash_usd,expected_card_usd,variance_cash_usd,variance_card_usd,review_status,reason,command_id,request_hash,created_by,correlation_id)
   VALUES(org,branch,second_session,1,-5,0,0,0,0,'balanced','One extra dollar',gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());
  IF NOT EXISTS(SELECT 1 FROM cash_closures WHERE session_id=second_session AND expected_card_usd=-5 AND expected_cash_usd=0 AND variance_cash_usd=1 AND review_status='pending_review') THEN RAISE EXCEPTION 'Discrepancy automatically approved'; END IF;
  result:=result||jsonb_build_object('test','variance_stays_pending_review_without_invented_limit','result','PASS');
  IF (SELECT expected_card_usd FROM cash_closures WHERE id=closure)<>80 THEN RAISE EXCEPTION 'Refund rewrote old closure'; END IF;
  result:=result||jsonb_build_object('test','later_refund_does_not_rewrite_previous_closure','result','PASS');
  RAISE EXCEPTION 'rollback fixtures' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org) THEN RAISE EXCEPTION 'Fixtures retained'; END IF;
 PERFORM set_config('dlc.test_results',result::text,false);
END $tests$;
SELECT current_setting('dlc.test_results')::jsonb AS tests;
