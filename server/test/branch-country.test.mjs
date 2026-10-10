import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { MetricsService } from '../dist/metrics/metrics.service.js';

let source = await readFile(new URL('../src/branches/branches.service.ts', import.meta.url), 'utf8');
source = source.replace(/^import .+?;\r?\n/gm, '').replace(/@Injectable\(\)\s*/g, '').replace(/@Inject\([^)]+\)\s*/g, '');
source = ['BadRequestException', 'ConflictException', 'NotFoundException']
  .map(name => `class ${name} extends Error { constructor(message){ super(typeof message==='string'?message:JSON.stringify(message)); this.details=message; } }`).join('\n') + '\n' + source;
const { BranchesService } = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source, { mode: 'transform' })).toString('base64')}`);

const branchId = '11111111-1111-4111-8111-111111111111';
const organizationId = '22222222-2222-4222-8222-222222222222';
const principal = { userId: '33333333-3333-4333-8333-333333333333', organizationId };

function createClient(row = {}) {
  const calls = [];
  const client = {
    calls,
    release() {},
    async query(sql, values = []) {
      calls.push({ sql, values });
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql)) return { rows: [] };
      if (sql.startsWith('INSERT INTO branches')) return { rows: [{ id: branchId, code: values[1], countryCode: values[7] }], rowCount: 1 };
      if (sql.startsWith('INSERT INTO branch_operating_profiles')) return { rows: [], rowCount: 1 };
      if (sql.startsWith('SELECT onboarding_version,status,onboarding_data')) {
        return { rows: [{ onboarding_version: 2, status: 'draft', onboarding_data: {}, code: 'DLC-1', name: 'DLC Uno', zone: 'central', timezone: 'America/El_Salvador', country_code: 'SV', ...row }] };
      }
      if (sql.startsWith('UPDATE branches SET code=')) return { rows: [{ id: branchId, status: 'draft', onboardingData: {}, onboardingVersion: 3 }], rowCount: 1 };
      throw new Error(`Unexpected SQL: ${sql}`);
    },
  };
  return client;
}
const audit = { appendTransaction: async () => {} };
const draft = { code: 'gt-1', name: 'Guatemala 1', zone: 'other', timezone: 'America/Guatemala', expectedDispenserCount: 4 };

test('createDraft defaults countryCode to SV and snapshots it in onboarding_data', async () => {
  const client = createClient();
  await new BranchesService({ connect: async () => client }, audit).createDraft(principal, draft, 'req-1');
  const insert = client.calls.find(call => call.sql.startsWith('INSERT INTO branches'));
  assert.match(insert.sql, /country_code/);
  assert.match(insert.sql, /'countryCode',\$8::text/);
  assert.match(insert.sql, /country_code AS "countryCode"/);
  assert.equal(insert.values[7], 'SV');
});

test('createDraft uppercases and validates countryCode', async () => {
  const client = createClient();
  await new BranchesService({ connect: async () => client }, audit).createDraft(principal, { ...draft, countryCode: ' gt ' }, 'req-2');
  assert.equal(client.calls.find(call => call.sql.startsWith('INSERT INTO branches')).values[7], 'GT');
  for (const countryCode of ['G', 'GTM', 'G1', '']) {
    let connected = false;
    const service = new BranchesService({ connect: async () => { connected = true; return createClient(); } }, audit);
    await assert.rejects(service.createDraft(principal, { ...draft, countryCode }, 'req-3'), /countryCode/);
    assert.equal(connected, false);
  }
});

test('identity step persists countryCode in the column and the jsonb snapshot', async () => {
  const client = createClient();
  const service = new BranchesService({ connect: async () => client }, audit);
  await service.saveStep(branchId, principal, { expectedVersion: 2, step: 'identity', data: { name: 'DLC Guate', countryCode: 'gt' } }, 'req-4');
  const update = client.calls.find(call => call.sql.startsWith('UPDATE branches SET code='));
  assert.match(update.sql, /country_code=\$10/);
  assert.equal(update.values[9], 'GT');
  const snapshot = JSON.parse(update.values[3]);
  assert.equal(snapshot.countryCode, 'GT');
  assert.equal(snapshot.name, 'DLC Guate');
});

test('identity step keeps the stored country when countryCode is omitted and rejects invalid values', async () => {
  const client = createClient({ country_code: 'GT' });
  const service = new BranchesService({ connect: async () => client }, audit);
  await service.saveStep(branchId, principal, { expectedVersion: 2, step: 'identity', data: { name: 'DLC Guate' } }, 'req-5');
  assert.equal(client.calls.find(call => call.sql.startsWith('UPDATE branches SET code=')).values[9], 'GT');
  for (const countryCode of ['guatemala', 12, null, 'G1']) {
    await assert.rejects(
      new BranchesService({ connect: async () => createClient() }, audit)
        .saveStep(branchId, principal, { expectedVersion: 2, step: 'identity', data: { countryCode } }, 'req-6'),
      /countryCode/,
    );
  }
});

test('branch list filters by country and exposes countryCode', async () => {
  const calls = [];
  const pool = { query: async (sql, values) => { calls.push({ sql, values }); return { rows: [] }; } };
  await new BranchesService(pool, audit).list(principal, { limit: 10, countryCode: 'gt' });
  assert.match(calls[0].sql, /country_code AS "countryCode"/);
  assert.match(calls[0].sql, /country_code=\$2/);
  assert.equal(calls[0].values[1], 'GT');
  await new BranchesService(pool, audit).list(principal, { limit: 10 });
  assert.doesNotMatch(calls[1].sql, /country_code=\$/);
});

function networkPool(branches) {
  const calls = [];
  return {
    calls,
    pool: {
      query: async (sql, values) => {
        calls.push({ sql, values });
        if (sql.includes('FROM branches WHERE organization_id=$1 AND status=\'active\' GROUP BY country_code')) {
          return { rows: [{ countryCode: 'GT', branchCount: 1 }, { countryCode: 'SV', branchCount: 2 }] };
        }
        if (sql.includes('FROM branches WHERE')) {
          const [, selected, country] = values;
          return { rows: branches.filter(b => (!selected || b.id === selected) && (!country || b.country_code === country)) };
        }
        return { rows: [] };
      },
    },
  };
}
const networkBranches = [
  { id: branchId, name: 'A', code: 'A', timezone: 'America/El_Salvador', country_code: 'SV', effective_date: '2026-10-01', today: '2026-10-08' },
  { id: '44444444-4444-4444-8444-444444444444', name: 'B', code: 'B', timezone: 'America/Guatemala', country_code: 'GT', effective_date: '2026-10-01', today: '2026-10-08' },
];
const auth = { capabilities: async () => ['branch.read'] };

test('network dashboard filters by countryCode, lists visible countries and tags branches', async () => {
  const db = networkPool(networkBranches);
  const service = new MetricsService(db.pool, auth, {});
  const filtered = (await service.network(principal, '7', undefined, 'gt')).data;
  assert.deepEqual(filtered.branches.map(b => [b.code, b.countryCode]), [['B', 'GT']]);
  assert.equal(filtered.scopeCountryCode, 'GT');
  assert.equal(filtered.activeBranchCount, 1);
  assert.deepEqual(filtered.countries, [{ countryCode: 'GT', branchCount: 1 }, { countryCode: 'SV', branchCount: 2 }]);
  assert.equal(db.calls[0].values[2], 'GT');
  const all = (await service.network(principal, '7')).data;
  assert.equal(all.scopeCountryCode, null);
  assert.deepEqual(all.branches.map(b => b.countryCode), ['SV', 'GT']);
});

test('network dashboard combines branchId and countryCode and validates the filter', async () => {
  const service = new MetricsService(networkPool(networkBranches).pool, auth, {});
  await assert.rejects(service.network(principal, '7', branchId, 'GT'), /fuera de la red/);
  assert.equal((await service.network(principal, '7', branchId, 'SV')).data.branches.length, 1);
  assert.equal((await service.network(principal, '7', undefined, '')).data.scopeCountryCode, null);
  for (const bad of ['G', 'GTM', 'G1']) await assert.rejects(service.network(principal, '7', undefined, bad), /Filtro de red/);
});
