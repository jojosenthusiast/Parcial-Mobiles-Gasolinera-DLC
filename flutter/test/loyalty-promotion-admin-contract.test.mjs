import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = async path => readFile(new URL(path, import.meta.url), 'utf8');

test('Operations exposes global points policy setup and review through the shared API client', async () => {
  const main = await read('../apps/dlc_operations/lib/main.dart');
  const screen = await read('../apps/dlc_operations/lib/loyalty_programs_screen.dart');
  const api = await read('../packages/dlc_api/lib/src/employee_session.dart');
  assert.match(main, /LoyaltyProgramsScreen\(\s*api:\s*controller\.api,\s*permissions:\s*controller\.globalPermissions,?\s*\)/);
  assert.match(screen, /loyalty\.program\.approve/);
  assert.match(screen, /Crear borrador/);
  assert.match(screen, /redemptionUsdPerPoint/);
  assert.match(screen, /La conversión aprobada habilita cotizaciones con confirmación del Cliente/);
  assert.match(screen, /Mantén la tasa en 0 en producción hasta implementar y probar los reversos/);
  assert.doesNotMatch(screen, /Permitir pagar parte de la venta con puntos/);
  for (const endpoint of ['/loyalty/programs', 'submitLoyaltyProgram', 'decideLoyaltyProgram', 'retireLoyaltyProgram']) assert.ok(api.includes(endpoint));
  assert.match(api, /requestPointPaymentQuote/);
  assert.match(api, /customer\/points\/quotes/);
});

test('General campaigns preview and freeze audiences; customer feed can filter by branch', async () => {
  const operations = await read('../apps/dlc_operations/lib/promotions_screen.dart');
  const customer = await read('../apps/dlc_customers/lib/main.dart');
  assert.match(operations, /targetBranchIds/);
  assert.match(operations, /targetZones/);
  assert.match(operations, /sales_usd_30d/);
  assert.match(operations, /Audiencia congelada/);
  assert.match(customer, /customer\/promotions\?branchId=/);
});
