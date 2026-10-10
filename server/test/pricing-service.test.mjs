import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

let source = await readFile(new URL('../src/pricing/pricing.service.ts', import.meta.url), 'utf8');
source = source.replace(/^import .+?;\n/gm, '').replace('@Injectable()', '').replace(/@Inject\([^)]+\) /g, '');
const { PricingService } = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source, { mode: 'transform' })).toString('base64')}`);

const organizationId = '11111111-1111-4111-8111-111111111111';
const branchId = '22222222-2222-4222-8222-222222222222';
const productId = '33333333-3333-4333-8333-333333333333';

test('fuel price board includes the catalog name and keeps branch and organization scope', async () => {
  const calls = [];
  const pool = {
    query: async (sql, values) => {
      calls.push({ sql, values });
      return { rows: [{ id: productId, fuelProductId: productId, productName: 'Gasolina Regular', serviceMode: 'self_service' }] };
    },
  };
  const service = new PricingService(pool, {});
  const result = await service.prices(branchId, { organizationId }, productId, 'self_service');

  assert.equal(result.current[0].productName, 'Gasolina Regular');
  assert.equal(result.upcoming[0].productName, 'Gasolina Regular');
  assert.equal(calls.length, 2);
  for (const call of calls) {
    assert.match(call.sql, /JOIN fuel_products p ON p\.id=v\.fuel_product_id AND p\.organization_id=v\.organization_id/);
    assert.match(call.sql, /v\.organization_id=\$1/);
    assert.match(call.sql, /v\.branch_id=\$2/);
    assert.deepEqual(call.values, [organizationId, branchId, productId, 'self_service']);
  }
});
