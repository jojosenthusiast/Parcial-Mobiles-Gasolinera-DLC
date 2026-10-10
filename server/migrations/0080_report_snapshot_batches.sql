-- Keep large report snapshots in bounded rows instead of one oversized JSON value.
DO $$ DECLARE c record; BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid='report_runs'::regclass AND contype='c'
      AND (pg_get_constraintdef(oid) ILIKE '%row_count%' OR pg_get_constraintdef(oid) ILIKE '%jsonb_array_length(rows_snapshot)%')
  LOOP EXECUTE format('ALTER TABLE report_runs DROP CONSTRAINT %I',c.conname); END LOOP;
END $$;

ALTER TABLE report_runs
  ADD COLUMN rows_externalized boolean NOT NULL DEFAULT false,
  ADD COLUMN snapshot_complete boolean NOT NULL DEFAULT true;

ALTER TABLE report_runs
  ADD CONSTRAINT report_runs_row_count_limit CHECK(row_count BETWEEN 0 AND 100000),
  ADD CONSTRAINT report_runs_snapshot_shape CHECK(
    (rows_externalized AND jsonb_array_length(rows_snapshot)=0)
    OR (NOT rows_externalized AND jsonb_array_length(rows_snapshot)=row_count)
  );

CREATE TABLE report_run_rows (
  report_run_id uuid NOT NULL REFERENCES report_runs(id),
  organization_id uuid NOT NULL,
  row_index integer NOT NULL CHECK(row_index>=0),
  row_data jsonb NOT NULL CHECK(jsonb_typeof(row_data)='object'),
  PRIMARY KEY(report_run_id,row_index)
);
CREATE INDEX report_run_rows_org_idx ON report_run_rows(organization_id,report_run_id,row_index);
ALTER TABLE report_run_rows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE report_run_rows FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON TABLE report_run_rows TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON report_run_rows FOR SELECT TO dlc_api_runtime
  USING(EXISTS(SELECT 1 FROM report_runs r WHERE r.id=report_run_rows.report_run_id AND r.organization_id=report_run_rows.organization_id));
CREATE POLICY dlc_api_insert ON report_run_rows FOR INSERT TO dlc_api_runtime
  WITH CHECK(EXISTS(SELECT 1 FROM report_runs r WHERE r.id=report_run_rows.report_run_id AND r.organization_id=report_run_rows.organization_id
    AND r.rows_externalized AND NOT r.snapshot_complete));

CREATE OR REPLACE FUNCTION guard_report_run() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='UPDATE' AND OLD.snapshot_complete=false AND NEW.snapshot_complete=true
     AND OLD.rows_externalized=true AND NEW.rows_externalized=true
     AND NEW.row_count BETWEEN 0 AND 100000
     AND NEW.row_count=(SELECT count(*) FROM report_run_rows WHERE report_run_id=OLD.id)
     AND (NEW.row_count=0 OR (SELECT min(row_index)=0 AND max(row_index)=NEW.row_count-1
       FROM report_run_rows WHERE report_run_id=OLD.id))
     AND (to_jsonb(OLD)-ARRAY['snapshot_complete','row_count','source_watermark'])
       =(to_jsonb(NEW)-ARRAY['snapshot_complete','row_count','source_watermark']) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Report snapshots are immutable after finalization' USING ERRCODE='55000';
END; $$;

CREATE FUNCTION guard_report_run_row() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'Report snapshot rows are immutable' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER report_run_rows_immutable BEFORE UPDATE OR DELETE ON report_run_rows FOR EACH ROW EXECUTE FUNCTION guard_report_run_row();
REVOKE ALL ON FUNCTION guard_report_run_row() FROM PUBLIC,anon,authenticated,service_role;
