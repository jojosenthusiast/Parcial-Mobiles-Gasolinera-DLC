import assert from 'node:assert/strict';
import test from 'node:test';
import { manualAccountDeliveryAllowed } from '../dist/auth/user-admin.service.js';

test('outside production manual delivery is always allowed', () => {
  assert.equal(manualAccountDeliveryAllowed({ NODE_ENV: 'development' }), true);
  assert.equal(manualAccountDeliveryAllowed({}), true);
});

test('production blocks manual delivery unless the operator opts in explicitly', () => {
  assert.equal(manualAccountDeliveryAllowed({ NODE_ENV: 'production' }), false);
  assert.equal(manualAccountDeliveryAllowed({ NODE_ENV: 'production', ALLOW_MANUAL_ACCOUNT_DELIVERY: 'false' }), false);
  assert.equal(manualAccountDeliveryAllowed({ NODE_ENV: 'production', ALLOW_MANUAL_ACCOUNT_DELIVERY: '1' }), false);
  assert.equal(manualAccountDeliveryAllowed({ NODE_ENV: 'production', ALLOW_MANUAL_ACCOUNT_DELIVERY: 'true' }), true);
});
