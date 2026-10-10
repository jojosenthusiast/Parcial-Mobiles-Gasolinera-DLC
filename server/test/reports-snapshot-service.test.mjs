import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
let source = await readFile(new URL('../src/reports/reports.service.ts', import.meta.url), 'utf8');
source = source.replace(/^import .+?;\n/gm, '').replace('@Injectable()', '').replace(/@Inject\([^)]+\) /g, '');
source = `import { createHash } from 'node:crypto';\n` +
  ['BadRequestException','ConflictException','ForbiddenException','NotFoundException','TooManyRequestsException'].map(name => `class ${name} extends Error {}`).join('\n') +
  '\n' + source;
const { ReportsService, appendReportRowsWithinMemoryLimit } = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source, { mode: 'transform' })).toString('base64')}`);
const id = '11111111-1111-4111-8111-111111111111';
const principal = { organizationId: id, userId: id, sessionId: id, permissionVersion: 1 };

test('create persiste reportes en páginas de 500 bajo snapshot repetible y finaliza el conteo', async () => {
  const calls = [];
  const clientQuery = async (sql, values = []) => {
    calls.push({ sql, values });
    if (sql === 'SELECT clock_timestamp() AS as_of') return { rows: [{ as_of: new Date('2026-10-08T12:00:00Z') }] };
    if (sql.startsWith('SELECT id,request_hash,created_by,branch_id')) return { rows: [] };
    if (sql.startsWith('INSERT INTO report_runs')) return { rows: [{ id }] };
    if (sql.startsWith('SELECT c.operational_date::text')) {
      const offset = values.at(-1);
      const count = offset === 1000 ? 1 : offset < 1000 ? 500 : 0;
      return { rows: Array.from({ length: count }, (_, i) => ({ operationalDate: '2026-10-08', slot: 1,
        sourceAt: new Date(Date.UTC(2026, 9, 8, 12, 0, 0) + (offset + i) * 1000) })) };
    }
    return { rows: [], rowCount: 1 };
  };
  const pool = { connect: async () => ({ query: clientQuery, release() {} }),
    query: async (sql) => sql.includes('SELECT timezone') ? { rows: [{ timezone: 'America/El_Salvador' }] } : { rows: [] } };
  const auth = { capabilities: async () => ['report.read', 'cut.read', 'sale.read'] };
  const service = new ReportsService(pool, auth, { appendTransaction: async () => {} }, {});
  let result;
  try { result = await service.create(id, principal, { type: 'closed_cuts', from: '2026-10-08', to: '2026-10-08', commandId: id }, id); }
  catch (error) { throw new Error(`create: ${error.message}`); }
  assert.equal(result.data.rowCount, 1001);
  assert.deepEqual(calls.filter(x => x.sql.startsWith('INSERT INTO report_run_rows')).map(x => x.values[2]), [0, 500, 1000]);
  assert.equal(calls.filter(x => x.sql.startsWith('SELECT c.operational_date::text')).length, 3);
  assert.ok(calls.some(x => x.sql === 'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ'));
  const finalize = calls.find(x => x.sql.startsWith('UPDATE report_runs SET row_count'));
  assert.deepEqual(finalize.values.slice(0, 2), [id, 1001]);
  assert.equal(calls.at(-1).sql, 'COMMIT');
});

test('create aborta y revierte snapshots que exceden 100,000 filas', async () => {
  let insertBatches = 0, rolledBack = false, finalized = false;
  const clientQuery = async (sql, values = []) => {
    if (sql === 'SELECT clock_timestamp() AS as_of') return { rows: [{ as_of: new Date('2026-10-08T12:00:00Z') }] };
    if (sql.startsWith('SELECT id,request_hash,created_by,branch_id')) return { rows: [] };
    if (sql.startsWith('INSERT INTO report_runs')) return { rows: [{ id }] };
    if (sql.startsWith('SELECT c.operational_date::text')) {
      const offset = values.at(-1);
      return { rows: Array.from({ length: offset < 100000 ? 500 : 1 }, () => ({ operationalDate: '2026-10-08', slot: 1 })) };
    }
    if (sql.startsWith('INSERT INTO report_run_rows')) { insertBatches += 1; return { rows: [], rowCount: 500 }; }
    if (sql.startsWith('UPDATE report_runs SET row_count')) { finalized = true; return { rows: [] }; }
    if (sql === 'ROLLBACK') { rolledBack = true; return { rows: [] }; }
    return { rows: [], rowCount: 1 };
  };
  const pool = { connect: async () => ({ query: clientQuery, release() {} }),
    query: async sql => sql.includes('SELECT timezone') ? { rows: [{ timezone: 'America/El_Salvador' }] } : { rows: [] } };
  const service = new ReportsService(pool, { capabilities: async () => ['report.read', 'cut.read', 'sale.read'] }, { appendTransaction: async () => {} }, {});
  await assert.rejects(service.create(id, principal, { type: 'closed_cuts', from: '2026-10-08', to: '2026-10-08', commandId: id }, id), /100,000 filas/);
  assert.equal(insertBatches, 200);
  assert.equal(rolledBack, true);
  assert.equal(finalized, false);
});

test('serialización de reportes limita el tamaño fuente antes de cargar todos los lotes', () => {
  const rows = [{ value: 'uno' }];
  const currentBytes = Buffer.byteLength(JSON.stringify(rows[0]));
  assert.throws(() => appendReportRowsWithinMemoryLimit(rows, [{ value: 'dos' }], currentBytes, currentBytes + 1), /64 MiB de datos fuente/);
  assert.equal(rows.length, 1, 'el lote que rebasa el límite no debe agregarse parcialmente');
  const nextBytes = appendReportRowsWithinMemoryLimit(rows, [{ value: 'dos' }], currentBytes, currentBytes + Buffer.byteLength('{"value":"dos"}'));
  assert.equal(nextBytes, Buffer.byteLength('{"value":"uno"}') + Buffer.byteLength('{"value":"dos"}'));
  assert.equal(rows.length, 2);
});

test('page obtiene 100 filas del almacenamiento externo en vez de usar el JSON legado', async () => {
  const calls = [];
  const pool = { query: async (sql, values) => {
    calls.push({ sql, values });
    if (sql.includes('SELECT * FROM report_runs')) return { rows: [{ id, report_type: 'closed_cuts',
      filter_snapshot: { type: 'closed_cuts', from: '2026-10-08', to: '2026-10-08' }, row_count: 220,
      rows_externalized: true, snapshot_complete: true, rows_snapshot: [], as_of: new Date(), unit: 'liter', timezone: 'America/El_Salvador' }] };
    if (sql.includes('SELECT row_data FROM report_run_rows')) return { rows: [{ row_data: { slot: 2, salesUsd: '20.00' } }] };
    return { rows: [{ timezone: 'America/El_Salvador' }] };
  } };
  const service = new ReportsService(pool, { capabilities: async () => ['report.read','cut.read','sale.read'] }, {}, {});
  let result;
  try { result = await service.page(id, id, principal, '100'); }
  catch (error) { throw new Error(`page: ${error.message}`); }
  assert.equal(result.data.rowCount, 220);
  assert.equal(result.data.rows[0].slot, '2');
  const pageQuery = calls.find(x => x.sql.includes('SELECT row_data FROM report_run_rows'));
  assert.deepEqual(pageQuery.values, [id, id, 100, 100]);
  assert.match(pageQuery.sql, /row_index>=\$4 ORDER BY row_index LIMIT \$3/);
});
