CREATE TABLE employee_attendance_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 shift_id uuid NOT NULL,kind text NOT NULL CHECK(kind IN('clock_in','clock_out','correction')),
 occurred_at timestamptz NOT NULL,corrects_event_id uuid,reason text,
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 recorded_by uuid NOT NULL,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(shift_id,organization_id,branch_id) REFERENCES employee_work_shifts(id,organization_id,branch_id),
 FOREIGN KEY(corrects_event_id) REFERENCES employee_attendance_events(id),
 FOREIGN KEY(recorded_by,organization_id) REFERENCES users(id,organization_id),
 CHECK((kind='correction' AND corrects_event_id IS NOT NULL AND length(btrim(reason)) BETWEEN 10 AND 500)
  OR (kind<>'correction' AND corrects_event_id IS NULL AND reason IS NULL)),
 UNIQUE(organization_id,command_id)
);
CREATE UNIQUE INDEX one_clock_in_per_shift ON employee_attendance_events(shift_id) WHERE kind='clock_in';
CREATE UNIQUE INDEX one_clock_out_per_shift ON employee_attendance_events(shift_id) WHERE kind='clock_out';
CREATE UNIQUE INDEX one_correction_per_event ON employee_attendance_events(corrects_event_id) WHERE kind='correction';
CREATE VIEW employee_shift_attendance WITH (security_invoker=true) AS
 SELECT s.id AS shift_id,s.organization_id,s.branch_id,s.employee_id,s.starts_at,s.ends_at,
  coalesce(ci_fix.occurred_at,ci.occurred_at) AS clocked_in_at,
  coalesce(co_fix.occurred_at,co.occurred_at) AS clocked_out_at,
  CASE WHEN ci.id IS NULL THEN 'absent_or_unrecorded'
   WHEN co.id IS NULL THEN 'on_duty_or_missing_checkout' ELSE 'completed' END AS attendance_state
 FROM employee_work_shifts s
 LEFT JOIN employee_attendance_events ci ON ci.shift_id=s.id AND ci.kind='clock_in'
 LEFT JOIN employee_attendance_events co ON co.shift_id=s.id AND co.kind='clock_out'
 LEFT JOIN employee_attendance_events ci_fix ON ci_fix.corrects_event_id=ci.id
 LEFT JOIN employee_attendance_events co_fix ON co_fix.corrects_event_id=co.id;

CREATE FUNCTION record_employee_attendance(p_org uuid,p_branch uuid,p_actor uuid,p_shift uuid,p_kind text,p_at timestamptz,
 p_corrects uuid,p_reason text,p_command uuid,p_hash text,p_correlation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE s employee_work_shifts%ROWTYPE; old employee_attendance_events%ROWTYPE; target employee_attendance_events%ROWTYPE;
 in_at timestamptz; result uuid;
BEGIN
 IF p_kind NOT IN('clock_in','clock_out','correction') OR p_at IS NULL OR p_at>clock_timestamp()+interval '5 minutes'
  OR p_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid attendance event' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('attendance:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM employee_attendance_events WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.recorded_by<>p_actor OR old.shift_id<>p_shift
  THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.id;
 END IF;
 SELECT * INTO s FROM employee_work_shifts WHERE id=p_shift AND organization_id=p_org AND branch_id=p_branch FOR UPDATE;
 IF s.id IS NULL OR s.status<>'scheduled' OR p_at<s.starts_at-interval '2 hours' OR p_at>s.ends_at+interval '12 hours'
 THEN RAISE EXCEPTION 'Shift or time unavailable' USING ERRCODE='23514'; END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active'
  AND (p_kind='correction' OR employee_id=s.employee_id);
 IF NOT FOUND THEN RAISE EXCEPTION 'Worker identity unavailable' USING ERRCODE='23514'; END IF;
 IF p_kind='correction' THEN
  SELECT * INTO target FROM employee_attendance_events WHERE id=p_corrects AND shift_id=s.id AND kind IN('clock_in','clock_out');
  IF target.id IS NULL OR target.recorded_by=p_actor OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500
   OR EXISTS(SELECT 1 FROM employee_attendance_events WHERE corrects_event_id=target.id)
  THEN RAISE EXCEPTION 'Correction needs independent reason and original event' USING ERRCODE='23514'; END IF;
  IF target.kind='clock_in' AND EXISTS(SELECT 1 FROM employee_shift_attendance a WHERE a.shift_id=s.id AND a.clocked_out_at<=p_at)
   OR target.kind='clock_out' AND EXISTS(SELECT 1 FROM employee_shift_attendance a WHERE a.shift_id=s.id AND a.clocked_in_at>=p_at)
  THEN RAISE EXCEPTION 'Corrected attendance order invalid' USING ERRCODE='23514'; END IF;
 ELSE
  IF p_corrects IS NOT NULL OR p_reason IS NOT NULL OR
    (p_kind='clock_in' AND EXISTS(SELECT 1 FROM employee_attendance_events WHERE shift_id=s.id AND kind='clock_in')) OR
    (p_kind='clock_out' AND (NOT EXISTS(SELECT 1 FROM employee_attendance_events WHERE shift_id=s.id AND kind='clock_in')
      OR EXISTS(SELECT 1 FROM employee_attendance_events WHERE shift_id=s.id AND kind='clock_out')))
  THEN RAISE EXCEPTION 'Attendance sequence invalid' USING ERRCODE='23514'; END IF;
  IF p_kind='clock_out' THEN
   SELECT clocked_in_at INTO in_at FROM employee_shift_attendance WHERE shift_id=s.id;
   IF p_at<=in_at THEN RAISE EXCEPTION 'Clock-out precedes clock-in' USING ERRCODE='23514'; END IF;
  END IF;
 END IF;
 INSERT INTO employee_attendance_events(organization_id,branch_id,shift_id,kind,occurred_at,corrects_event_id,
  reason,command_id,request_hash,recorded_by,correlation_id)
 VALUES(p_org,p_branch,p_shift,p_kind,p_at,p_corrects,p_reason,p_command,p_hash,p_actor,p_correlation)
 RETURNING id INTO result;
 RETURN result;
END $$;
ALTER TABLE employee_attendance_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON employee_attendance_events,employee_shift_attendance FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON employee_attendance_events,employee_shift_attendance TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON employee_attendance_events FOR SELECT TO dlc_api_runtime USING(true);
CREATE TRIGGER attendance_immutable BEFORE UPDATE OR DELETE ON employee_attendance_events FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION record_employee_attendance(uuid,uuid,uuid,uuid,text,timestamptz,uuid,text,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION record_employee_attendance(uuid,uuid,uuid,uuid,text,timestamptz,uuid,text,uuid,text,uuid) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES('staff.attendance.record','Registrar entrada y salida de turno'),
 ('staff.attendance.correct','Corregir asistencia con separación de actor') ON CONFLICT(code) DO NOTHING;
