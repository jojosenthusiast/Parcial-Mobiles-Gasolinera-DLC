ALTER TABLE asset_blocks ADD COLUMN incident_id uuid REFERENCES incidents(id);
CREATE UNIQUE INDEX asset_blocks_incident_unique_idx ON asset_blocks(incident_id) WHERE incident_id IS NOT NULL;

CREATE FUNCTION advance_incident(org uuid,branch uuid,target_incident uuid,actor uuid,expected_version integer,
 next_status text,assignee uuid,due timestamptz,transition_note text)
 RETURNS TABLE(incident_id uuid,status text,version integer)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE i incidents%ROWTYPE;
BEGIN
 SELECT x.* INTO i FROM incidents x WHERE x.id=target_incident AND x.organization_id=org AND x.branch_id=branch FOR UPDATE;
 IF i.id IS NULL OR i.version<>expected_version THEN RAISE EXCEPTION 'Incident version changed or scope invalid' USING ERRCODE='40001'; END IF;
 IF NOT ((i.status='reported' AND next_status='assessed') OR
  (i.status='assessed' AND next_status='in_progress') OR
  (i.status='in_progress' AND next_status='resolved') OR
  (i.status='resolved' AND next_status='closed')) THEN
  RAISE EXCEPTION 'Invalid incident transition' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') OR
  (assignee IS NOT NULL AND NOT EXISTS(SELECT 1 FROM users u WHERE u.id=assignee AND u.organization_id=org AND u.status='active')) THEN
  RAISE EXCEPTION 'Actor/assignee inactive or outside organization' USING ERRCODE='23514'; END IF;
 IF (next_status='in_progress' AND COALESCE(assignee,i.assignee_id) IS NULL) OR
  (due IS NOT NULL AND due<=i.occurred_at) THEN
  RAISE EXCEPTION 'Responsible assignee and valid due date required' USING ERRCODE='23514'; END IF;
 UPDATE incidents x SET status=next_status,assignee_id=COALESCE(assignee,x.assignee_id),due_at=COALESCE(due,x.due_at),
  version=x.version+1,resolved_at=CASE WHEN next_status='resolved' THEN clock_timestamp() ELSE x.resolved_at END,
  closed_at=CASE WHEN next_status='closed' THEN clock_timestamp() ELSE x.closed_at END WHERE x.id=target_incident;
 INSERT INTO incident_events(organization_id,branch_id,incident_id,from_status,to_status,note,actor_id)
 VALUES(org,branch,target_incident,i.status,next_status,transition_note,actor);
 RETURN QUERY SELECT target_incident,next_status,expected_version+1;
END; $$;
REVOKE ALL ON FUNCTION advance_incident(uuid,uuid,uuid,uuid,integer,text,uuid,timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION advance_incident(uuid,uuid,uuid,uuid,integer,text,uuid,timestamptz,text) TO dlc_api_runtime;
