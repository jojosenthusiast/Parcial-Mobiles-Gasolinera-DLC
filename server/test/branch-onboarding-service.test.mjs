import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

let source = await readFile(new URL('../src/branches/branches.service.ts', import.meta.url), 'utf8');
source = source.replace(/^import .+?;\n/gm, '').replace(/@Injectable\(\)\s*/g, '').replace(/@Inject\([^)]+\)\s*/g, '');
source = [
  'BadRequestException','ConflictException','NotFoundException',
].map(name => `class ${name} extends Error { constructor(message){ super(typeof message==='string'?message:JSON.stringify(message)); this.details=message; } }`).join('\n') + '\n' + source;
const transformed = stripTypeScriptTypes(source, { mode: 'transform' });
const { BranchesService } = await import(`data:text/javascript;base64,${Buffer.from(transformed).toString('base64')}`);

const branchId = '11111111-1111-4111-8111-111111111111';
const organizationId = '22222222-2222-4222-8222-222222222222';
const principal = { userId: '33333333-3333-4333-8333-333333333333', organizationId };

function readinessDb({ activeEmployees = 0, staffReview = undefined } = {}) {
  const calls = [];
  const query = async (sql, values = []) => {
    calls.push({ sql, values });
    if (sql.includes('SELECT id,status,onboarding_data')) return { rows: [{ id: branchId, status: 'draft', onboardingData: staffReview ? { staff: staffReview } : {}, onboardingVersion: 4 }] };
    if (sql.includes('SELECT profile,expected_dispenser_count')) return { rows: [{ profile: 'operational', expected_dispenser_count: 1 }] };
    if (sql.includes('FROM branch_fuel_offers')) return { rows: [{ count: 1 }] };
    if (sql.includes('FROM tanks WHERE') && sql.includes("status='active'")) return { rows: [{ count: 1 }] };
    if (sql.includes('FROM tanks t') && sql.includes('inventory_movements')) return { rows: [{ count: 0 }] };
    if (sql.includes('FROM dispensers d') && sql.includes("physical_status='active'")) return { rows: [{ count: 1 }] };
    if (sql.includes('FROM dispensers WHERE') && sql.includes("physical_status='active'")) return { rows: [{ count: 1 }] };
    if (sql.includes('FROM nozzles n LEFT JOIN nozzle_tank_connections')) return { rows: [{ count: 0 }] };
    if (sql.includes('NOT EXISTS (SELECT 1 FROM nozzles n')) return { rows: [{ count: 0 }] };
    if (sql.includes('FROM employees WHERE')) return { rows: [{ count: activeEmployees }] };
    if (sql.includes('FROM inventory_movements')) return { rows: [{ count: 0 }] };
    if (sql.includes('FILTER (WHERE price.id IS NULL)')) return { rows: [{ missing_price: 0, other_unavailable: 0 }] };
    throw new Error(`Unexpected SQL: ${sql}`);
  };
  return { calls, pool: { query, connect: async () => ({ query, release() {} }) } };
}

test('la revisión de personal no se puede confirmar con una cantidad activa vacía', async () => {
  let connected = false;
  const service = new BranchesService({ connect: async () => { connected = true; throw Error('No debe abrir transacción'); } }, {});
  await assert.rejects(service.saveStep(branchId, principal, {
    expectedVersion: 4, step: 'staff', data: { status: 'confirmed', employeeCount: 0 },
  }, 'request-1'), /número de colaboradores activos revisados/);
  assert.equal(connected, false);
});

test('la revisión puede guardarse como pendiente y conserva versión optimista y auditoría', async () => {
  const calls = [], audits = [];
  const client = { query: async (sql, values = []) => {
    calls.push({ sql, values });
    if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') return { rows: [] };
    if (sql.startsWith('SELECT onboarding_version,status,onboarding_data')) return { rows: [{ onboarding_version: 4, status: 'draft', onboarding_data: {}, code: 'DLC-1', name: 'DLC Uno', zone: 'central', timezone: 'America/El_Salvador' }] };
    if (sql.startsWith('UPDATE branches SET code=')) return { rows: [{ id: branchId, status: 'draft', onboardingData: { staff: { status: 'deferred', employeeCount: 0 } }, onboardingVersion: 5, updatedAt: '2026-10-08T12:00:00Z' }], rowCount: 1 };
    throw new Error(`Unexpected SQL: ${sql}`);
  }, release() {} };
  const service = new BranchesService({ connect: async () => client }, { appendTransaction: async (_client, event) => audits.push(event) });
  const result = await service.saveStep(branchId, principal, { expectedVersion: 4, step: 'staff', data: { status: 'deferred', employeeCount: 0 } }, 'request-2');
  assert.equal(result.onboardingVersion, 5);
  assert.deepEqual(JSON.parse(calls.find(x => x.sql.startsWith('UPDATE branches SET code=')).values[3]), { status: 'deferred', employeeCount: 0 });
  assert.equal(audits.length, 1);
});

test('readiness bloquea el alta cuando no hay personal activo', async () => {
  const db = readinessDb({ staffReview: { status: 'confirmed', employeeCount: 1 } });
  const service = new BranchesService(db.pool, {});
  const result = await service.readiness(branchId, principal);
  assert.equal(result.activeEmployeeCount, 0);
  assert.equal(result.canActivate, false);
  assert.ok(result.blockers.some(x => x.code === 'ACTIVE_EMPLOYEE_MISSING'));
  assert.ok(result.blockers.some(x => x.code === 'STAFF_REVIEW_PENDING'));
});

test('readiness invalida la confirmación si cambia el número de empleados activos', async () => {
  const db = readinessDb({ activeEmployees: 2, staffReview: { status: 'confirmed', employeeCount: 1 } });
  const service = new BranchesService(db.pool, {});
  const result = await service.readiness(branchId, principal);
  assert.equal(result.activeEmployeeCount, 2);
  assert.ok(result.blockers.some(x => x.code === 'STAFF_REVIEW_PENDING'));
});

test('la activación vuelve a validar personal activo dentro de su transacción', async () => {
  const db = readinessDb({ staffReview: { status: 'confirmed', employeeCount: 1 } });
  let activationWritten = false, rolledBack = false;
  const client = { query: async (sql, values = []) => {
    if (sql === 'BEGIN') return { rows: [] };
    if (sql === 'ROLLBACK') { rolledBack = true; return { rows: [] }; }
    if (sql === 'COMMIT') return { rows: [] };
    if (sql.startsWith('SELECT onboarding_version,status,onboarding_data')) return { rows: [{ onboarding_version: 4, status: 'draft', onboarding_data: { staff: { status: 'confirmed', employeeCount: 1 } } }] };
    if (sql.startsWith('SELECT expected_dispenser_count')) return { rows: [{ expected_dispenser_count: 1 }] };
    if (sql.startsWith('UPDATE branches SET status=\'active\'')) { activationWritten = true; return { rows: [{ id: branchId }] }; }
    return db.pool.query(sql, values);
  }, release() {} };
  const service = new BranchesService({ connect: async () => client }, { appendTransaction: async () => {} });
  await assert.rejects(service.activate(branchId, principal, { expectedVersion: 4 }, 'request-3'), /requisitos pendientes/);
  assert.equal(activationWritten, false);
  assert.equal(rolledBack, true);
});
