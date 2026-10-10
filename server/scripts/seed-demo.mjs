import pg from 'pg';
import { databaseConnectionOptions } from './database-connection.mjs';
const { Pool } = pg;
const pool = new Pool({ ...databaseConnectionOptions(process.env), application_name: 'dlc-demo-seed', max: 1, connectionTimeoutMillis: 5_000 });
const fixtureOrganizationID = '00000000-0000-4000-8000-000000000001';
try {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO organizations(id, name) VALUES ($1, 'DLC Demo')
       ON CONFLICT (id) DO NOTHING`, [fixtureOrganizationID]
    );
    await client.query(
      `INSERT INTO branches(organization_id, code, name, zone, status)
       VALUES ($1,'DEMO-SA','DLC Santa Ana','occidental','draft')
       ON CONFLICT (organization_id, code) DO NOTHING`, [fixtureOrganizationID]
    );
    await client.query('COMMIT');
    process.stdout.write('Organización y sucursal sintéticas listas en estado draft.\n');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
} finally {
  await pool.end();
}
