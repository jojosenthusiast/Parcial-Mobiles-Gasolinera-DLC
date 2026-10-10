-- Employee identity is distinct from login; movements keep the historical actor.
ALTER TABLE employees ADD COLUMN position_title text NOT NULL DEFAULT 'Operación'
 CHECK(length(btrim(position_title)) BETWEEN 2 AND 100),
 ADD COLUMN contact_phone text CHECK(contact_phone IS NULL OR contact_phone~'^\+?[0-9 ()-]{7,24}$'),
 ADD COLUMN hired_on date,
 ADD COLUMN ended_on date,
 ADD COLUMN version integer NOT NULL DEFAULT 1 CHECK(version>0),
 ADD CONSTRAINT employee_dates CHECK(ended_on IS NULL OR hired_on IS NULL OR ended_on>=hired_on);
CREATE TABLE employee_lifecycle_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,employee_id uuid NOT NULL,
 old_status text NOT NULL,new_status text NOT NULL CHECK(new_status IN('active','leave','suspended','terminated')),
 old_branch_id uuid,new_branch_id uuid,reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 effective_on date NOT NULL,command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 recorded_by uuid NOT NULL,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(employee_id,organization_id) REFERENCES employees(id,organization_id),
 FOREIGN KEY(old_branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(new_branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(recorded_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id)
);
CREATE FUNCTION change_employee_lifecycle(p_org uuid,p_actor uuid,p_employee uuid,p_version integer,
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
 IF p_status IN('suspended','terminated') THEN
  UPDATE users SET status='suspended',permission_version=permission_version+1,updated_at=clock_timestamp()
  WHERE employee_id=e.id AND organization_id=p_org AND status<>'suspended';
  UPDATE auth_sessions SET revoked_at=clock_timestamp(),revoke_reason='employee_status'
  WHERE user_id IN(SELECT id FROM users WHERE employee_id=e.id AND organization_id=p_org)
   AND revoked_at IS NULL;
 END IF;
 RETURN result;
END $$;
ALTER TABLE employee_lifecycle_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON employee_lifecycle_events FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON employee_lifecycle_events TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON employee_lifecycle_events FOR SELECT TO dlc_api_runtime USING(true);
CREATE TRIGGER employee_event_immutable BEFORE UPDATE OR DELETE ON employee_lifecycle_events FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION change_employee_lifecycle(uuid,uuid,uuid,integer,text,uuid,date,text,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION change_employee_lifecycle(uuid,uuid,uuid,integer,text,uuid,date,text,uuid,text,uuid) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES('staff.private.read','Consultar contacto y datos privados de personal') ON CONFLICT(code) DO NOTHING;
