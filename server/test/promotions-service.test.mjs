import test from 'node:test';
import assert from 'node:assert/strict';
import { PromotionsService } from '../dist/promotions/promotions.service.js';

const organizationId = '2f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e';

test('public promotion feed is always scoped to the server-configured organization', async () => {
  let sql = '', values;
  const service = new PromotionsService({ query: async (statement, params) => { sql = String(statement); values = params; return { rows: [] }; } }, {}, {}, { get: key => key === 'CUSTOMER_ORGANIZATION_ID' ? organizationId : undefined });
  await service.publicFeed('4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e');
  assert.match(sql, /p\.organization_id=\$1/);
  assert.match(sql, /targetBranchIds.*@>/s);
  assert.deepEqual(values, [organizationId, '4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e']);
});

test('public promotion feed fails closed when the customer organization is not configured', async () => {
  let queried = false;
  const service = new PromotionsService({ query: async () => { queried = true; return { rows: [] }; } }, {}, {}, { get: () => undefined });
  await assert.rejects(service.publicFeed(), /dominio de promociones no está configurado/);
  assert.equal(queried, false);
});

test('network audience resolves zones and freezes only branches meeting the metric threshold', async () => {
  const east = '4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e';
  const west = '5f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e';
  const pool = { query: async sql => String(sql).includes('WITH sales30')
    ? { rows: [{ branch_id: east, observed_value: '12000.00', eligible: true }, { branch_id: west, observed_value: '3000.00', eligible: false }] }
    : { rows: [{ id: east, timezone: 'America/El_Salvador' }, { id: west, timezone: 'America/El_Salvador' }] } };
  const service = new PromotionsService(pool, { capabilities: async () => ['promotion.network.manage'] }, {}, {});
  const result = await service.resolveTargeting({ organizationId, userId: 'user' }, {
    scope: 'network', timeZone: 'America/El_Salvador', targetZones: ['oriental'],
    targetMetric: { metric: 'sales_usd_30d', threshold: '10000' },
  });
  assert.deepEqual(result.targetBranchIds, [east]);
  assert.deepEqual(result.targetMetric.includedBranches, [{ branchId: east, observedValue: '12000.00' }]);
  assert.equal(result.targetMetric.windowDays, 30);
  assert.ok(result.targetMetric.asOf);
});
