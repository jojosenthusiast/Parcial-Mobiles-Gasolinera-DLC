import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../', import.meta.url);
const read = path => readFile(new URL(path, root), 'utf8');

test('customer app uses confirmed Supabase identity and read-only customer catalog contracts', async () => {
  const [app, guard, controller, service, migration, env, posScreen, api] = await Promise.all([
    read('flutter/apps/dlc_customers/lib/main.dart'), read('server/src/customers/customer-auth.guard.ts'),
    read('server/src/customers/customers.controller.ts'), read('server/src/customers/customer.service.ts'), read('server/migrations/0086_customer_loyalty_foundation.sql'),
    read('server/src/core/environment.ts'), read('flutter/apps/dlc_operations/lib/cash_screen.dart'), read('flutter/packages/dlc_api/lib/src/employee_session.dart'),
  ]);
  for (const route of ['/customer/me/profile', '/customer/me/loyalty', '/customer/me/points', '/customer/me/qr', '/customer/rewards', '/customer/campaigns', '/customer/branches']) {
    assert.ok(app.includes(route), `Customer app must call ${route}`);
    assert.ok(controller.includes(route.replace(/^\/customer\//, '')), `Customer API must register ${route}`);
  }
  assert.match(guard, /auth\/v1\/user/);
  assert.match(guard, /email_confirmed_at/);
  assert.doesNotMatch(guard, /user_metadata/);
  assert.match(migration, /customer_points_ledger_immutable/);
  assert.match(migration, /FOREIGN KEY \(reward_id, organization_id\)/);
  assert.match(migration, /GRANT SELECT, INSERT, UPDATE ON TABLE customer_accounts TO dlc_api_runtime/);
  assert.match(migration, /REVOKE ALL ON TABLE public\.%I FROM PUBLIC, anon, authenticated, service_role/);
  assert.match(env, /CUSTOMER_TERMS_VERSION/);
  assert.match(app, /emailRedirectTo: _authRedirect/);
  assert.match(app, /redirectTo: _authRedirect/);
  assert.match(app, /AuthChangeEvent.passwordRecovery/);
  assert.match(app, /QrImageView/);
  assert.match(service, /identity_only/);
  assert.match(service, /No autoriza pagos ni canjea recompensas/);
  assert.match(controller, /branches\/\:branchId\/sales\/\:saleId\/customer/);
  assert.match(service, /customer-sale-command:/);
  assert.match(service, /pending_collection/);
  const saleLinkMigration = await read('server/migrations/0087_customer_sale_link_points.sql');
  assert.match(saleLinkMigration, /customer_sale_links/);
  assert.match(saleLinkMigration, /award_points_for_paid_customer_sale/);
  assert.match(saleLinkMigration, /collection_status <> 'paid'/);
  assert.match(saleLinkMigration, /sale-collection:'\|\|NEW\.sale_id/);
  assert.match(posScreen, /Vincular Cliente antes del cobro/);
  const qrScanner = await read('flutter/apps/dlc_operations/lib/customer_qr_scanner_screen.dart');
  assert.match(posScreen, /CustomerQrScannerScreen/);
  assert.match(posScreen, /Escanear QR del Cliente/);
  assert.match(qrScanner, /formats: const \[BarcodeFormat\.qrCode\]/);
  assert.match(qrScanner, /QR solo identifica la cuenta/);
  assert.match(qrScanner, /autorizar cualquier pago con puntos/);
  assert.match(api, /Future<Map<String, dynamic>> linkCustomerToSale/);
  const bootstrap = await read('flutter/tool/bootstrap_flutter_windows.ps1');
  assert.match(bootstrap, /sv\.com\.dlc\.dlc_customers/);
});

test('cash checkout creates a recoverable POS sale and reconciles unknown card outcomes', async () => {
  const [client, screen, controller, payments] = await Promise.all([
    read('flutter/packages/dlc_api/lib/src/employee_session.dart'), read('flutter/apps/dlc_operations/lib/cash_screen.dart'),
    read('server/src/sales/pos.controller.ts'), read('server/src/sales/payments.controller.ts'),
  ]);
  assert.match(client, /Future<Map<String, dynamic>> createPosSale/);
  assert.match(client, /pendingPosSale\(String branchId\)/);
  assert.match(client, /Future<Map<String, dynamic>> retryPendingPayment/);
  assert.match(client, /Future<Map<String, dynamic>> resolvePayment/);
  assert.match(controller, /@Post\('sales\/pos'\)/);
  assert.match(payments, /@Post\('payments'\)/);
  assert.match(payments, /@Post\('payments\/:attemptId\/resolve'\)/);
  assert.match(screen, /Nueva venta POS/);
  assert.match(screen, /Resultado incierto/);
  assert.match(screen, /Conciliar cobro incierto/);
  assert.match(screen, /No procesa tarjetas ni se conecta al terminal/);
  assert.match(screen, /Solicitar pago con puntos/);
  assert.match(screen, /await _checkSaleStatus\(\)/);
  assert.match(client, /requestPointPaymentQuote/);
  assert.match(client, /customer\/points\/quotes/);
  assert.match(client, /saleDetail\(String branchId, String saleId\)/);
  assert.match(screen, /Verifica el saldo antes de otro cobro/);
});
