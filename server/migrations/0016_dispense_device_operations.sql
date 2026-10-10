CREATE TABLE dispense_device_operations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  authorization_id uuid NOT NULL,
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  operation text NOT NULL CHECK (operation IN ('start','query')),
  adapter_mode text NOT NULL CHECK (adapter_mode IN ('manual','simulated')),
  scenario text NOT NULL CHECK (scenario IN ('normal','timeout_after_completion','timeout_before_start')),
  snapshot jsonb NOT NULL CHECK (jsonb_typeof(snapshot)='object'),
  outcome jsonb CHECK (outcome IS NULL OR jsonb_typeof(outcome)='object'),
  state text NOT NULL DEFAULT 'prepared' CHECK (state IN ('prepared','observed','applied')),
  requested_by uuid NOT NULL,
  correlation_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  observed_at timestamptz,
  applied_at timestamptz,
  FOREIGN KEY (authorization_id,organization_id,branch_id) REFERENCES dispense_authorizations(id,organization_id,branch_id),
  FOREIGN KEY (requested_by,organization_id) REFERENCES users(id,organization_id),
  CHECK (state='prepared' OR (outcome IS NOT NULL AND observed_at IS NOT NULL)),
  CHECK (state<>'applied' OR applied_at IS NOT NULL),
  CHECK (adapter_mode='simulated' OR scenario='normal'),
  CHECK (snapshot ? 'authorizationId' AND (snapshot->>'authorizationId')::uuid=authorization_id),
  CHECK (outcome IS NULL OR ((outcome->>'source')=adapter_mode AND outcome ? 'source' AND outcome ? 'status'
    AND (outcome->>'status') IN ('operator_required','started','timeout','completed','no_flow'))),
  UNIQUE (organization_id,command_id)
);
CREATE UNIQUE INDEX dispense_device_one_start_idx ON dispense_device_operations(authorization_id) WHERE operation='start';
CREATE INDEX dispense_device_history_idx ON dispense_device_operations(authorization_id,organization_id,branch_id,created_at);
CREATE INDEX dispense_device_actor_idx ON dispense_device_operations(requested_by,organization_id);
ALTER TABLE dispense_device_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE dispense_device_operations FROM PUBLIC;
DO $$ DECLARE client_role text; BEGIN
  FOREACH client_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=client_role) THEN
      EXECUTE format('REVOKE ALL ON TABLE public.dispense_device_operations FROM %I',client_role);
    END IF;
  END LOOP;
END $$;
GRANT SELECT,INSERT ON dispense_device_operations TO dlc_api_runtime;
GRANT UPDATE(outcome,state,observed_at,applied_at) ON dispense_device_operations TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON dispense_device_operations FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON dispense_device_operations FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_update ON dispense_device_operations FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
