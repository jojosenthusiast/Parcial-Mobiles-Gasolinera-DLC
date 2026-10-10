import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../scripts/export-legacy.mjs', import.meta.url));
const sourceInstallationId = '11111111-1111-4111-8111-111111111111';
function minimal() {
  const arrays = ['users','cuts','products','suppliers','lots','stockMovements','storeSales','staff','shiftAssignments','equipment','maintenanceOrders'];
  return { schemaVersion: 1, branches: [], ...Object.fromEntries(arrays.map(name => [name, []])) };
}

test('exportador conserva el origen byte por byte y no sobrescribe el paquete', async () => {
  const root = await mkdtemp(join(tmpdir(), 'dlc-legacy-export-'));
  try {
    const input = join(root, 'local.json');
    const output = join(root, 'bundle');
    const bytes = Buffer.from(JSON.stringify(minimal(), null, 2));
    await writeFile(input, bytes);
    const result = spawnSync(process.execPath, [script, input, output, sourceInstallationId], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(await readFile(input), bytes);
    assert.deepEqual(await readFile(join(output, 'source.json')), bytes);
    const manifest = JSON.parse(await readFile(join(output, 'manifest.json'), 'utf8'));
    assert.equal(manifest.sourceSha256.length, 64);
    assert.equal(manifest.credentials, 'not-exported');
    const second = spawnSync(process.execPath, [script, input, output, sourceInstallationId], { encoding: 'utf8' });
    assert.notEqual(second.status, 0);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('exportador no escribe si el snapshot incluye un secreto', async () => {
  const root = await mkdtemp(join(tmpdir(), 'dlc-legacy-secrets-'));
  try {
    const input = join(root, 'local.json');
    await writeFile(input, JSON.stringify({ ...minimal(), users: [{ id: sourceInstallationId, password: 'must-not-leave' }] }));
    const output = join(root, 'bundle');
    const result = spawnSync(process.execPath, [script, input, output, sourceInstallationId], { encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /campo sensible/);
  } finally { await rm(root, { recursive: true, force: true }); }
});
