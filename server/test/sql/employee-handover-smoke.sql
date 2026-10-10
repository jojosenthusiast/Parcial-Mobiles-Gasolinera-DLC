DO $test$
DECLARE o uuid:=gen_random_uuid();b uuid:=gen_random_uuid();worker uuid:=gen_random_uuid();manager uuid:=gen_random_uuid();
 emp uuid:=gen_random_uuid();register_id uuid:=gen_random_uuid();shift_id uuid:=gen_random_uuid();clock_id uuid; emp2 uuid:=gen_random_uuid(); worker2 uuid:=gen_random_uuid(); dispenser uuid:=gen_random_uuid(); shift_a uuid:=gen_random_uuid(); shift_b uuid:=gen_random_uuid(); handover uuid:=gen_random_uuid(); block uuid; shift_start timestamptz; shift_end timestamptz;
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
  INSERT INTO employees(id,organization_id,branch_id,employee_code,legal_name,position_title,status)
   VALUES(emp2,o,b,'EMP2','Luis Operator','Pista','active');
  INSERT INTO users(id,organization_id,employee_id,email_normalized,display_name,password_hash,status)
   VALUES(worker2,o,emp2,worker2::text||'@example.invalid','Luis','NO_LOGIN','active');
  INSERT INTO dispensers(id,organization_id,branch_id,code) VALUES(dispenser,o,b,'D1');
  INSERT INTO employee_work_shifts(id,organization_id,branch_id,employee_id,position,cash_register_id,starts_at,ends_at,command_id,request_hash,scheduled_by,correlation_id)
   VALUES(shift_a,o,b,emp,'cashier',register_id,clock_timestamp()-interval '2 hours',clock_timestamp()+interval '2 hours',gen_random_uuid(),repeat('2',64),manager,gen_random_uuid());
  INSERT INTO employee_work_shifts(id,organization_id,branch_id,employee_id,position,dispenser_id,starts_at,ends_at,command_id,request_hash,scheduled_by,correlation_id)
   VALUES(shift_b,o,b,emp2,'forecourt',dispenser,clock_timestamp()-interval '1 hour',clock_timestamp()+interval '3 hours',gen_random_uuid(),repeat('3',64),manager,gen_random_uuid());
  block:=set_staffing_block(o,b,manager,dispenser,true,'Sin personal en pista disponible',gen_random_uuid(),repeat('4',64));
  IF NOT EXISTS(SELECT 1 FROM asset_blocks WHERE id=block AND block_type='operational' AND resolved_at IS NULL) THEN RAISE EXCEPTION 'Staffing block missing'; END IF;
  PERFORM record_employee_attendance(o,b,worker,shift_a,'clock_in',clock_timestamp()-interval '1 hour',NULL,NULL,gen_random_uuid(),repeat('5',64),gen_random_uuid());
  PERFORM record_employee_attendance(o,b,worker2,shift_b,'clock_in',clock_timestamp()-interval '30 minutes',NULL,NULL,gen_random_uuid(),repeat('6',64),gen_random_uuid());
  INSERT INTO employee_shift_handovers(id,organization_id,branch_id,outgoing_shift_id,incoming_shift_id,pending_items,equipment_note,command_id,request_hash,handed_by,correlation_id)
   VALUES(handover,o,b,shift_a,shift_b,'[{"text":"Revisar surtidor"}]','Equipo recibido en pista',gen_random_uuid(),repeat('7',64),worker,gen_random_uuid());
  INSERT INTO employee_handover_acknowledgments(handover_id,organization_id,branch_id,note,command_id,request_hash,received_by,correlation_id)
   VALUES(handover,o,b,'Pendientes recibidos',gen_random_uuid(),repeat('8',64),worker2,gen_random_uuid());
  PERFORM set_staffing_block(o,b,manager,dispenser,false,'Personal presente y registrado en pista',gen_random_uuid(),repeat('9',64));
  IF (SELECT resolved_at FROM asset_blocks WHERE id=block) IS NULL THEN RAISE EXCEPTION 'Staffing block not resolved'; END IF;
  BEGIN
   PERFORM change_employee_lifecycle(o,manager,emp,1,'terminated',b,(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date,'Baja durante turno activo no permitida',gen_random_uuid(),repeat('a',64),gen_random_uuid());
   RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM record_employee_attendance(o,b,worker,shift_a,'clock_out',clock_timestamp(),NULL,NULL,gen_random_uuid(),repeat('b',64),gen_random_uuid());
  PERFORM change_employee_lifecycle(o,manager,emp,1,'terminated',b,(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date,'Fin de relación laboral confirmada',gen_random_uuid(),repeat('1',64),gen_random_uuid());
  IF (SELECT status FROM users WHERE id=worker)<>'suspended' OR (SELECT status FROM employees WHERE id=emp)<>'terminated'
  THEN RAISE EXCEPTION 'Termination did not revoke account'; END IF;
  RAISE EXCEPTION 'ROLLBACK' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=o) THEN RAISE EXCEPTION 'Fixture persisted'; END IF;
 RAISE NOTICE 'PASS overnight shift, overlap, attendance, correction, cancellation guard, termination';
END $test$;
