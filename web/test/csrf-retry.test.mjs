import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const app = await readFile(new URL('../public/app.js', import.meta.url), 'utf8');
const CSRF_MESSAGE = 'Token CSRF inválido.';

// Extrae las declaraciones de una sola línea del cliente para ejecutarlas aisladas.
function line(pattern) {
  const match = app.match(pattern);
  assert.ok(match, `falta declaración en app.js: ${pattern}`);
  return match[0];
}
const source = [
  line(/^class DlcApiError .*$/m),
  line(/^const CSRF_FAILURE_MESSAGE=.*$/m),
  line(/^function refreshCsrf\(\).*$/m),
  line(/^async function request\(.*$/m),
].join('\n');

function response(status, body) {
  return {
    status,
    ok: status >= 200 && status < 300,
    headers: { get: name => (name.toLowerCase() === 'content-type' ? 'application/json' : null) },
    json: async () => body,
    text: async () => JSON.stringify(body),
  };
}

function harness({ csrfIssuedAt = Date.now(), postResponses }) {
  const calls = [];
  let csrfCount = 0;
  const queue = [...postResponses];
  const sandbox = {
    state: { csrf: 'old-token', csrfIssuedAt },
    crypto: { randomUUID: () => 'req-id' },
    notifyMutation() {},
    showLogin() { throw new Error('no debe cerrar sesión'); },
    fetch: async (url, init = {}) => {
      calls.push({ url, init });
      if (url === '/csrf') {
        csrfCount += 1;
        return response(200, { csrfToken: `token-${csrfCount}` });
      }
      const next = queue.shift();
      assert.ok(next, 'fetch inesperado');
      return next;
    },
  };
  vm.createContext(sandbox);
  vm.runInContext(`${source}\nthis.api = { request, refreshCsrf };`, sandbox);
  return { api: sandbox.api, sandbox, calls, csrfCalls: () => calls.filter(c => c.url === '/csrf').length };
}

test('ante 403 CSRF renueva el token y reintenta la misma mutación exactamente una vez', async () => {
  const h = harness({
    postResponses: [
      response(403, { message: CSRF_MESSAGE }),
      response(200, { data: { id: 'b1' } }),
    ],
  });
  const result = await h.api.request('/branches', { method: 'POST', data: { code: 'A1' } });
  assert.deepEqual(result, { data: { id: 'b1' } });
  const posts = h.calls.filter(c => c.url === '/api/v1/branches');
  assert.equal(posts.length, 2, 'debe reintentar una sola vez');
  assert.equal(posts[0].init.headers['X-CSRF-Token'], 'old-token');
  assert.equal(posts[1].init.headers['X-CSRF-Token'], 'token-1', 'el reintento usa el token renovado');
  assert.equal(posts[1].init.body, posts[0].init.body, 'el reintento envía el mismo cuerpo');
  assert.equal(h.sandbox.state.csrf, 'token-1');
  assert.equal(h.csrfCalls(), 1);
});

test('un 403 de permisos no renueva el token ni reintenta y se propaga', async () => {
  const h = harness({
    postResponses: [response(403, { message: 'No tienes permiso para esta acción.', code: 'FORBIDDEN' })],
  });
  await assert.rejects(
    h.api.request('/branches', { method: 'POST', data: { code: 'A1' } }),
    { name: 'DlcApiError', status: 403, code: 'FORBIDDEN', message: 'No tienes permiso para esta acción.' },
  );
  assert.equal(h.calls.filter(c => c.url === '/api/v1/branches').length, 1);
  assert.equal(h.csrfCalls(), 0);
  assert.equal(h.sandbox.state.csrf, 'old-token');
});

test('si el reintento también falla por CSRF se detiene sin bucle', async () => {
  const h = harness({
    postResponses: [
      response(403, { message: CSRF_MESSAGE }),
      response(403, { message: CSRF_MESSAGE }),
    ],
  });
  await assert.rejects(
    h.api.request('/branches', { method: 'PUT', data: { code: 'A1' } }),
    { status: 403, message: CSRF_MESSAGE },
  );
  assert.equal(h.calls.filter(c => c.url === '/api/v1/branches').length, 2, 'exactamente un reintento');
  assert.equal(h.csrfCalls(), 1, 'un solo refresco de token');
});

test('GET nunca renueva token ni reintenta ante 403 CSRF', async () => {
  const h = harness({
    csrfIssuedAt: Date.now() - 60 * 60 * 1000,
    postResponses: [response(403, { message: CSRF_MESSAGE })],
  });
  await assert.rejects(h.api.request('/branches'), { status: 403 });
  assert.equal(h.calls.filter(c => c.url === '/api/v1/branches').length, 1);
  assert.equal(h.csrfCalls(), 0);
});

test('renueva proactivamente el token de más de 50 minutos antes de mutar', async () => {
  const h = harness({
    csrfIssuedAt: Date.now() - 51 * 60 * 1000,
    postResponses: [response(200, { data: { ok: true } })],
  });
  await h.api.request('/branches/b1', { method: 'PATCH', data: { name: 'Centro' } });
  assert.equal(h.csrfCalls(), 1);
  const patch = h.calls.find(c => c.url === '/api/v1/branches/b1');
  assert.equal(patch.init.headers['X-CSRF-Token'], 'token-1');
});

test('un token reciente no se renueva antes de mutar', async () => {
  const h = harness({
    csrfIssuedAt: Date.now() - 10 * 60 * 1000,
    postResponses: [response(200, { data: { ok: true } })],
  });
  await h.api.request('/branches/b1', { method: 'DELETE' });
  assert.equal(h.csrfCalls(), 0);
  const del = h.calls.find(c => c.url === '/api/v1/branches/b1');
  assert.equal(del.init.headers['X-CSRF-Token'], 'old-token', 'DELETE sin cuerpo también envía el token');
});
