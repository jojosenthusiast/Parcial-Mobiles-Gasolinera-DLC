DO $test$
DECLARE o uuid:=gen_random_uuid();b uuid:=gen_random_uuid();cashier uuid:=gen_random_uuid();manager uuid:=gen_random_uuid();
 cat uuid:=gen_random_uuid();expense uuid:=gen_random_uuid();register_id uuid:=gen_random_uuid();session_id uuid:=gen_random_uuid();
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(o,'Transient expense');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(b,o,'EXPS','Expenses','central','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status)
  VALUES(cashier,o,cashier::text||'@example.invalid','Cashier','NO_LOGIN','active'),
   (manager,o,manager::text||'@example.invalid','Manager','NO_LOGIN','active');
  INSERT INTO cash_registers(id,organization_id,branch_id,code,created_by) VALUES(register_id,o,b,'C1',manager);
  INSERT INTO cash_sessions(id,organization_id,branch_id,register_id,cashier_id,opening_usd,command_id,request_hash,correlation_id)
  VALUES(session_id,o,b,register_id,cashier,100,gen_random_uuid(),repeat('a',64),gen_random_uuid());
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO expense_categories(id,organization_id,code,name,class,created_by)
  VALUES(cat,o,'REPAIR','Reparación','operating',manager);
  INSERT INTO expense_claims(id,organization_id,branch_id,category_id,cost_center,invoice_reference,amount_usd,incurred_on,
   source_kind,description,evidence_reference,command_id,request_hash,created_by,correlation_id)
  VALUES(expense,o,b,cat,'Pista','REPAIR-101',45,(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date,
   'other','Servicio de reparación de iluminación','doc://repair-101',gen_random_uuid(),repeat('b',64),cashier,gen_random_uuid());
  BEGIN
   INSERT INTO expense_claims(organization_id,branch_id,category_id,cost_center,invoice_reference,amount_usd,incurred_on,
    source_kind,description,evidence_reference,command_id,request_hash,created_by,correlation_id)
   VALUES(o,b,cat,'Pista','repair-101',45,(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date,
    'other','Factura duplicada de reparación','doc://duplicate',gen_random_uuid(),repeat('c',64),cashier,gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
   INSERT INTO expense_decisions(expense_id,organization_id,branch_id,outcome,reason,command_id,request_hash,decided_by,correlation_id)
   VALUES(expense,o,b,'approved','Autoaprobación no permitida',gen_random_uuid(),repeat('d',64),cashier,gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO expense_decisions(expense_id,organization_id,branch_id,outcome,reason,command_id,request_hash,decided_by,correlation_id)
  VALUES(expense,o,b,'approved','Comprobante revisado y aprobado',gen_random_uuid(),repeat('e',64),manager,gen_random_uuid());
  INSERT INTO expense_disbursements(organization_id,branch_id,expense_id,amount_usd,method,cash_session_id,
   command_id,request_hash,recorded_by,correlation_id)
  VALUES(o,b,expense,20,'cash',session_id,gen_random_uuid(),repeat('f',64),cashier,gen_random_uuid());
  IF (SELECT count(*) FROM cash_movements WHERE expense_disbursement_id IS NOT NULL AND organization_id=o)<>1
   OR (SELECT sum(delta_usd) FROM cash_movements WHERE organization_id=o)<>-20
  THEN RAISE EXCEPTION 'Expense cash ledger wrong'; END IF;
  BEGIN
   INSERT INTO expense_disbursements(organization_id,branch_id,expense_id,amount_usd,method,cash_session_id,
    command_id,request_hash,recorded_by,correlation_id)
   VALUES(o,b,expense,26,'cash',session_id,gen_random_uuid(),repeat('1',64),cashier,gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  IF (SELECT sum(delta_usd) FROM cash_movements WHERE organization_id=o)<>-20 THEN RAISE EXCEPTION 'Overpayment changed cash'; END IF;
  RAISE EXCEPTION 'ROLLBACK' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=o) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
 RAISE NOTICE 'PASS expense independent approval, duplicate, partial cash and excess rejection';
END $test$;
