BEGIN;

INSERT INTO permissions(code,description) VALUES
 ('loyalty.program.read','Consultar las políticas de puntos de la organización'),
 ('loyalty.program.manage','Crear propuestas de política de puntos para la organización'),
 ('loyalty.program.approve','Aprobar o rechazar políticas de puntos de la organización')
ON CONFLICT(code) DO NOTHING;

ALTER TABLE customer_loyalty_programs
  ADD COLUMN command_id uuid,
  ADD COLUMN request_hash char(64),
  ADD COLUMN submitted_by uuid,
  ADD COLUMN submitted_at timestamptz,
  ADD COLUMN decision_by uuid,
  ADD COLUMN decision_at timestamptz,
  ADD COLUMN decision_reason text,
  ADD COLUMN legacy_approval boolean NOT NULL DEFAULT false;

-- Preserve already active programs while marking that their former workflow did not
-- retain maker/checker metadata. New versions always use the stricter workflow below.
UPDATE customer_loyalty_programs
   SET submitted_by=created_by,
       submitted_at=created_at,
       decision_by=approved_by,
       decision_at=approved_at,
       legacy_approval=true
 WHERE status IN ('active','retired');

ALTER TABLE customer_loyalty_programs
  DROP CONSTRAINT customer_loyalty_programs_status_check,
  DROP CONSTRAINT customer_loyalty_programs_check,
  ADD CONSTRAINT customer_loyalty_programs_status_check
    CHECK(status IN ('draft','pending_approval','active','retired','rejected')),
  ADD CONSTRAINT customer_loyalty_programs_lifecycle_check CHECK (
    (status IN ('draft','pending_approval','rejected','active','retired')) AND
    ((status='draft' AND submitted_by IS NULL AND submitted_at IS NULL AND decision_by IS NULL AND decision_at IS NULL AND approved_by IS NULL AND approved_at IS NULL) OR
     (status='pending_approval' AND submitted_by IS NOT NULL AND submitted_at IS NOT NULL AND decision_by IS NULL AND decision_at IS NULL AND approved_by IS NULL AND approved_at IS NULL) OR
     (status='rejected' AND submitted_by IS NOT NULL AND submitted_at IS NOT NULL AND decision_by IS NOT NULL AND decision_at IS NOT NULL AND decision_reason IS NOT NULL AND approved_by IS NULL AND approved_at IS NULL) OR
     (status='active' AND submitted_by IS NOT NULL AND submitted_at IS NOT NULL AND decision_by IS NOT NULL AND decision_at IS NOT NULL AND approved_by IS NOT NULL AND approved_at IS NOT NULL AND (legacy_approval OR (approved_by<>created_by AND approved_by<>submitted_by))) OR
     (status='retired' AND ((legacy_approval AND ((approved_by IS NULL AND approved_at IS NULL) OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))) OR
       (submitted_by IS NOT NULL AND submitted_at IS NOT NULL AND decision_by IS NOT NULL AND decision_at IS NOT NULL AND approved_by IS NOT NULL AND approved_at IS NOT NULL AND approved_by<>created_by AND approved_by<>submitted_by))))
  ),
  ADD CONSTRAINT customer_loyalty_programs_command_hash_check CHECK (
    (command_id IS NULL AND request_hash IS NULL) OR
    (command_id IS NOT NULL AND request_hash ~ '^[0-9a-f]{64}$')
  ),
  ADD CONSTRAINT customer_loyalty_programs_submitted_by_fk FOREIGN KEY(submitted_by,organization_id) REFERENCES users(id,organization_id),
  ADD CONSTRAINT customer_loyalty_programs_decision_by_fk FOREIGN KEY(decision_by,organization_id) REFERENCES users(id,organization_id),
  ADD CONSTRAINT customer_loyalty_programs_command_unique UNIQUE(organization_id,command_id),
  ADD CONSTRAINT customer_loyalty_programs_rate_check CHECK(points_per_eligible_usd>=0 AND points_per_eligible_usd<=1000),
  ADD CONSTRAINT customer_loyalty_programs_minimum_check CHECK(minimum_eligible_usd>=0 AND minimum_eligible_usd<=1000000);

CREATE TABLE customer_loyalty_program_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 program_id uuid NOT NULL,
 command_id uuid NOT NULL,
 actor_id uuid NOT NULL,
 event_type text NOT NULL CHECK(event_type IN ('created','submitted','approved','rejected','retired')),
 request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 payload jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(payload)='object'),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(program_id,organization_id) REFERENCES customer_loyalty_programs(id,organization_id),
 FOREIGN KEY(actor_id,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id)
);
CREATE INDEX customer_loyalty_program_events_history_idx ON customer_loyalty_program_events(organization_id,program_id,created_at,id);

CREATE FUNCTION protect_customer_loyalty_program() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF OLD.organization_id IS DISTINCT FROM NEW.organization_id OR OLD.version IS DISTINCT FROM NEW.version
    OR OLD.points_per_eligible_usd IS DISTINCT FROM NEW.points_per_eligible_usd
    OR OLD.minimum_eligible_usd IS DISTINCT FROM NEW.minimum_eligible_usd
    OR OLD.points_expire_after_days IS DISTINCT FROM NEW.points_expire_after_days
    OR OLD.policy IS DISTINCT FROM NEW.policy OR OLD.created_by IS DISTINCT FROM NEW.created_by
    OR OLD.legacy_approval IS DISTINCT FROM NEW.legacy_approval THEN
   RAISE EXCEPTION 'Loyalty policy versions are immutable' USING ERRCODE='55000';
 END IF;
 IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
   (OLD.status='draft' AND NEW.status='pending_approval') OR
   (OLD.status='pending_approval' AND NEW.status IN ('active','rejected')) OR
   (OLD.status='active' AND NEW.status='retired')
 ) THEN RAISE EXCEPTION 'Invalid loyalty policy transition' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER customer_loyalty_program_guard BEFORE UPDATE ON customer_loyalty_programs
 FOR EACH ROW EXECUTE FUNCTION protect_customer_loyalty_program();
CREATE FUNCTION reject_customer_loyalty_program_delete() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'Loyalty policy versions cannot be deleted' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER customer_loyalty_program_no_delete BEFORE DELETE ON customer_loyalty_programs
 FOR EACH ROW EXECUTE FUNCTION reject_customer_loyalty_program_delete();
CREATE FUNCTION reject_customer_loyalty_program_event_mutation() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'Loyalty policy events are append-only' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER customer_loyalty_program_event_immutable BEFORE UPDATE OR DELETE ON customer_loyalty_program_events
 FOR EACH ROW EXECUTE FUNCTION reject_customer_loyalty_program_event_mutation();

ALTER TABLE customer_loyalty_program_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE customer_loyalty_program_events FROM PUBLIC,anon,authenticated,service_role;
CREATE POLICY dlc_api_select ON customer_loyalty_program_events FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON customer_loyalty_program_events FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_update ON customer_loyalty_programs FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
GRANT SELECT,INSERT,UPDATE ON customer_loyalty_programs TO dlc_api_runtime;
GRANT SELECT,INSERT ON customer_loyalty_program_events TO dlc_api_runtime;
REVOKE ALL ON FUNCTION protect_customer_loyalty_program(),reject_customer_loyalty_program_delete(),reject_customer_loyalty_program_event_mutation() FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
