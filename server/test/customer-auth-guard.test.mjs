import test from 'node:test';
import assert from 'node:assert/strict';
import { CustomerAuthGuard } from '../dist/customers/customer-auth.guard.js';

const verifiedUser = { id: '4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e', email: 'Client@example.com', email_confirmed_at: '2026-10-01T00:00:00Z', user_metadata: { role: 'admin' } };
function setup({ authorization, response = { status: 200, ok: true, json: async () => verifiedUser }, fetchImpl } = {}) {
  const request = { header: name => name.toLowerCase() === 'authorization' ? authorization : undefined };
  const context = { switchToHttp: () => ({ getRequest: () => request }) };
  const config = { get: key => ({ SUPABASE_URL: 'https://project.example', SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test' })[key] };
  const original = globalThis.fetch;
  globalThis.fetch = fetchImpl ?? (async (url, options) => {
    assert.equal(String(url), 'https://project.example/auth/v1/user');
    assert.equal(options.headers.apikey, 'sb_publishable_test');
    return response;
  });
  return { guard: new CustomerAuthGuard(config), context, request, restore: () => { globalThis.fetch = original; } };
}

test('Customer guard rejects missing bearer and never contacts auth', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => { throw new Error('should not call auth'); };
  try {
    const guard = new CustomerAuthGuard({ get: () => 'https://project.example' });
    await assert.rejects(guard.canActivate({ switchToHttp: () => ({ getRequest: () => ({ header: () => undefined }) }) }), { status: 401 });
  } finally { globalThis.fetch = original; }
});

test('Customer guard accepts only verified Supabase identity and ignores user metadata roles', async () => {
  const state = setup({ authorization: `Bearer ${'a'.repeat(50)}` });
  try {
    assert.equal(await state.guard.canActivate(state.context), true);
    assert.deepEqual(state.request.customer, { authUserId: verifiedUser.id, email: 'client@example.com' });
    assert.equal(state.request.customer.role, undefined);
  } finally { state.restore(); }
});

test('Customer guard rejects unconfirmed email', async () => {
  const state = setup({ authorization: `Bearer ${'b'.repeat(50)}`, response: { status: 200, ok: true, json: async () => ({ ...verifiedUser, email_confirmed_at: null }) } });
  try { await assert.rejects(state.guard.canActivate(state.context), { status: 401 }); }
  finally { state.restore(); }
});

test('Customer guard fails closed when Supabase is unavailable', async () => {
  const state = setup({ authorization: `Bearer ${'c'.repeat(50)}`, fetchImpl: async () => { throw new Error('network'); } });
  try { await assert.rejects(state.guard.canActivate(state.context), { status: 503 }); }
  finally { state.restore(); }
});
