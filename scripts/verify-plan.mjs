import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const contract = JSON.parse(await readFile(join(projectRoot, 'contracts/openapi.json'), 'utf8'));
assert.equal(contract.openapi, '3.1.0');
assert.ok(contract.servers.some(server => server.url === '/api/v1'));
const migrations = (await readdir(join(projectRoot, 'server/migrations'))).filter(name => /^\d{4}_[a-z0-9_]+\.sql$/.test(name)).sort();
assert.ok(migrations.length >= 2, 'faltan migraciones iniciales');
assert.equal(new Set(migrations).size, migrations.length, 'hay nombres de migración duplicados');
const serverPackage = JSON.parse(await readFile(join(projectRoot, 'server/package.json'), 'utf8'));
assert.equal(serverPackage.type, 'module');
assert.equal(serverPackage.engines.node, '>=24.15.0 <25');
process.stdout.write(`Integridad básica: OpenAPI válido; ${migrations.length} migraciones; servidor ESM configurado.\n`);
