-- Planned changes are explicit pending facts; applying them rechecks the employee version.
CREATE TABLE employee_planned_changes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,employee_id uuid NOT NULL,
 expected_version integer NOT NULL CHECK(expected_version>0),next_status text NOT NULL
  CHECK(next_status IN('active','leave','suspended','terminated')),
 next_branch_id uuid,effective_on date NOT NULL,reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 scheduled_by uuid NOT NULL,scheduled_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 applied_event_id uuid UNIQUE REFERENCES employee_lifecycle_events(id),applied_at timestamptz,correlation_id uuid NOT NULL,
 FOREIGN KEY(employee_id,organization_id) REFERENCES employees(id,organization_id),
 FOREIGN KEY(next_branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(scheduled_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id),CHECK((applied_event_id IS NULL AND applied_at IS NULL) OR (applied_event_id IS NOT NULL AND applied_at IS NOT NULL))
);
CREATE UNIQUE INDEX employee_one_pending_change ON employee_planned_changes(employee_id) WHERE applied_at IS NULL;
CREATE FUNCTION schedule_employee_change(p_org uuid,p_actor uuid,p_employee uuid,p_version integer,p_status text,
 p_branch uuid,p_effective date,p_reason text,p_command uuid,p_hash text,p_correlation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE e employees%ROWTYPE; old employee_planned_changes%ROWTYPE; result uuid;
BEGIN
 IF p_status NOT IN('active','leave','suspended','terminated') OR p_effective<=(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500 OR p_hash !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Scheduled change must have a future date' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('employee-plan:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM employee_planned_changes WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.scheduled_by<>p_actor THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.id;
 END IF;
 SELECT * INTO e FROM employees WHERE id=p_employee AND organization_id=p_org FOR UPDATE;
 IF e.id IS NULL OR e.status='terminated' OR e.version<>p_version
  OR EXISTS(SELECT 1 FROM employee_planned_changes WHERE employee_id=e.id AND applied_at IS NULL)
  OR (p_status=e.status AND p_branch IS NOT DISTINCT FROM e.branch_id)
 THEN RAISE EXCEPTION 'Employee schedule conflict' USING ERRCODE='23514'; END IF;
 IF p_branch IS NOT NULL AND NOT EXISTS(SELECT 1 FROM branches WHERE id=p_branch AND organization_id=p_org AND status='active')
 THEN RAISE EXCEPTION 'Target branch unavailable' USING ERRCODE='23514'; END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 INSERT INTO employee_planned_changes(organization_id,employee_id,expected_version,next_status,next_branch_id,
  effective_on,reason,command_id,request_hash,scheduled_by,correlation_id)
 VALUES(p_org,p_employee,p_version,p_status,p_branch,p_effective,btrim(p_reason),p_command,p_hash,p_actor,p_correlation)
 RETURNING id INTO result;
 RETURN result;
END $$;
CREATE FUNCTION apply_employee_change(p_org uuid,p_actor uuid,p_plan uuid,p_command uuid,p_hash text,p_correlation uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE plan employee_planned_changes%ROWTYPE; result uuid;
BEGIN
 IF p_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid command' USING ERRCODE='23514'; END IF;
 SELECT * INTO plan FROM employee_planned_changes WHERE id=p_plan AND organization_id=p_org FOR UPDATE;
 IF plan.id IS NULL OR plan.effective_on>(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date
 THEN RAISE EXCEPTION 'Change not due' USING ERRCODE='23514'; END IF;
 IF plan.applied_event_id IS NOT NULL THEN RETURN plan.applied_event_id; END IF;
 result:=change_employee_lifecycle(p_org,p_actor,plan.employee_id,plan.expected_version,
  plan.next_status,plan.next_branch_id,plan.effective_on,plan.reason,p_command,p_hash,p_correlation);
 UPDATE employee_planned_changes SET applied_event_id=result,applied_at=clock_timestamp() WHERE id=plan.id;
 RETURN result;
END $$;
CREATE FUNCTION guard_employee_plan_update() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF TG_OP='DELETE' OR (to_jsonb(NEW)-'applied_event_id'-'applied_at') IS DISTINCT FROM (to_jsonb(OLD)-'applied_event_id'-'applied_at')
  OR OLD.applied_at IS NOT NULL
 THEN RAISE EXCEPTION 'Employee plan fact is immutable' USING ERRCODE='55000'; END IF;
 RETURN NEW;
END $$;
ALTER TABLE employee_planned_changes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON employee_planned_changes FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON employee_planned_changes TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON employee_planned_changes FOR SELECT TO dlc_api_runtime USING(true);
CREATE TRIGGER employee_plan_guard BEFORE UPDATE OR DELETE ON employee_planned_changes FOR EACH ROW EXECUTE FUNCTION guard_employee_plan_update();
REVOKE ALL ON FUNCTION schedule_employee_change(uuid,uuid,uuid,integer,text,uuid,date,text,uuid,text,uuid),
 apply_employee_change(uuid,uuid,uuid,uuid,text,uuid),guard_employee_plan_update()
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION schedule_employee_change(uuid,uuid,uuid,integer,text,uuid,date,text,uuid,text,uuid),
 apply_employee_change(uuid,uuid,uuid,uuid,text,uuid) TO dlc_api_runtime;
