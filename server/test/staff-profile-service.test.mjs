import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

let source = await readFile(new URL('../src/staff/staff.service.ts', import.meta.url), 'utf8');
source = source.replace(/^import .+?;\r?\n/gm, '').replace(/@Injectable\(\)\s*/g, '').replace(/@Inject\([^)]+\)\s*/g, '');
source = `import { createHash } from 'node:crypto';\n` +
  ['BadRequestException','ConflictException','ForbiddenException','NotFoundException'].map(name => `class ${name} extends Error {}`).join('\n') +
  '\n' + source;
const { StaffService } = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source, { mode: 'transform' })).toString('base64')}`);

const branchId = '11111111-1111-4111-8111-111111111111';
const employeeId = '22222222-2222-4222-8222-222222222222';
const principal = { organizationId: '33333333-3333-4333-8333-333333333333', userId: '44444444-4444-4444-8444-444444444444' };

function fixture({ permissions = ['staff.manage','staff.private.read','staff.read','staff.shifts.plan'], status = 'active', branchStatus = 'active', version = 2 } = {}) {
  const calls = [], audits = [];let connectionCount = 0;
  const client = { query: async (sql, values = []) => {
    calls.push({ sql, values });
    if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') return { rows: [] };
    if (sql.startsWith('SELECT legal_name AS')) return { rows: [{ legalName: 'Ana López', positionTitle: 'Cajera', status, version }] };
    if (sql.startsWith('INSERT INTO employees')) return { rows: [{ id: employeeId }] };
    if (sql.startsWith('UPDATE employees SET legal_name=')) return { rows: [{ version: version + 1 }], rowCount: 1 };
    throw new Error(`Unexpected SQL: ${sql}`);
  }, release() {} };
  const pool = { query: async (sql, values = []) => {
    calls.push({ sql, values });
    if (sql.startsWith('SELECT id FROM branches')) return { rows: branchStatus === 'active' || (values[2] && ['draft','configured'].includes(branchStatus)) ? [{ id: branchId }] : [] };
    if (sql.startsWith('SELECT e.id')) return { rows: [] };
    throw new Error(`Unexpected pool SQL: ${sql}`);
  }, connect: async () => { connectionCount++; return client; } };
  const service = new StaffService(pool, { capabilities: async () => permissions }, { appendTransaction: async (_client, event) => audits.push(event) });
  return { service, calls, audits, wasConnected: () => connectionCount > 0, connectionCount: () => connectionCount };
}

test('actualiza ficha con versión optimista, normaliza contacto y audita solo campos', async () => {
  const f = fixture();
  const result = await f.service.updateProfile(branchId, employeeId, principal, {
    legalName: '  Ana López  ', positionTitle: 'Supervisora', contactEmail: ' ANA@EXAMPLE.COM ',
    contactPhone: null, hiredOn: null, expectedVersion: 2,
  }, 'request-1');
  assert.equal(result.data.version, 3);
  const update = f.calls.find(call => call.sql.startsWith('UPDATE employees SET legal_name='));
  assert.deepEqual(update.values.slice(3), ['Ana López','Supervisora',true,'ana@example.com',true,null,true,null,2]);
  assert.deepEqual(f.audits[0].before, { version: 2, fields: ['legalName','positionTitle','contactEmail','contactPhone','hiredOn'] });
  assert.deepEqual(f.audits[0].after.updatedFields, ['legalName','positionTitle','contactEmail','contactPhone','hiredOn']);
  assert.doesNotMatch(JSON.stringify(f.audits), /ana@example\.com/);
});

test('no permite modificar contacto sin permiso privado ni escribir con versión obsoleta', async () => {
  const noPrivate = fixture({ permissions: ['staff.manage'] });
  await assert.rejects(noPrivate.service.updateProfile(branchId, employeeId, principal, {
    legalName: 'Ana López', positionTitle: 'Cajera', contactEmail: null, expectedVersion: 2,
  }, 'request-2'), /staff\.private\.read/);
  assert.equal(noPrivate.wasConnected(), false);

  const stale = fixture();
  await assert.rejects(stale.service.updateProfile(branchId, employeeId, principal, {
    legalName: 'Ana López', positionTitle: 'Cajera', expectedVersion: 1,
  }, 'request-3'), /ficha cambió/);
  assert.equal(stale.calls.some(call => call.sql.startsWith('UPDATE employees SET legal_name=')), false);
  assert.ok(stale.calls.some(call => call.sql === 'ROLLBACK'));
});

test('rechaza fichas terminadas y payloads inválidos', async () => {
  const terminated = fixture({ status: 'terminated' });
  await assert.rejects(terminated.service.updateProfile(branchId, employeeId, principal, {
    legalName: 'Ana López', positionTitle: 'Cajera', expectedVersion: 2,
  }, 'request-4'), /colaborador terminado/);
  const invalid = fixture();
  await assert.rejects(invalid.service.updateProfile(branchId, employeeId, principal, {
    legalName: 'Ana', positionTitle: 'Cajera', contactEmail: 'no-es-correo', expectedVersion: 2,
  }, 'request-5'), /no son válidos/);
  assert.equal(invalid.wasConnected(), false);
});

test('permite preparar y consultar empleados en sucursal borrador, pero no planificar turnos', async () => {
  const draft = fixture({ branchStatus: 'draft' });
  const created = await draft.service.create(branchId, principal, {
    employeeCode: 'EMP-01', legalName: 'Ana López', positionTitle: 'Gerente',
  }, 'request-draft-create');
  assert.equal(created.data.employeeCode, 'EMP-01');
  assert.ok(draft.audits.some(event => event.action === 'staff.employee.created'));
  const rows = await draft.service.employees(branchId, principal, {});
  assert.deepEqual(rows.data, []);
  assert.ok(draft.calls.some(call => call.sql.startsWith('SELECT id FROM branches') && call.values[2] === true));

  const connectedBeforeBlockedOperation = draft.connectionCount();
  await assert.rejects(draft.service.schedule(branchId, principal, {
    commandId: '55555555-5555-4555-8555-555555555555',
    employeeId,
    position: 'manager',
    startsAt: '2026-10-10T08:00:00Z',
    endsAt: '2026-10-10T16:00:00Z',
  }, 'request-draft'), /fuera de tu ámbito/);
  assert.equal(draft.connectionCount(), connectedBeforeBlockedOperation);
});
