CREATE TABLE employee_work_shifts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,employee_id uuid NOT NULL,
 position text NOT NULL CHECK(position IN('cashier','forecourt','store','manager','maintenance')),
 cash_register_id uuid,dispenser_id uuid,
 starts_at timestamptz NOT NULL,ends_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'scheduled' CHECK(status IN('scheduled','cancelled')),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 scheduled_by uuid NOT NULL,scheduled_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(employee_id,organization_id) REFERENCES employees(id,organization_id),
 FOREIGN KEY(cash_register_id,organization_id,branch_id) REFERENCES cash_registers(id,organization_id,branch_id),
 FOREIGN KEY(dispenser_id,branch_id) REFERENCES dispensers(id,branch_id),
 FOREIGN KEY(scheduled_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(ends_at>starts_at AND ends_at<=starts_at+interval '24 hours'),
 CHECK((position='cashier' AND cash_register_id IS NOT NULL AND dispenser_id IS NULL)
 OR (position='forecourt' AND dispenser_id IS NOT NULL AND cash_register_id IS NULL)
 OR (position NOT IN('cashier','forecourt') AND cash_register_id IS NULL AND dispenser_id IS NULL)),
 UNIQUE(organization_id,command_id),UNIQUE(id,organization_id,branch_id)
);
CREATE INDEX employee_shifts_branch_time_idx ON employee_work_shifts(branch_id,starts_at,ends_at);
CREATE FUNCTION guard_employee_shift() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE e employees%ROWTYPE;
BEGIN
 IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'status') IS DISTINCT FROM (to_jsonb(OLD)-'status')
  THEN RAISE EXCEPTION 'Shift schedule is immutable except cancellation' USING ERRCODE='55000'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('employee-shifts:'||NEW.employee_id,0));
 SELECT * INTO e FROM employees WHERE id=NEW.employee_id;
 IF e.id IS NULL OR e.organization_id<>NEW.organization_id OR e.branch_id<>NEW.branch_id OR e.status<>'active'
 THEN RAISE EXCEPTION 'Employee unavailable at branch' USING ERRCODE='23514'; END IF;
 IF NEW.status='scheduled' AND EXISTS(SELECT 1 FROM employee_work_shifts s WHERE s.employee_id=NEW.employee_id
  AND s.id<>NEW.id AND s.status='scheduled' AND tstzrange(s.starts_at,s.ends_at,'[)') && tstzrange(NEW.starts_at,NEW.ends_at,'[)'))
 THEN RAISE EXCEPTION 'Employee shifts overlap' USING ERRCODE='23514'; END IF;
 IF NEW.status='scheduled' AND NEW.cash_register_id IS NOT NULL THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('cash-shifts:'||NEW.cash_register_id,0));
  IF EXISTS(SELECT 1 FROM employee_work_shifts s WHERE s.cash_register_id=NEW.cash_register_id
   AND s.id<>NEW.id AND s.status='scheduled' AND tstzrange(s.starts_at,s.ends_at,'[)') && tstzrange(NEW.starts_at,NEW.ends_at,'[)'))
  THEN RAISE EXCEPTION 'Cash register shift already assigned' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER employee_shift_guard BEFORE INSERT OR UPDATE ON employee_work_shifts FOR EACH ROW EXECUTE FUNCTION guard_employee_shift();
CREATE TABLE employee_shift_cancellations (
 shift_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 cancelled_by uuid NOT NULL,cancelled_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(shift_id,organization_id,branch_id) REFERENCES employee_work_shifts(id,organization_id,branch_id),
 FOREIGN KEY(cancelled_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id)
);
CREATE FUNCTION cancel_employee_shift(p_org uuid,p_branch uuid,p_actor uuid,p_shift uuid,p_reason text,
 p_command uuid,p_hash text,p_correlation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE s employee_work_shifts%ROWTYPE; old employee_shift_cancellations%ROWTYPE;
BEGIN
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500 OR p_hash !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Invalid cancellation' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('employee-shift-cancel:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM employee_shift_cancellations WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.cancelled_by<>p_actor OR old.shift_id<>p_shift THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.shift_id;
 END IF;
 SELECT * INTO s FROM employee_work_shifts WHERE id=p_shift AND organization_id=p_org AND branch_id=p_branch FOR UPDATE;
 IF s.id IS NULL OR s.status<>'scheduled' OR EXISTS(SELECT 1 FROM cash_sessions cs
  WHERE cs.register_id=s.cash_register_id AND cs.cashier_id IN(SELECT id FROM users WHERE employee_id=s.employee_id)
  AND NOT EXISTS(SELECT 1 FROM cash_closures WHERE session_id=cs.id))
 THEN RAISE EXCEPTION 'Shift cannot be cancelled with an open cash session' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM employee_attendance_events WHERE shift_id=s.id) THEN
  RAISE EXCEPTION 'Shift with attendance cannot be cancelled' USING ERRCODE='23514'; END IF;
 INSERT INTO employee_shift_cancellations(shift_id,organization_id,branch_id,reason,command_id,request_hash,cancelled_by,correlation_id)
 VALUES(s.id,p_org,p_branch,btrim(p_reason),p_command,p_hash,p_actor,p_correlation);
 UPDATE employee_work_shifts SET status='cancelled' WHERE id=s.id;
 RETURN s.id;
END $$;
-- Attendance table is added in the next migration; defer function resolution to execution time.
ALTER TABLE employee_work_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_shift_cancellations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON employee_work_shifts,employee_shift_cancellations FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON employee_work_shifts TO dlc_api_runtime;
GRANT SELECT ON employee_shift_cancellations TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON employee_work_shifts FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON employee_work_shifts FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_select ON employee_shift_cancellations FOR SELECT TO dlc_api_runtime USING(true);
CREATE TRIGGER shift_cancel_immutable BEFORE UPDATE OR DELETE ON employee_shift_cancellations FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE TRIGGER shift_delete_guard BEFORE DELETE ON employee_work_shifts FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION cancel_employee_shift(uuid,uuid,uuid,uuid,text,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION cancel_employee_shift(uuid,uuid,uuid,uuid,text,uuid,text,uuid) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES('staff.shifts.plan','Planificar y cancelar turnos de personal') ON CONFLICT(code) DO NOTHING;
