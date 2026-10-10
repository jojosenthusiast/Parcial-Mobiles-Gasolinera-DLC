import test from 'node:test';
import assert from 'node:assert/strict';
import { CustomerService } from '../dist/customers/customer.service.js';

const identity = { authUserId: '4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e', email: 'customer@example.test' };
const organizationId = '2f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e';

function serviceFor(rows) {
  return new CustomerService({
    query: async sql => String(sql).includes('WITH balance AS')
      ? { rows: [rows] }
      : { rows: [{ id: 'customer-account-id' }] },
  }, { get: key => key === 'CUSTOMER_ORGANIZATION_ID' ? organizationId : undefined }, {});
}

test('customer loyalty returns the active redemption rate and server-calculated USD value', async () => {
  const service = serviceFor({ balance: '125', earned_program: true, redemption_rate: '0.01', available_value: '1.25' });
  const result = await service.loyalty(identity);
  assert.deepEqual(result, {
    pointsBalance: '125',
    earnedProgram: true,
    canRedeem: true,
    redemptionUsdPerPoint: '0.01',
    availableValueUsd: '1.25',
    message: 'Los puntos se acreditan sobre la parte elegible pagada con dinero; la parte cubierta con puntos no genera puntos.',
  });
});

test('customer loyalty does not imply cash value when no redemption rate is active', async () => {
  const result = await serviceFor({ balance: '125', earned_program: true, redemption_rate: '0', available_value: '0.00' }).loyalty(identity);
  assert.equal(result.pointsBalance, '125');
  assert.equal(result.canRedeem, false);
  assert.equal(result.availableValueUsd, '0.00');
});
