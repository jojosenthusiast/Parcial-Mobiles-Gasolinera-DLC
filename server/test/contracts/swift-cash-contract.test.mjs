import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../../', import.meta.url);
const read = (path) => readFile(new URL(path, root), 'utf8');
const spec = JSON.parse(await read('contracts/openapi.json'));
const client = await read('DLCGasolineras/Services/RemoteAPIClient.swift');
const viewModel = await read('DLCGasolineras/ViewModels/RemotePOSViewModel.swift');
const views = await read('DLCGasolineras/Views/BranchManager/RemotePOSViews.swift');
const app = await read('DLCGasolineras/App/DLCGasolinerasApp.swift');
const operationsCash = await read('flutter/apps/dlc_operations/lib/cash_screen.dart');
const controller = await read('server/src/sales/payments.controller.ts');
const approvalController = await read('server/src/authorization/approval.controller.ts');
const approvalService = await read('server/src/authorization/approval.service.ts');

test('mobile cash screens use the authenticated cash API and its permission boundaries', () => {
  const routes = [
    ['/branches/{branchId}/cash/registers', 'get', 'cash.read'],
    ['/branches/{branchId}/cash/registers', 'post', 'cash.register.manage'],
    ['/branches/{branchId}/cash/sessions', 'post', 'cash.open'],
    ['/branches/{branchId}/cash/sessions/{sessionId}', 'get', 'cash.read'],
    ['/branches/{branchId}/cash/sessions/{sessionId}/movements', 'get', 'cash.read'],
    ['/branches/{branchId}/cash/sessions/{sessionId}/movements', 'post', 'cash.move'],
    ['/branches/{branchId}/cash/sessions/{sessionId}/close', 'post', 'cash.close'],
    ['/branches/{branchId}/cash/sessions/{sessionId}/review', 'get', 'cash.read'],
    ['/branches/{branchId}/cash/reviews', 'get', 'cash.read'],
  ];
  for (const [path, method, permission] of routes) {
    const operation = spec.paths[path]?.[method];
    assert.ok(operation, `falta ${method.toUpperCase()} ${path}`);
    assert.match(operation.responses['403'].description, new RegExp(permission));
    assert.ok(controller.includes(`@RequirePermission('${permission}')`));
  }
  for (const method of ['cashRegisters', 'createCashRegister', 'openCashSession', 'cashSession', 'cashMovements', 'createCashMovement', 'closeCashSession', 'cashReview', 'cashReviews']) {
    assert.match(client, new RegExp(`func ${method}\\([^\\n]*\\) async throws`), `falta el método remoto ${method}`);
  }
  assert.match(app, /contains\("cash\.read"\)[\s\S]*?RemoteCashCenterView\(/);
  assert.match(app, /canManageRegisters: appState\.remoteCapabilities\?\.permissions\.contains\("cash\.register\.manage"\)/);
  assert.match(app, /canOpen: appState\.remoteCapabilities\?\.permissions\.contains\("cash\.open"\)/);
  assert.match(app, /canMove: appState\.remoteCapabilities\?\.permissions\.contains\("cash\.move"\)/);
  assert.match(app, /canClose: appState\.remoteCapabilities\?\.permissions\.contains\("cash\.close"\)/);
});

test('mobile cash operations are persisted and retried with the original idempotency command', () => {
  assert.match(viewModel, /resource: "cash-command"/);
  assert.match(viewModel, /store\.saveDraft\(draft\)/);
  assert.match(viewModel, /command\.id == draft\.id/);
  assert.match(viewModel, /store\.removeDraft\(id: command\.id, scope: scope\)/);
  assert.match(viewModel, /client\.cashSession\(branchId: branchID, sessionID: sessionID\)/);
  assert.match(viewModel, /countedCashUsd: cash, settledCardUsd: card/);
  assert.match(viewModel, /\[400, 403, 404, 409, 422\]/);
  assert.match(viewModel, /movementGeneration/);
  assert.match(viewModel, /guard requestGeneration == movementGeneration else \{ return \}/);
});

test('cash UI supports register lifecycle, movement history, server-computed closure review, and reduced motion', () => {
  for (const text of [
    'RemoteCashCenterView', 'RemoteCashSessionView', 'RemoteCashRegisterSheet', 'RemoteCashOpenSheet',
    'RemoteCashMovementSheet', 'RemoteCashCloseSheet', 'cash_in', 'withdrawal', 'deposit',
    'expectedCashUsd', 'varianceCardUsd', 'loadMovements(more: true)', 'Arqueos recientes',
    'Pendientes', 'Las diferencias requieren resolución', 'accessibilityReduceMotion',
  ]) assert.ok(views.includes(text), `falta UI de caja: ${text}`);
  assert.match(views, /Solo un usuario con permisos de aprobación, distinto de quien cerró/);
  assert.match(views, /reduceMotion \? nil :/);
  assert.match(views, /.animation\(reduceMotion \? nil :/);
});

test('cash variance approval is permission-gated, independent, audited, and safely recoverable', () => {
  const operation = spec.paths['/approvals/{approvalId}/decision']?.post;
  assert.ok(operation, 'falta la ruta de decisión de aprobación');
  assert.match(operation.responses['403'].description, /Permiso/);
  assert.match(operation.responses['409'].description, /Aprobación propia o solicitud resuelta/);
  assert.match(approvalController, /@RequirePermission\('approval\.decide'\)/);
  assert.match(approvalService, /capabilities\.includes\(request\.action\)/);
  assert.match(approvalService, /request\.requested_by === approver\.userId/);
  assert.match(approvalService, /approval\.\$\{decision\}/);
  assert.match(app, /canDecideVariance: appState\.remoteCapabilities\?\.permissions\.contains\("approval\.decide"\) == true[\s\S]*?contains\("cash\.variance\.approve"\)/);
  assert.match(client, /func decideApproval\(approvalID: UUID, body: RemoteApprovalDecisionBody\) async throws/);
  assert.match(viewModel, /resource: "cash-review-command"/);
  assert.match(viewModel, /command\.id == draft\.id/);
  assert.match(viewModel, /review\.cashierId != scope\.userId/);
  assert.match(viewModel, /client\.cashReview\(branchId: branchID, sessionID: command\.sessionId\)/);
  assert.match(viewModel, /client\.decideApproval\([\s\S]*?command\.approvalId/);
  assert.match(viewModel, /La solicitud sigue pendiente; puedes consultar y reintentar con el mismo borrador/);
  assert.match(views, /Revisión independiente/);
  assert.match(views, /Aprobar diferencia/);
  assert.match(views, /Rechazar diferencia/);
  assert.match(views, /TextEditor\(text: \$reason\)/);
  assert.match(views, /retryVarianceDecision\(command\)/);
});



test('operations POS provides a category filter for quick retail merchandise', () => {
  assert.match(operationsCash, /Filtrar por categoría/);
  assert.match(operationsCash, /_selectedStoreCategory/);
  assert.match(operationsCash, /p\['category'\]/);
});
