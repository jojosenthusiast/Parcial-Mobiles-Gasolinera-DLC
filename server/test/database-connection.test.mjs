import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { rootCertificates } from 'node:tls';
import { assertRestrictedDatabaseRole, databaseConnectionOptions } from '../scripts/database-connection.mjs';

const base = { DATABASE_URL: 'postgresql://dlc:test@localhost/dlc', NODE_ENV: 'production', DATABASE_SSL_MODE: 'verify-full' };
test('all database callers use verified TLS and reject URI overrides', () => {
  assert.deepEqual(databaseConnectionOptions(base).ssl, { rejectUnauthorized: true });
  assert.throws(() => databaseConnectionOptions({ ...base, DATABASE_SSL_MODE: 'disable' }), /En producción/);
  assert.throws(() => databaseConnectionOptions({ ...base, DATABASE_URL: base.DATABASE_URL + '?sslmode=require' }), /Configura TLS/);
  assert.throws(() => databaseConnectionOptions({ ...base, DATABASE_URL: base.DATABASE_URL + '?ssl=false' }), /Configura TLS/);
});
test('uses a valid CA without disabling certificate verification', () => {
  const directory = mkdtempSync(join(tmpdir(), 'dlc-tls-'));
  try {
    const path = join(directory, 'ca.pem');
    writeFileSync(path, rootCertificates[0]);
    const options = databaseConnectionOptions({ ...base, DATABASE_SSL_CA_FILE: path });
    assert.equal(options.ssl.rejectUnauthorized, true);
    assert.equal(options.ssl.ca, rootCertificates[0]);
    writeFileSync(path, 'invalid');
    assert.throws(() => databaseConnectionOptions({ ...base, DATABASE_SSL_CA_FILE: path }), /certificado PEM legible/);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
test('a CA file cannot be silently ignored in plaintext mode', () => {
  assert.throws(() => databaseConnectionOptions({ ...base, NODE_ENV: 'development', DATABASE_SSL_MODE: 'disable', DATABASE_SSL_CA_FILE: '/not-read' }), /requiere verify-full/);
});
test('production runtime rejects privileged database accounts', () => {
  const restricted = { isSuperuser: false, bypassesRls: false, createsRoles: false, createsDatabases: false, createsSchemaObjects: false, canEditAudit: false, canEditMigrations: false };
  assert.doesNotThrow(() => assertRestrictedDatabaseRole(restricted));
  assert.throws(() => assertRestrictedDatabaseRole(undefined), /cuenta PostgreSQL limitada/);
  for (const capability of Object.keys(restricted)) {
    assert.throws(() => assertRestrictedDatabaseRole({ ...restricted, [capability]: true }), /cuenta PostgreSQL limitada/);
  }
});
