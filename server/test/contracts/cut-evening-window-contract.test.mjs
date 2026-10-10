import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

const spec = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
const migrationBytes = await readFile(new URL('../../migrations/0110_cut_evening_window.sql', import.meta.url), 'utf8');
const pasteSql = await readFile(new URL('../../scripts/sql/qa-migration-0110.sql', import.meta.url), 'utf8');
const smoke = await readFile(new URL('../sql/cut-evening-window-smoke.sql', import.meta.url), 'utf8');
const service = await readFile(new URL('../../src/cuts/cuts.service.ts', import.meta.url), 'utf8');
const seeder = await readFile(new URL('../../scripts/seed-qa-operations.mjs', import.meta.url), 'utf8');

test('migration 0110 is CRLF like its neighbours, transactional and keeps the integrity rules', () => {
  assert.match(migrationBytes, /^BEGIN;\r\n[\s\S]*COMMIT;\r\n$/);
  assert.ok(!/[^\r]\n/.test(migrationBytes), 'every line ends with CRLF (the checksum depends on exact bytes)');
  assert.match(migrationBytes, /ADD COLUMN IF NOT EXISTS day_end time/);
  assert.match(migrationBytes, /CREATE OR REPLACE FUNCTION previous_operational_cut\(target_cut uuid\)/);
  assert.match(migrationBytes, /Operational cut windows of a branch cannot overlap/);
  assert.match(migrationBytes, /first_cut\.ends_at<>second_cut\.starts_at/, 'the two windows of a day stay contiguous');
  assert.match(migrationBytes, /ON CONFLICT ON CONSTRAINT operational_cuts_branch_id_operational_date_slot_key/, 'one cut per window per day');
  for (const fn of ['generate_operational_cuts', 'capture_cut_meter', 'prepare_operational_cut', 'close_operational_cut']) {
    assert.match(migrationBytes, new RegExp(`CREATE OR REPLACE FUNCTION ${fn}\\(`));
  }
  assert.ok(!/pc\.ends_at=c\.starts_at/.test(migrationBytes), 'no strict adjacency lookup remains outside previous_operational_cut');
});

test('qa-migration-0110.sql embeds the migration and records its exact sha256 in schema_migrations', () => {
  const checksum = createHash('sha256').update(migrationBytes).digest('hex');
  assert.ok(pasteSql.includes(`'${checksum}'`), 'paste SQL carries the checksum of the committed migration bytes');
  assert.match(pasteSql, /INSERT INTO schema_migrations \(version, checksum\) VALUES \('0110_cut_evening_window\.sql'/);
  assert.match(pasteSql, /^BEGIN;/m);
  assert.equal(pasteSql.match(/^COMMIT;/gm)?.length, 1);
  assert.equal(pasteSql.match(/^BEGIN;/gm)?.length, 1, 'single transaction');
  assert.ok(pasteSql.includes('ADD COLUMN IF NOT EXISTS day_end time'));
});

test('OpenAPI documents the optional evening end and the non-cut period', () => {
  const operation = spec.paths['/branches/{branchId}/cuts/profiles'].post;
  const schema = operation.requestBody.content['application/json'].schema;
  assert.deepEqual(schema.required, ['effectiveDate']);
  assert.ok(schema.properties.dayEnd);
  assert.match(operation.description, /22:00/);
  assert.match(operation.description, /NO es un corte/);
  assert.ok(spec.components.schemas.OperationalCut.properties.accountingStartsAt);
});

test('academicLab22 fixes morning 06:00-14:00 and evening 14:00-22:00 in service, seeder and smoke', () => {
  assert.match(service, /ACADEMIC_CUT_SCHEDULE=\{dayStart:'06:00',splitAt:'14:00',dayEnd:'22:00'\}/);
  assert.match(seeder, /CUT_SCHEDULE = \{ dayStart: '06:00', splitAt: '14:00', dayEnd: '22:00' \}/);
  assert.match(seeder, /legacy/i, 'the seeder knows how to cope with branches that already hold 14:00-06:00 cuts');
  assert.match(smoke, /'2026-10-01 20:00\+00' AND ends_at='2026-10-02 04:00\+00'/);
});
