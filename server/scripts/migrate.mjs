import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import { databaseConnectionOptions } from './database-connection.mjs';

const { Pool } = pg;
const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, '..', 'migrations');
const pool = new Pool({ ...databaseConnectionOptions(process.env), max: 1, application_name: 'dlc-migrations', connectionTimeoutMillis: 5_000 });
const client = await pool.connect();
try {
  await client.query('SELECT pg_advisory_lock(hashtext($1))', ['dlc-schema-migrations']);
  // Supabase provides these client roles. The local PostgreSQL Compose image does not;
  // create only missing, non-login, least-privilege placeholders before migrations
  // that revoke grants from the Supabase role names. Existing Supabase roles are untouched.
  await client.query(`DO $bootstrap$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
      END IF;
    END;
  $bootstrap$`);
  await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    version text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now()
  )`);
  const names = (await readdir(migrationsDir)).filter(name => /^\d{4}_[a-z0-9_]+\.sql$/.test(name)).sort();
  for (const name of names) {
    const sql = await readFile(join(migrationsDir, name), 'utf8');
    const checksum = createHash('sha256').update(sql).digest('hex');
    const existing = await client.query('SELECT checksum FROM schema_migrations WHERE version = $1', [name]);
    if (existing.rowCount) {
      if (existing.rows[0].checksum !== checksum) throw new Error(`Migración aplicada modificada: ${name}`);
      continue;
    }
    await client.query('BEGIN');
    try {
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations(version, checksum) VALUES ($1, $2)', [name, checksum]);
      await client.query('COMMIT');
      process.stdout.write(`aplicada ${name}\n`);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  }
} finally {
  await client.query('SELECT pg_advisory_unlock(hashtext($1))', ['dlc-schema-migrations']).catch(() => undefined);
  client.release();
  await pool.end();
}
