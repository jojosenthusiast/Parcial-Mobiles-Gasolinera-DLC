DROP INDEX report_export_expiry_idx;
CREATE INDEX report_export_expiry_idx ON report_export_jobs(expires_at) WHERE state IN('succeeded','failed','cancelled');
DROP POLICY dlc_api_delete ON report_export_jobs;
CREATE POLICY dlc_api_delete ON report_export_jobs FOR DELETE TO dlc_api_runtime
 USING(state IN('succeeded','failed','cancelled') AND expires_at<clock_timestamp());
