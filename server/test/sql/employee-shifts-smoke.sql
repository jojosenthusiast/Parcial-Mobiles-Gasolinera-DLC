DO $test$
DECLARE o uuid:=gen_random_uuid();b uuid:=gen_random_uuid();worker uuid:=gen_random_uuid();manager uuid:=gen_random_uuid();
 emp uuid:=gen_random_uuid();register_id uuid:=gen_random_uuid();shift_id uuid:=gen_random_uuid();clock_id uuid; shift_start timestamptz; shift_end timestamptz;
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(o,'Transient workforce');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(b,o,'STAFF','Workforce','central','active');
  INSERT INTO employees(id,organization_id,branch_id,employee_code,legal_name,position_title,status)
   VALUES(emp,o,b,'EMP1','Ana Operator','Cajera','active');
  INSERT INTO users(id,organization_id,employee_id,email_normalized,display_name,password_hash,status)
   VALUES(worker,o,emp,worker::text||'@example.invalid','Ana','NO_LOGIN','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status)
   VALUES(manager,o,manager::text||'@example.invalid','Manager','NO_LOGIN','active');
  INSERT INTO cash_registers(id,organization_id,branch_id,code,created_by) VALUES(register_id,o,b,'C1',manager);
  shift_start:=((clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date-1+time '22:00') AT TIME ZONE 'America/El_Salvador';
  shift_end:=shift_start+interval '8 hours';
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO employee_work_shifts(id,organization_id,branch_id,employee_id,position,cash_register_id,starts_at,ends_at,command_id,request_hash,scheduled_by,correlation_id)
   VALUES(shift_id,o,b,emp,'cashier',register_id,shift_start,shift_end,gen_random_uuid(),repeat('a',64),manager,gen_random_uuid());
  BEGIN
   INSERT INTO employee_work_shifts(organization_id,branch_id,employee_id,position,cash_register_id,starts_at,ends_at,command_id,request_hash,scheduled_by,correlation_id)
   VALUES(o,b,emp,'cashier',register_id,shift_start+interval '1 hour',shift_end+interval '1 hour',gen_random_uuid(),repeat('b',64),manager,gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  clock_id:=record_employee_attendance(o,b,worker,shift_id,'clock_in',shift_start,NULL,NULL,gen_random_uuid(),repeat('c',64),gen_random_uuid());
  PERFORM record_employee_attendance(o,b,worker,shift_id,'clock_out',shift_end,NULL,NULL,gen_random_uuid(),repeat('d',64),gen_random_uuid());
  PERFORM record_employee_attendance(o,b,manager,shift_id,'correction',shift_start+interval '5 minutes',clock_id,'Terminal marcó cinco minutos antes',gen_random_uuid(),repeat('e',64),gen_random_uuid());
  IF (SELECT count(*) FROM employee_shift_attendance WHERE organization_id=o AND attendance_state='completed')<>1 THEN RAISE EXCEPTION 'Attendance not completed'; END IF;
  BEGIN
   PERFORM cancel_employee_shift(o,b,manager,shift_id,'Intento cancelar turno cumplido',gen_random_uuid(),repeat('f',64),gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  DECLARE
   planned uuid;
  BEGIN
   planned:=schedule_employee_change(o,manager,emp,1,'leave',b,(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date+1,
    'Permiso programado para mañana',gen_random_uuid(),repeat('2',64),gen_random_uuid());
   BEGIN
    PERFORM apply_employee_change(o,manager,planned,gen_random_uuid(),repeat('3',64),gen_random_uuid());
    RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
   EXCEPTION WHEN check_violation THEN NULL; END;
  END;
  BEGIN
   INSERT INTO cash_sessions(organization_id,branch_id,register_id,cashier_id,opening_usd,command_id,request_hash,correlation_id)
   VALUES(o,b,register_id,worker,10,gen_random_uuid(),repeat('4',64),gen_random_uuid());
   PERFORM change_employee_lifecycle(o,manager,emp,1,'terminated',b,(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date,'Baja con caja abierta no permitida',gen_random_uuid(),repeat('5',64),gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM change_employee_lifecycle(o,manager,emp,1,'terminated',b,(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date,'Fin de relación laboral confirmada',gen_random_uuid(),repeat('1',64),gen_random_uuid());
  IF (SELECT status FROM users WHERE id=worker)<>'suspended' OR (SELECT status FROM employees WHERE id=emp)<>'terminated'
  THEN RAISE EXCEPTION 'Termination did not revoke account'; END IF;
  RAISE EXCEPTION 'ROLLBACK' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=o) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
 RAISE NOTICE 'PASS overnight shift, overlap, attendance, correction, cancellation guard, termination';
END $test$;
