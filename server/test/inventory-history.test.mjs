import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

let source = await readFile(new URL('../src/inventory/fuel-inventory.service.ts', import.meta.url), 'utf8');
source = source.replace(/^import .+?;\n/gm, '').replace('@Injectable()', '').replace(/@Inject\([^)]+\) /g, '');
const { FuelInventoryService } = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source, { mode: 'transform' })).toString('base64')}`);

const organizationId = '11111111-1111-4111-8111-111111111111';
const branchId = '22222222-2222-4222-8222-222222222222';
const tankId = '33333333-3333-4333-8333-333333333333';
const rows = [
  { id: '44444444-4444-4444-8444-444444444444', occurredAt: '2026-10-08T12:00:00.000Z' },
  { id: '55555555-5555-4555-8555-555555555555', occurredAt: '2026-10-08T11:00:00.000Z' },
  { id: '66666666-6666-4666-8666-666666666666', occurredAt: '2026-10-08T10:00:00.000Z' },
];

test('tank movement history returns a stable compound cursor for the next page', async () => {
  const calls = [];
  let movementRows = rows;
  const pool = { query: async (sql, values) => {
    calls.push({ sql, values });
    if (sql.startsWith('SELECT 1 FROM tanks')) return { rowCount: 1, rows: [{}] };
    return { rows: movementRows };
  } };
  const service = new FuelInventoryService(pool, {});
  const principal = { organizationId };

  const first = await service.history(branchId, tankId, principal, 2);
  assert.deepEqual(first.data.map(row => row.id), rows.slice(0, 2).map(row => row.id));
  const decoded = Buffer.from(first.meta.nextCursor, 'base64url').toString('utf8');
  assert.equal(decoded, `${rows[1].occurredAt}|${rows[1].id}`);

  movementRows = [rows[2]];
  const second = await service.history(branchId, tankId, principal, 2, first.meta.nextCursor);
  assert.deepEqual(second.data.map(row => row.id), [rows[2].id]);
  assert.equal(second.meta.nextCursor, null);
  const secondQuery = calls.at(-1);
  assert.match(secondQuery.sql, /\(occurred_at,id\)<\(\$4::timestamptz,\$5::uuid\)/);
  assert.deepEqual(secondQuery.values.slice(3), [rows[1].occurredAt, rows[1].id, 3]);
});
