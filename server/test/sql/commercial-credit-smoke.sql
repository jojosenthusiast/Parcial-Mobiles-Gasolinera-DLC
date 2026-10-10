DO $test$
DECLARE o uuid:=gen_random_uuid();b uuid:=gen_random_uuid();a uuid:=gen_random_uuid();reviewer uuid:=gen_random_uuid();
 customer uuid:=gen_random_uuid();buyer uuid:=gen_random_uuid();svc uuid:=gen_random_uuid();offer uuid:=gen_random_uuid();
 sale uuid;charge uuid;cashreg uuid:=gen_random_uuid();sess uuid:=gen_random_uuid();first_receipt uuid;bank_receipt uuid;second_sale uuid;
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(o,'Transient credit');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(b,o,'CR01','Credit','central','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status) VALUES
   (a,o,a::text||'@example.invalid','Cashier','NO_LOGIN','active'),
   (reviewer,o,reviewer::text||'@example.invalid','Reviewer','NO_LOGIN','active');
  INSERT INTO pos_products(id,organization_id,branch_id,sku,kind,created_by) VALUES(svc,o,b,'WASH','service',a);
  INSERT INTO pos_offer_versions(id,organization_id,branch_id,product_id,version,description,active,price_usd,service_unit_cost_usd,command_id,request_hash,created_by,correlation_id)
   VALUES(offer,o,b,svc,1,'Lavado',true,10,4,gen_random_uuid(),repeat('a',64),a,gen_random_uuid());
  INSERT INTO cash_registers(id,organization_id,branch_id,code,created_by) VALUES(cashreg,o,b,'CR01',a);
  INSERT INTO cash_sessions(id,organization_id,branch_id,register_id,cashier_id,opening_usd,command_id,request_hash,correlation_id)
   VALUES(sess,o,b,cashreg,a,0,gen_random_uuid(),repeat('b',64),gen_random_uuid());
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO commercial_customers(id,organization_id,code,legal_name,credit_limit_usd,terms_days,created_by)
   VALUES(customer,o,'BUS01','Cliente comercial',15,30,a);
  INSERT INTO commercial_authorized_buyers(id,organization_id,customer_id,buyer_code,full_name,created_by)
   VALUES(buyer,o,customer,'BUY01','Comprador autorizado',a);
  BEGIN
   INSERT INTO commercial_customer_events(organization_id,customer_id,kind,reason,command_id,request_hash,changed_by)
    VALUES(o,customer,'activate','Autoaprobación no permitida',gen_random_uuid(),repeat('c',64),a);
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO commercial_customer_events(organization_id,customer_id,kind,reason,command_id,request_hash,changed_by)
   VALUES(o,customer,'activate','Límite y plazo revisados',gen_random_uuid(),repeat('d',64),reviewer);
  sale:=post_pos_sale(o,b,a,gen_random_uuid(),repeat('e',64),
   jsonb_build_array(jsonb_build_object('productId',svc,'offerVersionId',offer,'quantity','1')),gen_random_uuid());
  SET CONSTRAINTS ALL IMMEDIATE;SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO commercial_credit_charges(organization_id,branch_id,customer_id,buyer_id,sale_id,amount_usd,due_on,buyer_evidence,command_id,request_hash,charged_by,correlation_id)
   SELECT o,b,customer,buyer,sale,10,(occurred_at AT TIME ZONE 'America/El_Salvador')::date+30,'Documento firmado',gen_random_uuid(),repeat('f',64),a,gen_random_uuid()
   FROM sales WHERE id=sale RETURNING id INTO charge;
  IF (SELECT collection_status FROM sale_collection_balances WHERE id=sale)<>'on_credit' THEN RAISE EXCEPTION 'Credit status missing'; END IF;
  BEGIN
   INSERT INTO payment_attempts(organization_id,branch_id,sale_id,method,mode,amount_usd,cash_session_id,command_id,request_hash,created_by,correlation_id)
    VALUES(o,b,sale,'cash','manual',10,sess,gen_random_uuid(),repeat('1',64),a,gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO commercial_credit_receipts(organization_id,branch_id,charge_id,amount_usd,method,cash_session_id,evidence_reference,
   command_id,request_hash,recorded_by,correlation_id)
  VALUES(o,b,charge,6,'cash',sess,'CASH-01',gen_random_uuid(),repeat('2',64),a,gen_random_uuid()) RETURNING id INTO first_receipt;
  IF (SELECT outstanding_usd FROM commercial_account_statement WHERE id=charge)<>4
   OR (SELECT sum(delta_usd) FROM cash_movements WHERE credit_receipt_id=first_receipt)<>6
   OR (SELECT count(*) FROM sales WHERE organization_id=o)<>1
  THEN RAISE EXCEPTION 'Partial receipt or cash ledger wrong'; END IF;
  BEGIN
   INSERT INTO commercial_credit_receipts(organization_id,branch_id,charge_id,amount_usd,method,cash_session_id,evidence_reference,
    command_id,request_hash,recorded_by,correlation_id)
   VALUES(o,b,charge,5,'cash',sess,'CASH-02',gen_random_uuid(),repeat('3',64),a,gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  IF (SELECT count(*) FROM cash_movements WHERE credit_receipt_id IS NOT NULL)<>1 THEN RAISE EXCEPTION 'Overpayment posted cash'; END IF;
  INSERT INTO commercial_credit_receipts(organization_id,branch_id,charge_id,amount_usd,method,evidence_reference,
   command_id,request_hash,recorded_by,correlation_id)
   VALUES(o,b,charge,4,'bank_reported','BANK-01',gen_random_uuid(),repeat('4',64),a,gen_random_uuid()) RETURNING id INTO bank_receipt;
  IF (SELECT outstanding_usd FROM commercial_account_statement WHERE id=charge)<>4
   OR (SELECT pending_bank_usd FROM commercial_account_statement WHERE id=charge)<>4
   OR (SELECT collection_status FROM sale_collection_balances WHERE id=sale)<>'on_credit'
  THEN RAISE EXCEPTION 'Unverified bank receipt was treated as settled'; END IF;
  BEGIN
   INSERT INTO commercial_bank_verifications(receipt_id,organization_id,branch_id,outcome,reason,command_id,request_hash,verified_by,correlation_id)
    VALUES(bank_receipt,o,b,'confirmed','Autoaprobación no permitida',gen_random_uuid(),repeat('5',64),a,gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO commercial_bank_verifications(receipt_id,organization_id,branch_id,outcome,reason,command_id,request_hash,verified_by,correlation_id)
   VALUES(bank_receipt,o,b,'confirmed','Transferencia conciliada con referencia',gen_random_uuid(),repeat('6',64),reviewer,gen_random_uuid());
  IF (SELECT outstanding_usd FROM commercial_account_statement WHERE id=charge)<>0
   OR (SELECT collection_status FROM sale_collection_balances WHERE id=sale)<>'paid'
   OR (SELECT count(*) FROM sales WHERE organization_id=o)<>1
  THEN RAISE EXCEPTION 'Confirmed bank receipt did not settle original sale'; END IF;
  INSERT INTO commercial_buyer_events(organization_id,customer_id,buyer_id,active,reason,command_id,request_hash,changed_by)
   VALUES(o,customer,buyer,false,'Comprador retirado del convenio',gen_random_uuid(),repeat('7',64),reviewer);
  second_sale:=post_pos_sale(o,b,a,gen_random_uuid(),repeat('8',64),
   jsonb_build_array(jsonb_build_object('productId',svc,'offerVersionId',offer,'quantity','1')),gen_random_uuid());
  SET CONSTRAINTS ALL IMMEDIATE;SET CONSTRAINTS ALL DEFERRED;
  BEGIN
   INSERT INTO commercial_credit_charges(organization_id,branch_id,customer_id,buyer_id,sale_id,amount_usd,due_on,buyer_evidence,command_id,request_hash,charged_by,correlation_id)
    SELECT o,b,customer,buyer,second_sale,10,(occurred_at AT TIME ZONE 'America/El_Salvador')::date+30,'Comprador retirado',gen_random_uuid(),repeat('9',64),a,gen_random_uuid()
    FROM sales WHERE id=second_sale;
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE EXCEPTION 'ROLLBACK' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=o) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
 RAISE NOTICE 'PASS opt-in credit, independent activation, sale lock, installment and cash';
END $test$;
