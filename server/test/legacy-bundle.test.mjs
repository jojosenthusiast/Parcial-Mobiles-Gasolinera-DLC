import test from 'node:test';
import assert from 'node:assert/strict';
import { makeManifest, makePreview, parseSnapshot, verifyBundle, deterministicId } from '../scripts/legacy-bundle.mjs';

const sourceInstallationId = '11111111-1111-4111-8111-111111111111';
const branchId = '22222222-2222-4222-8222-222222222222';
const tankId = '33333333-3333-4333-8333-333333333333';
function fixture() {
  return {
    schemaVersion: 1,
    branches: [{ id: branchId, code: 'SA-01', name: 'Demo', tanks: [{ id: tankId, type: 'Súper', currentLiters: 3000, capacityLiters: 5000 }] }],
    users: [{ id: '44444444-4444-4444-8444-444444444444', username: 'admin', name: 'Admin', role: 'generalManager', isActive: true }],
    cuts: [{ id: '55555555-5555-4555-8555-555555555555', branchID: branchId, date: '2025-01-01T00:00:00Z', type: 'Matutino', isClosed: true, inventoryApplied: true }],
    products: [{ id: '66666666-6666-4666-8666-666666666666' }], suppliers: [], lots: [], stockMovements: [], storeSales: [], staff: [], shiftAssignments: [], equipment: [], maintenanceOrders: [],
  };
}

test('verifica hash de origen y conserva una propuesta de apertura sin contabilizar', () => {
  const snapshot = fixture();
  const bytes = Buffer.from(JSON.stringify(snapshot));
  const manifest = makeManifest(snapshot, bytes, sourceInstallationId, '2026-10-04T00:00:00.000Z');
  assert.equal(verifyBundle(manifest, bytes).schemaVersion, 1);
  const preview = makePreview(snapshot, manifest, null, '2026-10-04T00:00:00.000Z');
  assert.equal(preview.status, 'review_required');
  assert.equal(preview.canPublish, false);
  assert.equal(preview.fuelOpeningCandidates[0].quantityLiters, '3000');
  assert.equal(preview.fuelOpeningCandidates[0].cost, null);
  assert.equal(preview.policy.noInventoryPosted, true);
  assert.equal(preview.historicalCuts[0].disposition, 'archive_only_never_post_ledger');
});

test('mapeos son deterministas y un hash incorrecto bloquea antes de staging', () => {
  assert.equal(deterministicId(sourceInstallationId, 'branches', branchId), deterministicId(sourceInstallationId, 'branches', branchId));
  const bytes = Buffer.from(JSON.stringify(fixture()));
  const manifest = makeManifest(fixture(), bytes, sourceInstallationId);
  assert.throws(() => verifyBundle(manifest, Buffer.from('{}')), /hash/);
});

test('respaldo corrupto, colección faltante y credenciales se rechazan', () => {
  assert.throws(() => parseSnapshot(Buffer.from('{')), SyntaxError);
  const missing = fixture(); delete missing.cuts;
  assert.throws(() => parseSnapshot(Buffer.from(JSON.stringify(missing))), /Falta la colección/);
  const unsafe = fixture(); unsafe.users[0].password = 'secret';
  assert.throws(() => parseSnapshot(Buffer.from(JSON.stringify(unsafe))), /campo sensible/);
});

test('las cantidades de apertura fuera de rango y referencias ausentes bloquean preview', () => {
  const snapshot = fixture();
  snapshot.branches[0].tanks[0].currentLiters = 9000;
  snapshot.cuts[0].branchID = '77777777-7777-4777-8777-777777777777';
  const bytes = Buffer.from(JSON.stringify(snapshot));
  const manifest = makeManifest(snapshot, bytes, sourceInstallationId);
  const preview = makePreview(snapshot, manifest);
  assert.equal(preview.status, 'blocked');
  assert.ok(preview.blockers.some(issue => issue.code === 'TANK_OPENING_OUT_OF_RANGE'));
  assert.ok(preview.blockers.some(issue => issue.code === 'CUT_BRANCH_MISSING'));
});
