import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const service = await readFile(new URL('../../src/reports/reports.service.ts', import.meta.url), 'utf8');
const migration = await readFile(new URL('../../migrations/0080_report_snapshot_batches.sql', import.meta.url), 'utf8');
const indexMigration = await readFile(new URL('../../migrations/0081_report_snapshot_indexes.sql', import.meta.url), 'utf8');
const finalizationMigration = await readFile(new URL('../../migrations/0111_report_run_finalize_operational_assets.sql', import.meta.url), 'utf8');

test('reportes toman snapshot consistente en lotes y conservan paginación normalizada', () => {
  assert.match(service, /SET TRANSACTION ISOLATION LEVEL REPEATABLE READ/);
  assert.match(service, /batchSize=500/);
  assert.match(service, /report_run_rows\(report_run_id,organization_id,row_index,row_data\)/);
  assert.match(service, /LIMIT \$\$\{args\.length\+1\} OFFSET \$\$\{args\.length\+2\}/);
  assert.match(service, /row_index>=\$4 ORDER BY row_index LIMIT \$3/);
  assert.match(service, /snapshotRows\(r,p,offset,100\)/);
  assert.match(service, /El reporte supera 100,000 filas/);
  assert.match(service, /MAX_REPORT_EXPORT_SOURCE_BYTES=64\*1024\*1024/);
  assert.match(service, /appendReportRowsWithinMemoryLimit\(rows,await this\.snapshotRows/);
  assert.doesNotMatch(service, /rows\.length>10000\)/);
});

test('la migración conserva snapshots antiguos y protege la nueva tabla por organización', () => {
  assert.match(migration, /rows_externalized boolean NOT NULL DEFAULT false/);
  assert.match(migration, /snapshot_complete boolean NOT NULL DEFAULT true/);
  assert.match(migration, /CREATE TABLE report_run_rows/);
  assert.match(migration, /row_count BETWEEN 0 AND 100000/);
  assert.match(migration, /report_run_rows\.organization_id/);
  assert.match(migration, /Report snapshot rows are immutable/);
  assert.match(indexMigration, /report_runs_branch_fk_idx ON report_runs\(branch_id,organization_id\)/);
  assert.match(indexMigration, /report_runs_creator_fk_idx ON report_runs\(created_by,organization_id\)/);
  assert.match(indexMigration, /DROP INDEX IF EXISTS report_run_rows_org_idx/);
});

test('report-run finalization grants only the immutable-transition columns to the API runtime', () => {
  assert.match(finalizationMigration, /GRANT\s+UPDATE\s*\(\s*snapshot_complete\s*,\s*row_count\s*,\s*source_watermark\s*\)\s+ON\s+TABLE\s+report_runs\s+TO\s+dlc_api_runtime/i);
  assert.doesNotMatch(finalizationMigration, /GRANT\s+UPDATE\s+ON\s+TABLE\s+report_runs\s+TO\s+dlc_api_runtime/i);
  assert.match(finalizationMigration, /CREATE\s+POLICY\s+dlc_api_finalize\s+ON\s+report_runs\s+FOR\s+UPDATE\s+TO\s+dlc_api_runtime\s+USING\s*\(\s*snapshot_complete\s*=\s*false\s*\)\s+WITH\s+CHECK\s*\(\s*snapshot_complete\s*=\s*true\s*\)/i);
});