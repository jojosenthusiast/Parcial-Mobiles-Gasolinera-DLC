import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../../', import.meta.url);
const read = (path) => readFile(new URL(path, root), 'utf8');
const spec = JSON.parse(await read('contracts/openapi.json'));
const client = await read('DLCGasolineras/Services/RemoteAPIClient.swift');
const viewModel = await read('DLCGasolineras/ViewModels/RemotePOSViewModel.swift');
const saleViews = await read('DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift');
const refundPanel = saleViews.slice(saleViews.indexOf('private struct RemoteSaleRefundPanel'), saleViews.indexOf('private struct RemoteRefundRequestSheet'));
const app = await read('DLCGasolineras/App/DLCGasolinerasApp.swift');
const controller = await read('server/src/sales/payments.controller.ts');

test('sale payment screens match collection, resolution, and read API permissions', () => {
  const routes = [
    ['/branches/{branchId}/payments', 'post', 'payment.collect'],
    ['/branches/{branchId}/payments/{attemptId}/resolve', 'post', 'payment.resolve'],
    ['/branches/{branchId}/sales/{saleId}/payments', 'get', 'payment.read'],
  ];
  for (const [path, method, permission] of routes) {
    const operation = spec.paths[path]?.[method];
    assert.ok(operation, `falta ${method.toUpperCase()} ${path}`);
    assert.match(operation.responses['403'].description, new RegExp(permission));
    assert.ok(controller.includes(`@RequirePermission('${permission}')`));
  }
  for (const method of ['paymentsForSale', 'collectPayment', 'resolvePayment']) {
    assert.match(client, new RegExp(`func ${method}\\([^\\n]*\\) async throws`));
  }
  assert.match(app, /canReadPayments: appState\.remoteCapabilities\?\.permissions\.contains\("payment\.read"\)/);
  assert.match(app, /canCollectPayments: appState\.remoteCapabilities\?\.permissions\.contains\("payment\.collect"\)/);
  assert.match(app, /canResolvePayments: appState\.remoteCapabilities\?\.permissions\.contains\("payment\.resolve"\)/);
  assert.match(app, /canReadCash: appState\.remoteCapabilities\?\.permissions\.contains\("cash\.read"\)/);
});

test('payments are sale-scoped, durable, capped to outstanding balance, and never persist card secrets', () => {
  assert.match(viewModel, /resource: "payment-command"/);
  assert.match(viewModel, /command\.saleID == saleID/);
  assert.match(viewModel, /requested <= due/);
  assert.match(viewModel, /saleStatus != "on_credit"/);
  assert.match(viewModel, /method: method, mode: "manual"/);
  assert.match(viewModel, /outcome == "unknown"/);
  assert.match(viewModel, /store\.saveDraft\(draft\)/);
  assert.match(viewModel, /command\.id == draft\.id/);
  assert.match(saleViews, /sin número de tarjeta/);
  assert.match(saleViews, /No guardes PAN, CVV ni credenciales del terminal/);
});

test('the sale master-detail presents attempts, resolves unknown outcomes, and reloads server balances', () => {
  for (const text of [
    'RemoteSalePaymentsPanel', 'RemotePaymentCollectionSheet', 'RemotePaymentResolutionSheet',
    'Registrar pago parcial o total', 'Resultado del terminal', 'Conciliar resultado del terminal',
    'Saldo por cobrar', 'paymentStatusTitle', 'reduceMotion ? nil :',
  ]) assert.ok(saleViews.includes(text), `falta flujo de pago: ${text}`);
  assert.match(saleViews, /await reloadSale\(\)/);
  assert.match(saleViews, /selectedCashSessionID/);
});

