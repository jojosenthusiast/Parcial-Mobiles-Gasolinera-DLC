import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { spawn } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

async function freePort() {
  const server = createServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const { port } = server.address();
  await new Promise((done, reject) => server.close(error => error ? reject(error) : done()));
  return port;
}

async function launch(script, env) {
  const port = await freePort();
  const child = spawn(process.execPath, [resolve(webRoot, script)], { env: { ...process.env, ...env, PORT: String(port), HOST: '127.0.0.1' }, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; });
  child.stderr.on('data', chunk => { output += chunk; });
  const base = `http://127.0.0.1:${port}`;
  try {
    for (let attempt = 0; attempt < 80; attempt++) {
      if (child.exitCode !== null) throw new Error(`Server exited early: ${output}`);
      try { if ((await fetch(`${base}/healthz`)).ok) return { child, base, output: () => output }; } catch { }
      await delay(50);
    }
    throw new Error(`Server did not become ready: ${output}`);
  } catch (error) {
    child.kill('SIGTERM');
    throw error;
  }
}

test('web runtime enforces CSRF, HttpOnly sessions and authenticated API proxying', { timeout: 15000 }, async t => {
  const upstreamCalls = [];
  let refreshCalls = 0;
  const api = createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    upstreamCalls.push({ method: req.method, url: req.url, authorization: req.headers.authorization, body: Buffer.concat(chunks).toString() });
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/api/v1/auth/login' && req.method === 'POST') {
      res.end(JSON.stringify({ data: { accessToken: 'qa-access-token', refreshToken: 'qa-refresh-token', accessExpiresAt: new Date(Date.now() + 10000).toISOString() } }));
      return;
    }
    if (req.url === '/api/v1/auth/refresh' && req.method === 'POST') {
      refreshCalls++;
      await delay(50);
      res.end(JSON.stringify({ data: { accessToken: 'qa-refreshed-token', refreshToken: 'qa-refreshed-refresh-token', accessExpiresAt: new Date(Date.now() + 3600000).toISOString() } }));
      return;
    }
    if (req.url === '/api/v1/auth/logout') { res.end(JSON.stringify({ data: { revoked: true } })); return; }
    res.end(JSON.stringify({ data: { ok: true } }));
  });
  api.listen(0, '127.0.0.1');
  try { await once(api, 'listening'); }
  catch (error) {
    if (error.code === 'EPERM' || error.code === 'EACCES') { t.skip('Este runtime no permite abrir puertos localhost; ejecutar en QA o en la máquina de desarrollo.'); return; }
    throw error;
  }
  const apiPort = api.address().port;
  const web = await launch('server.mjs', {
    WEB_SESSION_KEY: 'qa-only-secret-key-with-at-least-32-bytes',
    WEB_API_BASE_URL: `http://127.0.0.1:${apiPort}/api/v1`,
  });
  t.after(async () => {
    web.child.kill('SIGTERM');
    api.close();
    await Promise.allSettled([once(web.child, 'exit'), once(api, 'close')]);
  });

  const health = await fetch(`${web.base}/healthz`);
  assert.deepEqual(await health.json(), { ok: true });
  const home = await fetch(`${web.base}/`);
  assert.equal(home.status, 200);
  assert.match(home.headers.get('content-security-policy'), /default-src 'self'/);
  assert.match(home.headers.get('content-security-policy'), /frame-ancestors 'none'/);
  assert.match(await home.text(), /DLC/);

  const csrfResponse = await fetch(`${web.base}/csrf`);
  const csrf = (csrfResponse.headers.get('set-cookie') ?? '').split(';')[0];
  const csrfToken = (await csrfResponse.json()).csrfToken;
  assert.ok(csrf.startsWith('dlc_csrf='));
  assert.ok(csrfResponse.headers.get('set-cookie').includes('SameSite=Strict'));

  const noCsrf = await fetch(`${web.base}/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'qa@example.test', password: 'not-used' }) });
  assert.equal(noCsrf.status, 403);
  assert.equal(upstreamCalls.length, 0, 'invalid CSRF must not reach the identity API');

  const login = await fetch(`${web.base}/login`, { method: 'POST', headers: { 'Content-Type': 'application/json', Cookie: csrf, 'X-CSRF-Token': csrfToken }, body: JSON.stringify({ email: 'qa@example.test', password: 'qa-only' }) });
  assert.equal(login.status, 200);
  assert.deepEqual(await login.json(), { authenticated: true }, 'tokens are not returned to browser JavaScript');
  const sessionCookie = (login.headers.get('set-cookie') ?? '').split(';')[0];
  assert.ok(sessionCookie.startsWith('dlc_session='));
  assert.match(login.headers.get('set-cookie'), /HttpOnly/);
  assert.match(login.headers.get('set-cookie'), /SameSite=Lax/);

  const unauthorized = await fetch(`${web.base}/api/v1/private`);
  assert.equal(unauthorized.status, 401);
  const proxiedResponses = await Promise.all([1, 2].map(() => fetch(`${web.base}/api/v1/private`, { headers: { Cookie: sessionCookie } })));
  for (const proxied of proxiedResponses) {
    assert.equal(proxied.status, 200);
    assert.deepEqual(await proxied.json(), { data: { ok: true } });
  }
  assert.equal(refreshCalls, 1, 'concurrent requests share a single refresh operation');
  assert.ok(upstreamCalls.filter(call => call.url === '/api/v1/private').every(call => call.authorization === 'Bearer qa-refreshed-token'));

  const blockedWrite = await fetch(`${web.base}/api/v1/private`, { method: 'POST', headers: { Cookie: sessionCookie, 'Content-Type': 'application/json' }, body: '{}' });
  assert.equal(blockedWrite.status, 403);
  const allowedWrite = await fetch(`${web.base}/api/v1/private`, { method: 'POST', headers: { Cookie: `${sessionCookie}; ${csrf}`, 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'qa' }) });
  assert.equal(allowedWrite.status, 200);

  const logout = await fetch(`${web.base}/logout`, { method: 'POST', headers: { Cookie: `${sessionCookie}; ${csrf}`, 'X-CSRF-Token': csrfToken } });
  assert.equal(logout.status, 200);
  assert.match(logout.headers.get('set-cookie'), /Max-Age=0/);
  assert.ok(upstreamCalls.some(call => call.url === '/api/v1/auth/logout'));
});
