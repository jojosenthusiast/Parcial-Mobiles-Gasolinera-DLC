import test from 'node:test';
import assert from 'node:assert/strict';
import { CustomerPointsPaymentService } from '../dist/customers/customer-points-payment.service.js';

const org = '20000000-0000-4000-8000-000000000002';
const customer = '80000000-0000-4000-8000-000000000008';
const quoteId = '60000000-0000-4000-8000-000000000006';
const commandId = '40000000-0000-4000-8000-000000000004';
const saleId = '70000000-0000-4000-8000-000000000007';
const identity = { authUserId: '10000000-0000-4000-8000-000000000001' };

function fixture() {
  const state = { quote: { id: quoteId, sale_id: saleId, status: 'pending', expires_at: new Date(Date.now() + 60_000), decision_command_id: null, decision_hash: null }, updates: 0 };
  const client = { async query(sql, values = []) {
    const text = String(sql).replace(/\s+/g, ' ').trim();
    if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(text) || text.includes('pg_advisory_xact_lock')) return { rows: [], rowCount: 0 };
    if (text.startsWith('SELECT id,sale_id,status,expires_at,decision_command_id,decision_hash')) return { rows: [state.quote], rowCount: 1 };
    if (text.startsWith('SELECT 1 FROM customer_point_payment_quotes WHERE organization_id=$1 AND decision_command_id=$2')) return { rows: [], rowCount: 0 };
    if (text.startsWith('UPDATE customer_point_payment_quotes')) {
      state.updates++;
      state.quote = { ...state.quote, status: 'declined', decision_command_id: values[3], decision_hash: values[4] };
      return { rows: [{ id: quoteId, saleId, status: 'declined' }], rowCount: 1 };
    }
    throw new Error(`Unexpected SQL: ${text}`);
  }, release() {} };
  const pool = { connect: async () => client, async query(sql) {
    if (String(sql).includes('FROM customer_accounts WHERE organization_id=$1 AND auth_user_id=$2')) return { rows: [{ id: customer }] };
    throw new Error(`Unexpected pool SQL: ${sql}`);
  } };
  const service = new CustomerPointsPaymentService(pool, {}, {}, { get: () => org });
  return { service, state };
}

test('customer decline is durable and idempotent only for the original decision command', async () => {
  const f = fixture();
  const first = await f.service.decline(identity, quoteId, commandId);
  assert.equal(first.data.status, 'declined');
  assert.equal(first.data.idempotentReplay, false);
  const replay = await f.service.decline(identity, quoteId, commandId);
  assert.equal(replay.data.idempotentReplay, true);
  assert.equal(f.state.updates, 1);
});

test('a different command cannot replay a prior decline', async () => {
  const f = fixture();
  await f.service.decline(identity, quoteId, commandId);
  await assert.rejects(f.service.decline(identity, quoteId, '50000000-0000-4000-8000-000000000005'), /ya fue resuelta/);
  assert.equal(f.state.updates, 1);
});
