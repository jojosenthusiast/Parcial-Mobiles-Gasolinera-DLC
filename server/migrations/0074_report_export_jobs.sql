CREATE TABLE report_export_jobs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 branch_id uuid NOT NULL,
 report_run_id uuid NOT NULL,
 requested_by uuid NOT NULL,
 session_id uuid NOT NULL,
 format text NOT NULL CHECK(format IN('csv','xlsx','pdf')),
 command_id uuid NOT NULL,
 request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 state text NOT NULL DEFAULT 'queued' CHECK(state IN('queued','running','succeeded','failed')),
 processing_attempt integer NOT NULL DEFAULT 0 CHECK(processing_attempt>=0),
 filename text,
 content_type text,
 content bytea,
 error_message text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 started_at timestamptz,
 completed_at timestamptz,
 expires_at timestamptz NOT NULL DEFAULT (clock_timestamp()+interval '7 days'),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(report_run_id) REFERENCES report_runs(id),
 FOREIGN KEY(requested_by,organization_id) REFERENCES users(id,organization_id),
 FOREIGN KEY(session_id) REFERENCES auth_sessions(id),
 UNIQUE(organization_id,command_id),
 CHECK((state='succeeded' AND filename IS NOT NULL AND content_type IS NOT NULL AND content IS NOT NULL AND completed_at IS NOT NULL)
    OR state<>'succeeded'),
 CHECK(content IS NULL OR octet_length(content)<=33554432),
 CHECK(expires_at>created_at)
);
CREATE INDEX report_export_owner_idx ON report_export_jobs(organization_id,branch_id,requested_by,created_at DESC);
CREATE INDEX report_export_ready_idx ON report_export_jobs(created_at) WHERE state IN('queued','running');
ALTER TABLE report_export_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE report_export_jobs FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT,UPDATE ON TABLE report_export_jobs TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON report_export_jobs FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON report_export_jobs FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_update ON report_export_jobs FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
