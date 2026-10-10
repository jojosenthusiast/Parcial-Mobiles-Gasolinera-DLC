ALTER TABLE report_export_jobs DROP CONSTRAINT report_export_jobs_state_check;
ALTER TABLE report_export_jobs ADD CONSTRAINT report_export_jobs_state_check
 CHECK(state IN('queued','running','succeeded','failed','cancelled'));
