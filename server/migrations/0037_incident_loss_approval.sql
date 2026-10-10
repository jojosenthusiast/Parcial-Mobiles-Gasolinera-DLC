CREATE TABLE incident_loss_approvals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 assessment_id uuid NOT NULL UNIQUE REFERENCES incident_impact_assessments(id),
 command_id uuid NOT NULL,approved_by uuid NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 8 AND 500),
 approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),movement_id uuid UNIQUE REFERENCES inventory_movements(id),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(approved_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id)
);
CREATE FUNCTION approve_incident_loss(org uuid,branch uuid,assessment uuid,actor uuid,command uuid,review_reason text)
 RETURNS TABLE(approval_id uuid,tank_id uuid,quantity_l numeric,movement_id uuid)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a incident_impact_assessments%ROWTYPE; prior incident_loss_approvals%ROWTYPE; aid uuid;
BEGIN
 SELECT x.* INTO a FROM incident_impact_assessments x WHERE x.id=assessment AND x.organization_id=org AND x.branch_id=branch;
 IF a.id IS NULL OR a.impact_type<>'fuel_loss' OR a.assessed_by=actor OR NOT EXISTS(
  SELECT 1 FROM incidents i WHERE i.id=a.incident_id AND i.status IN('assessed','in_progress','resolved')) OR NOT EXISTS(
  SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Independent approval requires an assessed fuel loss' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('incident-loss:'||assessment::text,0));
 SELECT x.* INTO prior FROM incident_loss_approvals x WHERE x.assessment_id=assessment;
 IF prior.id IS NOT NULL THEN
  IF prior.command_id<>command OR prior.approved_by<>actor OR prior.reason<>review_reason THEN
   RAISE EXCEPTION 'Approval already exists with different details' USING ERRCODE='23505'; END IF;
  RETURN QUERY SELECT prior.id,a.tank_id,a.quantity_l,prior.movement_id; RETURN;
 END IF;
 INSERT INTO incident_loss_approvals(organization_id,branch_id,assessment_id,command_id,approved_by,reason)
 VALUES(org,branch,assessment,command,actor,review_reason) RETURNING id INTO aid;
 RETURN QUERY SELECT aid,a.tank_id,a.quantity_l,NULL::uuid;
END; $$;
CREATE FUNCTION validate_approved_incident_loss() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE approval incident_loss_approvals%ROWTYPE; assessment incident_impact_assessments%ROWTYPE;
BEGIN
 IF NEW.movement_type<>'loss' THEN RETURN NEW; END IF;
 IF NEW.source_type<>'incident_loss' OR NEW.source_id IS NULL THEN
  RAISE EXCEPTION 'Loss must originate from an independently approved incident assessment' USING ERRCODE='23514'; END IF;
 SELECT x.* INTO approval FROM incident_loss_approvals x WHERE x.assessment_id::text=NEW.source_id
  AND x.organization_id=NEW.organization_id AND x.branch_id=NEW.branch_id AND x.command_id=NEW.command_id;
 SELECT x.* INTO assessment FROM incident_impact_assessments x WHERE x.id=approval.assessment_id;
 IF approval.id IS NULL OR approval.movement_id IS NOT NULL OR assessment.impact_type<>'fuel_loss' OR
   assessment.tank_id<>NEW.tank_id OR assessment.quantity_l IS DISTINCT FROM -NEW.delta_l OR
   approval.approved_by<>NEW.actor_user_id THEN
  RAISE EXCEPTION 'Loss differs from approved quantity, tank or actor' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER inventory_loss_approval_guard BEFORE INSERT ON inventory_movements
 FOR EACH ROW EXECUTE FUNCTION validate_approved_incident_loss();
CREATE FUNCTION link_incident_loss(org uuid,branch uuid,assessment uuid,actor uuid,command uuid,target_movement uuid)
 RETURNS uuid LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE approval incident_loss_approvals%ROWTYPE;
BEGIN
 SELECT x.* INTO approval FROM incident_loss_approvals x WHERE x.assessment_id=assessment AND x.organization_id=org
  AND x.branch_id=branch AND x.command_id=command AND x.approved_by=actor FOR UPDATE;
 IF approval.id IS NULL OR NOT EXISTS(SELECT 1 FROM inventory_movements m WHERE m.id=target_movement AND m.organization_id=org
  AND m.branch_id=branch AND m.command_id=command AND m.movement_type='loss' AND m.source_id=assessment::text) THEN
  RAISE EXCEPTION 'Movement does not match approved loss' USING ERRCODE='23514'; END IF;
 IF approval.movement_id IS NULL THEN
  UPDATE incident_loss_approvals SET movement_id=target_movement WHERE id=approval.id;
 ELSIF approval.movement_id<>target_movement THEN RAISE EXCEPTION 'Another movement already linked' USING ERRCODE='23505'; END IF;
 RETURN approval.id;
END; $$;

ALTER TABLE incident_loss_approvals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE incident_loss_approvals FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT,UPDATE ON TABLE incident_loss_approvals TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON incident_loss_approvals FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON incident_loss_approvals FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_update ON incident_loss_approvals FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
REVOKE ALL ON FUNCTION approve_incident_loss(uuid,uuid,uuid,uuid,uuid,text),validate_approved_incident_loss(),
 link_incident_loss(uuid,uuid,uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION approve_incident_loss(uuid,uuid,uuid,uuid,uuid,text),link_incident_loss(uuid,uuid,uuid,uuid,uuid,uuid) TO dlc_api_runtime;
