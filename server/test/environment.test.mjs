import test from 'node:test';
import assert from 'node:assert/strict';
import { validateEnvironment } from '../src/core/environment.ts';

const base = {
  DATABASE_URL: 'postgresql://dlc:secret@db.example.test:5432/dlc',
  AUTH_RATE_LIMIT_KEY: 'a'.repeat(40),
  NODE_ENV: 'development',
};
const customerProduction = {
  SUPABASE_URL: 'https://project.example',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
  SUPABASE_SECRET_KEY: 'sb_secret_server_only_test',
  CUSTOMER_ORGANIZATION_ID: '4f22f2b4-2f9b-4f8d-9d77-cd11a0d1825e',
  CUSTOMER_TERMS_VERSION: 'terms-2026-01',
};

test('local validation defaults to unencrypted TLS mode only for development config', () => {
  const config = validateEnvironment(base);
  assert.equal(config.DATABASE_SSL_MODE, 'disable');
  assert.equal(config.DATABASE_POOL_MAX, 10);
});

test('production requires certificate-verified PostgreSQL TLS', () => {
  assert.throws(
    () => validateEnvironment({ ...base, NODE_ENV: 'production' }),
    /DATABASE_SSL_MODE debe ser verify-full/,
  );
  const config = validateEnvironment({ ...base, ...customerProduction, NODE_ENV: 'production', DATABASE_SSL_MODE: 'verify-full' });
  assert.equal(config.DATABASE_SSL_MODE, 'verify-full');
});

test('production requires verified Supabase Auth and a scoped customer organization', () => {
  assert.throws(
    () => validateEnvironment({ ...base, ...customerProduction, CUSTOMER_ORGANIZATION_ID: '', NODE_ENV: 'production', DATABASE_SSL_MODE: 'verify-full' }),
    /app de Clientes requiere Supabase Auth/,
  );
  assert.throws(
    () => validateEnvironment({ ...base, ...customerProduction, NODE_ENV: 'production', DATABASE_SSL_MODE: 'verify-full', SUPABASE_URL: 'http://project.example' }),
    /SUPABASE_URL debe usar HTTPS/,
  );
  assert.throws(
    () => validateEnvironment({ ...base, ...customerProduction, NODE_ENV: 'production', DATABASE_SSL_MODE: 'verify-full', CUSTOMER_ORGANIZATION_ID: 'bad' }),
    /CUSTOMER_ORGANIZATION_ID debe ser un UUID/,
  );
});

test('rejects unknown TLS modes and ssl options embedded in the connection URL', () => {
  assert.throws(
    () => validateEnvironment({ ...base, DATABASE_SSL_MODE: 'require' }),
    /DATABASE_SSL_MODE debe ser disable o verify-full/,
  );
  assert.throws(
    () => validateEnvironment({ ...base, DATABASE_URL: `${base.DATABASE_URL}?sslmode=disable` }),
    /Configura TLS con DATABASE_SSL_MODE/,
  );
});

test('promotion storage keys stay server-side and are required for production image uploads', () => {
  assert.throws(() => validateEnvironment({ ...base, ...customerProduction, SUPABASE_SECRET_KEY: '', NODE_ENV: 'production', DATABASE_SSL_MODE: 'verify-full' }), /SUPABASE_SECRET_KEY solo en el servidor/);
  assert.throws(() => validateEnvironment({ ...base, SUPABASE_SECRET_KEY: 'sb_secret_test' }), /requiere SUPABASE_URL/);
  assert.throws(() => validateEnvironment({ ...base, PROMOTION_IMAGE_BUCKET: 'not/valid' }), /PROMOTION_IMAGE_BUCKET no es válido/);
});
