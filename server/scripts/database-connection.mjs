import { readFileSync } from 'node:fs';
import { X509Certificate } from 'node:crypto';

export function validateDatabaseEnvironment(values) {
  const databaseUrl = String(values.DATABASE_URL ?? '');
  let parsed;
  try { parsed = new URL(databaseUrl); } catch { throw new Error('DATABASE_URL debe ser una URL PostgreSQL válida.'); }
  if (!['postgres:', 'postgresql:'].includes(parsed.protocol) || !parsed.hostname || !parsed.pathname || parsed.pathname === '/') {
    throw new Error('DATABASE_URL debe apuntar a una base PostgreSQL con nombre.');
  }
  if (['ssl', 'sslmode', 'sslrootcert', 'sslcert', 'sslkey', 'sslpassword'].some(key => parsed.searchParams.has(key))) {
    throw new Error('Configura TLS con DATABASE_SSL_MODE, no dentro de DATABASE_URL.');
  }
  const sslMode = String(values.DATABASE_SSL_MODE ?? 'disable');
  if (!['disable', 'verify-full'].includes(sslMode)) throw new Error('DATABASE_SSL_MODE debe ser disable o verify-full.');
  if (values.NODE_ENV === 'production' && sslMode !== 'verify-full') throw new Error('En producción, DATABASE_SSL_MODE debe ser verify-full.');
  const caFile = String(values.DATABASE_SSL_CA_FILE ?? '').trim();
  if (caFile && sslMode !== 'verify-full') throw new Error('DATABASE_SSL_CA_FILE requiere verify-full.');
  return { databaseUrl, sslMode, caFile };
}

export function databaseConnectionOptions(values) {
  const { databaseUrl, sslMode, caFile } = validateDatabaseEnvironment(values);
  if (sslMode === 'disable') return { connectionString: databaseUrl, ssl: false };
  const ssl = { rejectUnauthorized: true };
  if (caFile) {
    let certificate;
    try {
      certificate = readFileSync(caFile, 'utf8');
      new X509Certificate(certificate);
    } catch { throw new Error('DATABASE_SSL_CA_FILE debe ser un certificado PEM legible.'); }
    ssl.ca = certificate;
  }
  return { connectionString: databaseUrl, ssl };
}

export function assertRestrictedDatabaseRole(role) {
  if (!role || role.isSuperuser || role.bypassesRls || role.createsRoles || role.createsDatabases || role.createsSchemaObjects || role.canEditAudit || role.canEditMigrations) {
    throw new Error('La API de producción requiere una cuenta PostgreSQL limitada; usa un login miembro de dlc_api_runtime y una cuenta separada para migraciones.');
  }
}
