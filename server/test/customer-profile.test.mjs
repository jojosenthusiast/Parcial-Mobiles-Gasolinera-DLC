import test from 'node:test';
import assert from 'node:assert/strict';
import { CustomerService } from '../dist/customers/customer.service.js';

const identity = { authUserId: '4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e', email: 'customer@example.test' };
const organizationId = '2f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e';
const input = { fullName: '  Ada Customer  ', phone: '+503 7000-0000', termsVersion: 'terms-v3', termsAccepted: true, communicationsConsent: false };

function create(query) {
  return new CustomerService({ query }, { get: key => ({ CUSTOMER_TERMS_VERSION: 'terms-v3', CUSTOMER_ORGANIZATION_ID: organizationId })[key] }, { appendTransaction: async () => {} });
}

test('profile creation uses server-owned organization and accepted terms version', async () => {
  const calls = [];
  const service = create(async (sql, values) => {
    calls.push({ sql: String(sql), values });
    return { rows: [{ id: 'profile-id', fullName: 'Ada Customer' }] };
  });
  const result = await service.profile(identity, input);
  assert.equal(result.id, 'profile-id');
  assert.match(calls[0].sql, /ON CONFLICT \(organization_id, auth_user_id\) DO UPDATE/);
  assert.match(calls[0].sql, /WHERE customer_accounts.status='active'/);
  assert.equal(calls[0].values[0], organizationId);
  assert.equal(calls[0].values[1], identity.authUserId);
  assert.equal(calls[0].values[2], 'customer@example.test');
  assert.equal(calls[0].values[3], 'Ada Customer');
  assert.equal(calls[0].values[5], 'terms-v3');
  assert.equal(calls[0].values[6], false);
});

test('profile rejects a stale or caller-invented terms version before writing', async () => {
  let queried = false;
  const service = create(async () => { queried = true; return { rows: [] }; });
  await assert.rejects(service.profile(identity, { ...input, termsVersion: 'production-v99' }), /condiciones cambiaron/);
  assert.equal(queried, false);
});

test('profile requires explicit acceptance of the current terms before writing', async () => {
  let queried = false;
  const service = create(async () => { queried = true; return { rows: [] }; });
  await assert.rejects(service.profile(identity, { ...input, termsAccepted: false }), /aceptar las condiciones/);
  assert.equal(queried, false);
});