test('refund workflow is permissioned, independently approved, sale-scoped, and exposed through one sheet route', () => {
  const path = '/branches/{branchId}/sales/{saleId}/refund-requests';
  const operation = spec.paths[path]?.get;
  assert.ok(operation, `falta GET ${path}`);
  assert.match(operation.responses['403'].description, /payment\.read/);
  assert.equal(operation.responses['200'].content['application/json'].schema.properties.data.items.$ref, '#/components/schemas/RefundRequestDetail');
  for (const [route, permission] of [
    ['/branches/{branchId}/payment-events/{paymentEventId}/refund-requests', 'sale.refund.request'],
    ['/branches/{branchId}/payment-events/{paymentEventId}/refunds', 'payment.refund'],
  ]) {
    const write = spec.paths[route]?.post;
    assert.ok(write, `falta POST ${route}`);
    assert.match(write.responses['403'].description, new RegExp(permission));
    assert.ok(controller.includes(`@RequirePermission('${permission}')`));
  }
  for (const method of ['refundRequestsForSale', 'requestRefund', 'executeRefund']) {
    assert.match(client, new RegExp(`func ${method}\\([^\\n]*\\) async throws`), `falta ${method}`);
  }
  assert.match(app, /canRequestRefund: appState\.remoteCapabilities\?\.permissions\.contains\("sale\.refund\.request"\)/);
  assert.match(app, /canDecideRefund: appState\.remoteCapabilities\?\.permissions\.contains\("approval\.decide"\)/);
  assert.match(app, /canDecideRefund:[\s\S]*?contains\("sale\.refund\.approve"\)/);
  assert.match(app, /canExecuteRefund: appState\.remoteCapabilities\?\.permissions\.contains\("payment\.refund"\)/);
  assert.match(viewModel, /request\.requestedBy != scope\.userId/);
  assert.match(viewModel, /request\.requestedBy == scope\.userId/);
  assert.match(viewModel, /resource: "refund-command"/);
  assert.match(viewModel, /command\.id == draft\.id/);
  assert.match(viewModel, /client\.refundRequestsForSale\(branchId: branchID, saleID: saleID\)/);
  assert.match(saleViews, /case \.request\(let attempt\):[\s\S]*case \.decide\(let request\):[\s\S]*case \.execute\(let request\):/);
  assert.equal((refundPanel.match(/\.sheet\(item: \$activeSheet\)/g) ?? []).length, 1, 'refund actions must share one sheet presenter');
  assert.match(viewModel, /devolución de tarjeta requiere una referencia/);
});

test('prepayment refunds are listed by branch and retain durable, separated request, decision, and execution actions', () => {
  const path = '/branches/{branchId}/prepayments';
  const operation = spec.paths[path]?.get;
  assert.ok(operation, `falta GET ${path}`);
  assert.match(operation.responses['403'].description, /payment\.read/);
  assert.equal(operation.responses['200'].content['application/json'].schema.properties.data.items.$ref, '#/components/schemas/PrepaymentRecord');
  for (const route of [
    ['/branches/{branchId}/dispense-authorizations/{authorizationId}/prepayments', 'payment.collect'],
    ['/branches/{branchId}/prepayments/{advanceId}/allocate', 'payment.collect'],
    ['/branches/{branchId}/prepayments/{advanceId}/refund-requests', 'sale.refund.request'],
    ['/branches/{branchId}/prepayments/{advanceId}/refunds', 'payment.refund'],
    ['/branches/{branchId}/prepayments/{advanceId}/release-requests', 'payment.resolve'],
    ['/branches/{branchId}/prepayments/{advanceId}/release-confirmations', 'payment.resolve'],
    ['/branches/{branchId}/prepayments/{advanceId}/resolve', 'payment.resolve'],
  ]) {
    const write = spec.paths[route[0]]?.post;
    assert.ok(write, `falta POST ${route[0]}`);
    assert.match(write.responses['403'].description, new RegExp(route[1]));
  }
  for (const method of ['prepayments', 'collectPrepayment', 'allocatePrepayment', 'requestPrepaymentRefund', 'executePrepaymentRefund', 'requestPrepaymentRelease', 'confirmPrepaymentRelease', 'resolvePrepayment']) {
    assert.match(client, new RegExp(`func ${method}\\([^\\n]*\\) async throws`), `falta ${method}`);
  }
  assert.match(viewModel, /resource: "prepayment-refund-command"/);
  assert.match(viewModel, /case collect\(authorizationID:/);
  assert.match(viewModel, /cashSessionId: cashSessionID/);
  assert.match(viewModel, /func allocatePrepayment\(/);
  assert.match(viewModel, /func requestRelease\(/);
  assert.match(viewModel, /func confirmRelease\(/);
  assert.match(viewModel, /func resolvePrepayment\(/);
  assert.match(viewModel, /tenderKind == "authorization_hold" && outcome == "declined"/);
  assert.match(viewModel, /advance\.requestStatus == "approved"[\s\S]*advance\.requestedBy == scope\.userId/);
  assert.match(viewModel, /advance\.requestedBy != scope\.userId/);
  assert.match(viewModel, /client\.prepayments\(branchId: branchID\)/);
  assert.match(saleViews, /struct RemotePrepaymentsView/);
  assert.match(saleViews, /RemotePrepaymentCollectionPanel/);
  assert.match(saleViews, /RemotePrepaymentCollectSheet/);
  assert.match(saleViews, /RemotePrepaymentAllocationSheet/);
  assert.match(saleViews, /Confirmar liberación de tarjeta/);
  assert.match(saleViews, /releaseStatus == "pending"/);
  assert.match(app, /Anticipos y devoluciones/);
  assert.match(app, /canExecute: appState\.remoteCapabilities\?\.permissions\.contains\("payment\.refund"\)/);
});

