import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const spec = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
const migration = await readFile(new URL('../../migrations/0089_loyalty_program_approval.sql', import.meta.url), 'utf8');
const redemptionMigration = await readFile(new URL('../../migrations/0091_customer_points_redemption_rate.sql', import.meta.url), 'utf8');
const salesBackfill = await readFile(new URL('../../migrations/0090_backfill_completed_fuel_sales.sql', import.meta.url), 'utf8');
const service = await readFile(new URL('../../src/customers/loyalty-program.service.ts', import.meta.url), 'utf8');

test('la política central de puntos expone gestión, aprobación y retiro con permisos separados', () => {
  assert.ok(spec.paths['/loyalty/programs']);
  assert.ok(spec.paths['/loyalty/programs/{programId}/submit']);
  assert.ok(spec.paths['/loyalty/programs/{programId}/decision']);
  assert.ok(spec.paths['/loyalty/programs/{programId}/retire']);
  assert.equal(spec.paths['/loyalty/programs'].post['x-required-permission'], 'loyalty.program.manage');
  assert.equal(spec.paths['/loyalty/programs/{programId}/decision'].post['x-required-permission'], 'loyalty.program.approve');
  assert.match(service, /approved_by=\$2,approved_at=now\(\)/);
  assert.match(service, /created_by === principal\.userId \|\| row\.submitted_by === principal\.userId/);
});

test('la migración conserva datos históricos y fija el flujo de versión inmutable con doble control', () => {
  assert.match(migration, /legacy_approval boolean NOT NULL DEFAULT false/);
  assert.match(migration, /UPDATE customer_loyalty_programs[\s\S]*WHERE status IN \('active','retired'\)/);
  assert.match(migration, /Loyalty policy versions are immutable/);
  assert.match(migration, /OLD\.status='pending_approval' AND NEW\.status IN \('active','rejected'\)/);
  assert.match(migration, /customer_loyalty_program_events/);
  assert.match(migration, /FOR UPDATE TO dlc_api_runtime/);
});

test('la conversión de pago con puntos queda versionada, desactivada por defecto e inmutable', () => {
  const request = spec.components.schemas.CreateLoyaltyProgramRequest;
  assert.ok(request.required.includes('redemptionUsdPerPoint'));
  assert.equal(request.properties.redemptionUsdPerPoint.minimum, 0);
  assert.match(redemptionMigration, /redemption_usd_per_point numeric\(12,6\) NOT NULL DEFAULT 0/);
  assert.match(redemptionMigration, /OLD\.redemption_usd_per_point IS DISTINCT FROM NEW\.redemption_usd_per_point/);
  assert.match(service, /redemption_usd_per_point AS "redemptionUsdPerPoint"/);
  assert.match(service, /normalized\.redemptionUsdPerPoint/);
});

test('un cierre de despacho registra venta y línea junto con completar autorización', async () => {
  const source = await readFile(new URL('../../src/infrastructure/infrastructure.service.ts', import.meta.url), 'utf8');
  const close = source.slice(source.indexOf('async completeDispense('), source.indexOf('private async calculateSaleAmount('));
  assert.ok(close.indexOf("status='completed'") < close.indexOf('INSERT INTO sales'));
  assert.ok(close.indexOf('INSERT INTO sales') < close.indexOf('INSERT INTO sale_lines'));
  assert.match(close, /ON CONFLICT\(authorization_id\) DO NOTHING/);
  assert.match(salesBackfill, /sale\.backfilled_from_dispense/);
  assert.match(salesBackfill, /NOT EXISTS\(SELECT 1 FROM sales s WHERE s\.authorization_id=a\.id\)/);
});
