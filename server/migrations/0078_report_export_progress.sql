ALTER TABLE report_export_jobs
 ADD COLUMN progress_rows integer NOT NULL DEFAULT 0 CHECK(progress_rows>=0),
 ADD COLUMN progress_total integer NOT NULL DEFAULT 0 CHECK(progress_total>=0),
 ADD CONSTRAINT report_export_progress_bounds CHECK(progress_rows<=progress_total);
