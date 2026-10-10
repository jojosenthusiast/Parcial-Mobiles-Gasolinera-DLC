-- Cover tenant-scoped foreign keys and keep row paging on the primary-key index.
DROP INDEX IF EXISTS report_run_rows_org_idx;
CREATE INDEX report_runs_branch_fk_idx ON report_runs(branch_id,organization_id);
CREATE INDEX report_runs_creator_fk_idx ON report_runs(created_by,organization_id);
