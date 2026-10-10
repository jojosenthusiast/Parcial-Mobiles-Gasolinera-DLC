import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

let source = await readFile(new URL('../src/procurement/procurement.service.ts', import.meta.url), 'utf8');
source = source.replace(/^import .+?;\r?\n/gm, '').replace('@Injectable()', '').replace(/@Inject\([^)]+\) /g, '');
const { ProcurementService } = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source, { mode: 'transform' })).toString('base64')}`);

const organizationId = '11111111-1111-4111-8111-111111111111';
const branchId = '22222222-2222-4222-8222-222222222222';

test('purchase order search escapes LIKE metacharacters and preserves branch/status cursor scope', async () => {
  let call;
  const pool = { query: async (sql, values) => { call = { sql, values }; return { rows: [] }; } };
  const service = new ProcurementService(pool, {});
  const result = await service.listPurchaseOrders(branchId, { organizationId }, 'approved', undefined, 25, '  PO%_\\1  ');

  assert.deepEqual(result, { data: [], meta: { limit: 25, nextCursor: null } });
  assert.match(call.sql, /po\.organization_id=\$1 AND po\.branch_id=\$2/);
  assert.match(call.sql, /\$3::text IS NULL OR po\.status=\$3/);
  assert.match(call.sql, /purchase_order_lines ql JOIN fuel_products fp/);
  assert.match(call.sql, /ESCAPE '\\'/);
  assert.deepEqual(call.values, [organizationId, branchId, 'approved', null, null, 'PO\\%\\_\\\\1', 26]);
});
