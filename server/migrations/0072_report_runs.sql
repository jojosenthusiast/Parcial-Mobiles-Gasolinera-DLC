-- Immutable, bounded report snapshots: screen and export read the same rows.
CREATE TABLE report_runs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,
 branch_id uuid NOT NULL,report_type text NOT NULL CHECK(report_type IN('closed_cuts','fuel_sales','tank_movements','incidents','purchase_orders')),
 filter_snapshot jsonb NOT NULL CHECK(jsonb_typeof(filter_snapshot)='object'),
 rows_snapshot jsonb NOT NULL CHECK(jsonb_typeof(rows_snapshot)='array'),
 row_count integer NOT NULL CHECK(row_count>=0 AND row_count<=10000),
 as_of timestamptz NOT NULL,source_watermark timestamptz,
 timezone text NOT NULL,unit text NOT NULL CHECK(unit IN('liter','usd','record')),
 currency text NOT NULL DEFAULT 'USD' CHECK(currency='USD'),
 created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL DEFAULT (clock_timestamp()+interval '7 days'),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id),
 CHECK(jsonb_array_length(rows_snapshot)=row_count),
 CHECK(expires_at>created_at)
);
CREATE INDEX report_runs_owner_idx ON report_runs(organization_id,created_by,created_at DESC);
CREATE FUNCTION guard_report_run() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'Report snapshots cannot be edited or deleted' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER report_runs_immutable BEFORE UPDATE OR DELETE ON report_runs FOR EACH ROW EXECUTE FUNCTION guard_report_run();
ALTER TABLE report_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE report_runs FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON TABLE report_runs TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON report_runs FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON report_runs FOR INSERT TO dlc_api_runtime WITH CHECK(true);
REVOKE ALL ON FUNCTION guard_report_run() FROM PUBLIC,anon,authenticated,service_role;
