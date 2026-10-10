BEGIN;
DO $tests$
DECLARE
 org uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); cashier uuid:=gen_random_uuid(); checker uuid:=gen_random_uuid();
 customer uuid:=gen_random_uuid(); program uuid:=gen_random_uuid(); register_id uuid:=gen_random_uuid(); v_session_id uuid:=gen_random_uuid();
 product uuid:=gen_random_uuid(); offer uuid:=gen_random_uuid(); sale uuid; quote uuid:=gen_random_uuid(); payment uuid:=gen_random_uuid();
 attempt uuid:=gen_random_uuid(); event_id uuid:=gen_random_uuid(); approval uuid:=gen_random_uuid(); refunded uuid:=gen_random_uuid();
 point_request uuid:=gen_random_uuid(); point_refunded numeric;
 balance bigint; status text; cash numeric; result jsonb:='[]';
BEGIN
 INSERT INTO organizations(id,name) VALUES(org,'Point payment transient');
 INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(branch,org,'POINTQA','Point QA','occidental','active');
 INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status) VALUES
   (cashier,org,cashier::text||'@example.invalid','Cashier','NOT_A_LOGIN_HASH','active'),
   (checker,org,checker::text||'@example.invalid','Checker','NOT_A_LOGIN_HASH','active');
 INSERT INTO customer_accounts(id,organization_id,auth_user_id,email_normalized,full_name,terms_version)
   VALUES(customer,org,gen_random_uuid(),customer::text||'@example.invalid','QA Customer','qa-v1');
 INSERT INTO customer_loyalty_programs(id,organization_id,version,status,points_per_eligible_usd,minimum_eligible_usd,
   policy,approved_by,approved_at,created_by,command_id,request_hash,submitted_by,submitted_at,decision_by,decision_at,redemption_usd_per_point)
   VALUES(program,org,1,'active',1,0,'{}',checker,now(),cashier,gen_random_uuid(),repeat('a',64),cashier,now(),checker,now(),0.01);
 INSERT INTO pos_products(id,organization_id,branch_id,sku,kind,expiry_required,created_by)
   VALUES(product,org,branch,'POINT-SERVICE','service',false,cashier);
 INSERT INTO pos_offer_versions(id,organization_id,branch_id,product_id,version,description,active,price_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(offer,org,branch,product,1,'QA service',true,10,gen_random_uuid(),repeat('b',64),cashier,gen_random_uuid());
 INSERT INTO cash_registers(id,organization_id,branch_id,code,created_by) VALUES(register_id,org,branch,'POINTQA',cashier);
 SET LOCAL ROLE dlc_api_runtime;
 sale:=post_pos_sale(org,branch,cashier,gen_random_uuid(),repeat('c',64),
   jsonb_build_array(jsonb_build_object('productId',product,'offerVersionId',offer,'quantity','1')),gen_random_uuid());
 INSERT INTO customer_sale_links(organization_id,branch_id,sale_id,customer_id,command_id,request_hash,linked_by)
   VALUES(org,branch,sale,customer,gen_random_uuid(),repeat('d',64),cashier);
 INSERT INTO cash_sessions(id,organization_id,branch_id,register_id,cashier_id,opening_usd,command_id,request_hash,correlation_id)
   VALUES(v_session_id,org,branch,register_id,cashier,0,gen_random_uuid(),repeat('e',64),gen_random_uuid());
 INSERT INTO customer_points_ledger(organization_id,customer_id,program_id,event_type,points_delta,source_type,source_id,command_id,reason,created_by)
   VALUES(org,customer,program,'earn',500,'qa_seed',gen_random_uuid(),gen_random_uuid(),'QA seed',cashier);
 INSERT INTO customer_point_payment_quotes(id,organization_id,branch_id,sale_id,customer_id,cash_session_id,program_id,
   points,amount_usd,redemption_usd_per_point,expires_at,command_id,request_hash,requested_by)
   VALUES(quote,org,branch,sale,customer,v_session_id,program,500,5,0.01,now()+interval '120 seconds',gen_random_uuid(),repeat('f',64),cashier);
 INSERT INTO customer_point_payments(id,organization_id,branch_id,sale_id,customer_id,quote_id,program_id,points,
   amount_usd,redemption_usd_per_point,command_id,request_hash)
   VALUES(payment,org,branch,sale,customer,quote,program,500,5,0.01,gen_random_uuid(),repeat('1',64));
 INSERT INTO customer_points_ledger(organization_id,customer_id,program_id,event_type,points_delta,source_type,source_id,command_id,reason)
   VALUES(org,customer,program,'redeem',-500,'sale_point_payment',payment,gen_random_uuid(),'QA point tender');
 UPDATE customer_point_payment_quotes SET status='confirmed',confirmed_at=now(),decision_command_id=gen_random_uuid(),
   decision_hash=repeat('2',64),decided_by_customer_id=customer WHERE id=quote;
 INSERT INTO payment_attempts(id,organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
   VALUES(attempt,org,branch,sale,'cash','manual',5,v_session_id,gen_random_uuid(),repeat('3',64),cashier,gen_random_uuid());
 INSERT INTO payment_events(id,organization_id,branch_id,attempt_id,outcome,command_id,request_hash,created_by,correlation_id)
   VALUES(event_id,org,branch,attempt,'confirmed',gen_random_uuid(),repeat('4',64),cashier,gen_random_uuid());
 SELECT coalesce(sum(points_delta),0) INTO balance FROM customer_points_ledger WHERE organization_id=org AND customer_id=customer;
 SELECT collection_status INTO status FROM sale_collection_balances WHERE id=sale;
 SELECT coalesce(sum(cm.delta_usd),0) INTO cash FROM cash_movements cm WHERE cm.session_id=v_session_id;
 IF status<>'paid' OR balance<>5 OR cash<>5 THEN RAISE EXCEPTION 'Mixed points/cash tender invariant failed: status %, points %, cash %',status,balance,cash; END IF;
 result:=result||jsonb_build_object('test','mixed_points_cash_posts_one_tender_and_only_cash_to_drawer','result','PASS');

 RESET ROLE;
 INSERT INTO approval_requests(id,organization_id,branch_id,action,entity_type,entity_id,requested_by,decided_by,status,payload)
   VALUES(approval,org,branch,'sale.refund.approve','payment_refund',event_id::text,cashier,checker,'approved','{"amountUsd":"2.50","reason":"QA partial refund"}');
 SET LOCAL ROLE dlc_api_runtime;
 INSERT INTO payment_refunds(id,approval_id,organization_id,branch_id,payment_event_id,amount_usd,cash_session_id,reason,command_id,request_hash,created_by,correlation_id)
   VALUES(refunded,approval,org,branch,event_id,2.50,v_session_id,'QA partial refund',gen_random_uuid(),repeat('5',64),cashier,gen_random_uuid());
 SELECT coalesce(sum(points_delta),0) INTO balance FROM customer_points_ledger WHERE organization_id=org AND customer_id=customer;
 IF balance<>3 OR NOT EXISTS(SELECT 1 FROM customer_points_ledger WHERE source_type='sale_refund' AND source_id=refunded AND points_delta=-2)
 THEN RAISE EXCEPTION 'Proportional earned-points reversal failed: %',balance; END IF;
 result:=result||jsonb_build_object('test','partial_money_refund_reverses_earned_points_proportionally','result','PASS');

 BEGIN
  INSERT INTO customer_point_payment_quotes(organization_id,branch_id,sale_id,customer_id,cash_session_id,program_id,
    points,amount_usd,redemption_usd_per_point,expires_at,command_id,request_hash,requested_by)
    VALUES(org,branch,sale,customer,v_session_id,program,1,0.01,0.01,now()+interval '120 seconds',gen_random_uuid(),repeat('6',64),cashier);
  RAISE EXCEPTION 'Expected quote against paid sale to fail' USING ERRCODE='Z0002';
 EXCEPTION WHEN check_violation THEN result:=result||jsonb_build_object('test','paid_sale_cannot_receive_new_points_quote','result','PASS'); END;
 INSERT INTO customer_point_refund_requests(id,organization_id,branch_id,payment_id,points,requested_by,command_id,reason)
 VALUES(point_request,org,branch,payment,500,cashier,gen_random_uuid(),'Devolución total de puntos QA');
 BEGIN
  INSERT INTO customer_point_refund_decisions(organization_id,branch_id,request_id,decision,decided_by,command_id,reason)
  VALUES(org,branch,point_request,'approved',cashier,gen_random_uuid(),'Autoaprobación debe fallar');
  RAISE EXCEPTION 'Expected maker checker rejection' USING ERRCODE='Z0002';
 EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO customer_point_refund_decisions(organization_id,branch_id,request_id,decision,decided_by,command_id,reason)
 VALUES(org,branch,point_request,'approved',checker,gen_random_uuid(),'Aprobación independiente QA');
 SELECT coalesce(sum(points_delta),0) INTO balance FROM customer_points_ledger WHERE organization_id=org AND customer_id=customer;
 IF balance<>503 THEN RAISE EXCEPTION 'Expected 503 points after point return, got %',balance; END IF;
 SELECT sum(d.amount_usd) INTO point_refunded FROM customer_point_refund_decisions d JOIN customer_point_refund_requests r ON r.id=d.request_id WHERE r.payment_id=payment;
 IF point_refunded<>5 THEN RAISE EXCEPTION 'Expected exact 5 USD point refund, got %',point_refunded; END IF;
 BEGIN
  INSERT INTO customer_point_refund_requests(organization_id,branch_id,payment_id,points,requested_by,command_id,reason)
  VALUES(org,branch,payment,1,cashier,gen_random_uuid(),'Debe rechazar doble devolución');
  RAISE EXCEPTION 'Expected over-refund rejection' USING ERRCODE='Z0002';
 EXCEPTION WHEN check_violation THEN NULL; END;
 result:=result||jsonb_build_object('test','total_point_refund_independent_capped','result','PASS');
 RAISE NOTICE '%',result;
END;
$tests$;
ROLLBACK;
