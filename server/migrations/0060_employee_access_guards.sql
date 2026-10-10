-- Leave, suspension and termination end operational access after attendance is closed.
CREATE OR REPLACE FUNCTION change_employee_lifecycle(p_org uuid,p_actor uuid,p_employee uuid,p_version integer,
 p_status text,p_branch uuid,p_effective date,p_reason text,p_command uuid,p_hash text,p_correlation uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE e employees%ROWTYPE; old employee_lifecycle_events%ROWTYPE; result uuid; u users%ROWTYPE;
BEGIN
 IF p_status NOT IN('active','leave','suspended','terminated') OR p_effective IS NULL
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500 OR p_hash !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Invalid employee transition' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('employee-event:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM employee_lifecycle_events WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.recorded_by<>p_actor THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.id;
 END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO e FROM employees WHERE id=p_employee AND organization_id=p_org FOR UPDATE;
 IF e.id IS NULL OR e.version<>p_version OR e.status='terminated' OR
  (p_status=e.status AND p_branch IS NOT DISTINCT FROM e.branch_id)
 THEN RAISE EXCEPTION 'Employee state/version changed' USING ERRCODE='23514'; END IF;
 IF p_branch IS NOT NULL AND NOT EXISTS(SELECT 1 FROM branches WHERE id=p_branch AND organization_id=p_org AND status='active')
 THEN RAISE EXCEPTION 'Branch unavailable' USING ERRCODE='23514'; END IF;
 IF p_effective>(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date THEN
  RAISE EXCEPTION 'Future change must be scheduled, not applied immediately' USING ERRCODE='23514'; END IF;
 IF p_status IN('leave','suspended','terminated') AND EXISTS(
  SELECT 1 FROM employee_work_shifts s JOIN employee_shift_attendance a ON a.shift_id=s.id
  WHERE s.employee_id=e.id AND s.status='scheduled' AND a.clocked_in_at IS NOT NULL AND a.clocked_out_at IS NULL) THEN
  RAISE EXCEPTION 'Complete active attendance before disabling employee' USING ERRCODE='23514'; END IF;
 IF p_status='terminated' AND EXISTS(
  SELECT 1 FROM users x JOIN cash_sessions cs ON cs.cashier_id=x.id
  LEFT JOIN cash_closures cl ON cl.session_id=cs.id
  WHERE x.employee_id=e.id AND cl.id IS NULL) THEN
  RAISE EXCEPTION 'Close cashier session before termination' USING ERRCODE='23514'; END IF;
 INSERT INTO employee_lifecycle_events(organization_id,employee_id,old_status,new_status,old_branch_id,new_branch_id,
  reason,effective_on,command_id,request_hash,recorded_by,correlation_id)
 VALUES(p_org,e.id,e.status,p_status,e.branch_id,p_branch,btrim(p_reason),p_effective,p_command,p_hash,p_actor,p_correlation)
 RETURNING id INTO result;
 UPDATE employees SET status=p_status,branch_id=p_branch,version=version+1,
  ended_on=CASE WHEN p_status='terminated' THEN p_effective ELSE ended_on END,updated_at=clock_timestamp()
 WHERE id=e.id;
 IF p_status IN('leave','suspended','terminated') THEN
  UPDATE users SET status='suspended',permission_version=permission_version+1,updated_at=clock_timestamp()
  WHERE employee_id=e.id AND organization_id=p_org AND status<>'suspended';
  UPDATE auth_sessions SET revoked_at=clock_timestamp(),revoke_reason='employee_status'
  WHERE user_id IN(SELECT id FROM users WHERE employee_id=e.id AND organization_id=p_org)
   AND revoked_at IS NULL;
 END IF;
 RETURN result;
END $$;
