CREATE INDEX report_export_expiry_idx ON report_export_jobs(expires_at) WHERE state IN('succeeded','failed');
CREATE INDEX report_export_queue_retention_idx ON background_jobs(created_at)
 WHERE job_type='report.export.generate' AND state IN('succeeded','dead');
GRANT DELETE ON TABLE report_export_jobs,background_jobs TO dlc_api_runtime;
CREATE POLICY dlc_api_delete ON report_export_jobs FOR DELETE TO dlc_api_runtime
 USING(state IN('succeeded','failed') AND expires_at<clock_timestamp());
CREATE POLICY dlc_api_delete ON background_jobs FOR DELETE TO dlc_api_runtime
 USING(job_type='report.export.generate' AND state IN('succeeded','dead') AND created_at<clock_timestamp()-interval '30 days');
