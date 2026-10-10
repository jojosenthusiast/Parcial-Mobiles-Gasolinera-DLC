import test from 'node:test';
import assert from 'node:assert/strict';
import * as argon2 from 'argon2';
import { AuthService } from '../dist/auth/auth.service.js';

const id = '5a2d2931-78aa-45c1-9655-f5f67f840a2d';

function poolForLogin(activeShift) {
  const statements = [];
  const pool = {
    query: async sql => { statements.push(String(sql)); return { rows: [{ attempt_count: 1 }] }; },
    connect: async () => ({
      query: async (sql) => {
        statements.push(String(sql));
        if (String(sql).includes('FROM users WHERE email_normalized')) return { rows: [{
          id, organization_id: id, employee_id: id, display_name: 'Test worker',
          password_hash: pool.passwordHash, status: 'active', permission_version: 1,
          failed_login_count: 0, locked_until: null,
        }] };
        if (String(sql).includes('SELECT EXISTS')) return { rows: [{ active: activeShift }] };
        return { rows: [] };
      },
      release() {},
    }),
  };
  return { pool, statements };
}

test('employee login is denied outside scheduled work shift before session creation', async () => {
  const state = poolForLogin(false);
  state.pool.passwordHash = await argon2.hash('correct horse battery staple');
  const service = new AuthService(state.pool, { getOrThrow: () => 'test-rate-key' }, { appendTransaction: async () => {} });
  await assert.rejects(service.login('worker@example.test', 'correct horse battery staple', undefined, '127.0.0.1', id), { status: 403 });
  assert.ok(state.statements.some(sql => sql.includes('employee_work_shifts')));
  assert.equal(state.statements.some(sql => sql.includes('INSERT INTO auth_sessions')), false);
});

test('existing employee access token is rejected outside the scheduled shift', async () => {
  let sql = '';
  const service = new AuthService({ query: async value => { sql = String(value); return { rows: [] }; } }, { getOrThrow: () => 'key' }, {});
  assert.equal(await service.authenticate('a'.repeat(60)), null);
  assert.match(sql, /employee_work_shifts/);
  assert.match(sql, /starts_at<=clock_timestamp()/);
  assert.match(sql, /ends_at>clock_timestamp()/);
});
