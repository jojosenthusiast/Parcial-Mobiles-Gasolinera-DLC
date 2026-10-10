CREATE UNIQUE INDEX nozzles_identity_branch_idx ON nozzles(id,branch_id);

CREATE TABLE nozzle_meter_states (
  nozzle_id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  unit text NOT NULL CHECK (unit IN ('gallon_us','liter')),
  last_value numeric(24,9) NOT NULL CHECK (last_value >= 0),
  meter_serial text,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  last_reading_id uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (nozzle_id,branch_id) REFERENCES nozzles(id,branch_id),
  FOREIGN KEY (branch_id,organization_id) REFERENCES branches(id,organization_id)
);

CREATE TABLE nozzle_meter_readings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  nozzle_id uuid NOT NULL,
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  reading_type text NOT NULL CHECK (reading_type IN ('baseline','regular','meter_change')),
  value numeric(24,9) NOT NULL CHECK (value >= 0),
  unit text NOT NULL CHECK (unit IN ('gallon_us','liter')),
  prior_value numeric(24,9),
  prior_reading_id uuid,
  prior_meter_serial text,
  meter_serial text,
  old_serial text,
  new_serial text,
  change_reason text,
  note text,
  source text NOT NULL CHECK (source IN ('manual','simulated','device')),
  captured_by uuid NOT NULL,
  correlation_id uuid NOT NULL,
  captured_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (nozzle_id,branch_id) REFERENCES nozzles(id,branch_id),
  FOREIGN KEY (branch_id,organization_id) REFERENCES branches(id,organization_id),
  FOREIGN KEY (captured_by,organization_id) REFERENCES users(id,organization_id),
  FOREIGN KEY (prior_reading_id,nozzle_id) REFERENCES nozzle_meter_readings(id,nozzle_id),
  UNIQUE (organization_id,command_id),
  UNIQUE (id,nozzle_id),
  CHECK ((reading_type='meter_change' AND length(btrim(COALESCE(change_reason,'')))>0 AND length(btrim(COALESCE(new_serial,'')))>0)
      OR (reading_type<>'meter_change' AND old_serial IS NULL AND new_serial IS NULL AND change_reason IS NULL)),
  CHECK (prior_value IS NULL OR prior_value >= 0),
  CHECK (reading_type='baseline' OR prior_value IS NOT NULL)
);

CREATE INDEX nozzle_meter_history_idx ON nozzle_meter_readings(organization_id,branch_id,nozzle_id,captured_at DESC,id DESC);
ALTER TABLE nozzle_meter_states ADD CONSTRAINT nozzle_meter_state_last_reading_fk
  FOREIGN KEY (last_reading_id,nozzle_id) REFERENCES nozzle_meter_readings(id,nozzle_id);

CREATE FUNCTION prevent_nozzle_meter_reading_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'nozzle_meter_readings is append-only' USING ERRCODE = '55000';
END;
$$;
CREATE TRIGGER nozzle_meter_readings_immutable BEFORE UPDATE OR DELETE ON nozzle_meter_readings
FOR EACH ROW EXECUTE FUNCTION prevent_nozzle_meter_reading_mutation();
