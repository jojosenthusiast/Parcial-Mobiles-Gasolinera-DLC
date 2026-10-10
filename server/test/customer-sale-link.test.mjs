import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { CustomerService } from '../dist/customers/customer.service.js';

const principal = { userId: '10000000-0000-4000-8000-000000000001', organizationId: '20000000-0000-4000-8000-000000000002', sessionId: '30000000-0000-4000-8000-000000000003', permissionVersion: 1 };
const input = { commandId: '40000000-0000-4000-8000-000000000004', customerCode: '50000000-0000-4000-8000-000000000005' };
const saleId = '60000000-0000-4000-8000-000000000006';
const branchId = '70000000-0000-4000-8000-000000000007';
const customerId = '80000000-0000-4000-8000-000000000008';
const correlationId = '90000000-0000-4000-8000-000000000009';
const requestHash = createHash('sha256').update(JSON.stringify({ branchId: branchId.toLowerCase(), saleId: saleId.toLowerCase(), customerCode: input.customerCode.toLowerCase() })).digest('hex');

function service({ alreadyLinked, saleStatus = 'pending_collection', oldCommand } = {}) {
  const seen = [];
  const client = {
    async query(sql, values = []) {
      const text = String(sql).replace(/\s+/g, ' ').trim(); seen.push({ text, values });
      if (text === 'BEGIN' || text === 'COMMIT' || text === 'ROLLBACK') return { rows: [] };
      if (text.includes('SELECT pg_advisory_xact_lock')) return { rows: [] };
      if (text.startsWith('SELECT id,request_hash,linked_by FROM customer_sale_links')) return { rows: oldCommand ? [{ id: 'link-old', request_hash: requestHash, linked_by: principal.userId }] : [] };
      if (text.includes('FROM sales s JOIN sale_collection_balances')) return { rows: [{ id: saleId, status: saleStatus }] };
      if (text.includes('FROM customer_accounts WHERE organization_id=$1 AND public_code=$2')) return { rows: [{ id: customerId }] };
      if (text.startsWith('SELECT id,customer_id FROM customer_sale_links')) return { rows: alreadyLinked ? [{ id: 'link-existing', customer_id: alreadyLinked }] : [] };
      if (text.startsWith('INSERT INTO customer_sale_links')) return { rows: [{ id: 'link-new' }] };
      throw new Error(`Unexpected SQL: ${text}`);
    },
    release() {},
  };
  const auditCalls = [];
  const pool = { connect: async () => client };
  const audit = { appendTransaction: async (...args) => { auditCalls.push(args); } };
  return { instance: new CustomerService(pool, { get: () => 'qa' }, audit), seen, auditCalls };
}

test('customer sale link writes once and audits using the authenticated employee actor', async () => {
  const state = service();
  const result = await state.instance.linkSale(branchId, saleId, principal, input, correlationId);
  assert.deepEqual(result, { id: 'link-new', idempotentReplay: false });
  assert.equal(state.seen.filter(({ text }) => text.startsWith('INSERT INTO customer_sale_links')).length, 1);
  assert.equal(state.auditCalls.length, 1);
  const locks = state.seen.filter(({ text }) => text.includes('pg_advisory_xact_lock'));
  assert.deepEqual(locks.map(item => item.values[0]), [
    `customer-sale-command:${principal.organizationId}:${input.commandId}`,
    `customer-sale:${principal.organizationId}:${saleId}`,
    `sale-collection:${saleId}`,
  ]);
});

test('customer sale link rejects a paid sale before linking', async () => {
  const state = service({ saleStatus: 'paid' });
  await assert.rejects(state.instance.linkSale(branchId, saleId, principal, input, correlationId), /before linking|cobrar/);
  assert.equal(state.seen.some(({ text }) => text.startsWith('INSERT INTO customer_sale_links')), false);
  assert.ok(state.seen.some(({ text }) => text === 'ROLLBACK'));
});

test('same customer already linked is safe to retry; another customer is rejected', async () => {
  const same = service({ alreadyLinked: customerId });
  assert.deepEqual(await same.instance.linkSale(branchId, saleId, principal, input, correlationId), { id: 'link-existing', idempotentReplay: true });
  assert.equal(same.seen.some(({ text }) => text.startsWith('INSERT INTO customer_sale_links')), false);
  const other = service({ alreadyLinked: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' });
  await assert.rejects(other.instance.linkSale(branchId, saleId, principal, input, correlationId), /otra cuenta/);
});

test('command replay returns the original link without repeating side effects', async () => {
  const state = service({ oldCommand: true });
  assert.deepEqual(await state.instance.linkSale(branchId, saleId, principal, input, correlationId), { id: 'link-old', idempotentReplay: true });
  assert.equal(state.seen.some(({ text }) => text.startsWith('INSERT INTO customer_sale_links')), false);
  assert.equal(state.auditCalls.length, 0);
});
