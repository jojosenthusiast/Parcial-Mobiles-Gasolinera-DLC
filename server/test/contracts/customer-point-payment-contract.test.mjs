import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const spec = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
const migration = await readFile(new URL('../../migrations/0092_customer_points_sale_tender.sql', import.meta.url), 'utf8');
const reversalMigration = await readFile(new URL('../../migrations/0093_customer_points_refund_reversals.sql', import.meta.url), 'utf8');
const sqlSmoke = await readFile(new URL('../sql/customer-points-payment-smoke.sql', import.meta.url), 'utf8');
const paymentService = await readFile(new URL('../../src/customers/customer-points-payment.service.ts', import.meta.url), 'utf8');
const controller = await readFile(new URL('../../src/customers/customers.controller.ts', import.meta.url), 'utf8');
const customerApp = await readFile(new URL('../../../flutter/apps/dlc_customers/lib/main.dart', import.meta.url), 'utf8');
const operationsApp = await readFile(new URL('../../../flutter/apps/dlc_operations/lib/cash_screen.dart', import.meta.url), 'utf8');

test('puntos en ventas exige aprobación autenticada del cliente y publica rutas explícitas', () => {
  assert.ok(spec.paths['/branches/{branchId}/sales/{saleId}/customer/points/quotes'].post);
  assert.ok(spec.paths['/customer/me/points-payment-quotes'].get);
  assert.ok(spec.paths['/customer/me/points-payment-quotes/{quoteId}/confirm'].post);
  assert.ok(spec.paths['/customer/me/points-payment-quotes/{quoteId}/decline'].post);
  assert.equal(spec.components.schemas.CreateCustomerPointQuoteRequest.properties.points.maximum, 2000000000);
  assert.match(controller, /@UseGuards\(CustomerAuthGuard\)[\s\S]*confirmPointPayment/);
  assert.match(controller, /@RequirePermission\('payment\.collect'\)[\s\S]*Solicita aprobación del Cliente/);
});

test('la autorización de puntos es breve, un uso, idempotente y limitada por saldo de venta y cuenta', () => {
  assert.match(migration, /customer_point_quote_one_pending_sale_idx/);
  assert.match(migration, /interval '120 seconds'/);
  assert.match(migration, /An active linked customer is required/);
  assert.match(migration, /Insufficient available points/);
  assert.match(migration, /Point quote exceeds the available sale balance/);
  assert.match(migration, /Points cannot be applied to a commercial credit sale/);
  assert.match(migration, /Payment exceeds unreserved sale balance including points/);
  assert.match(migration, /Customer point payment facts are immutable/);
  assert.match(paymentService, /'redeem'/);
});

test('el saldo del Cliente publica la tasa activa y su equivalente monetario calculado', () => {
  const response = spec.paths['/customer/me/loyalty'].get.responses['200'];
  assert.equal(response.content['application/json'].schema.$ref, '#/components/schemas/CustomerLoyaltyBalance');
  assert.deepEqual(spec.components.schemas.CustomerLoyaltyBalance.required, ['pointsBalance', 'earnedProgram', 'canRedeem', 'redemptionUsdPerPoint', 'availableValueUsd', 'message']);
  assert.match(customerApp, /Valor para canje/);
  assert.match(customerApp, /canRedeem/);
});

test('las apps tienen pasos de solicitud, confirmación explícita y actualización del saldo', () => {
  assert.match(customerApp, /Solicitudes de pago en caja/);
  assert.match(customerApp, /Confirmar pago/);
  assert.match(customerApp, /commandId.*quote\['id'\]/);
  assert.match(operationsApp, /Solicitar pago con puntos/);
  assert.match(operationsApp, /Actualizar saldo de venta/);
});

test('reembolsos monetarios revierten puntos ganados de forma acumulativa y proporcional', () => {
  assert.match(reversalMigration, /AFTER INSERT ON payment_refunds/);
  assert.match(reversalMigration, /floor\(earned::numeric\*least\(refunded,eligible\)\/eligible\)/);
  assert.match(reversalMigration, /source_type='sale_refund'/);
  assert.match(reversalMigration, /customer_points_ledger/);
  assert.match(sqlSmoke, /mixed_points_cash_posts_one_tender/);
  assert.match(sqlSmoke, /partial_money_refund_reverses_earned_points_proportionally/);
  assert.match(sqlSmoke, /ROLLBACK/);
});
