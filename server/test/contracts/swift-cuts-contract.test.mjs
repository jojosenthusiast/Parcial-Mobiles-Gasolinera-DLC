import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../../', import.meta.url);
const read = (path) => readFile(new URL(path, root), 'utf8');
const spec = JSON.parse(await read('contracts/openapi.json'));
const client = await read('DLCGasolineras/Services/RemoteAPIClient.swift');
const viewModel = await read('DLCGasolineras/ViewModels/BranchManagerViewModel.swift');
const cutsView = await read('DLCGasolineras/Views/BranchManager/CutsView.swift');
const app = await read('DLCGasolineras/App/DLCGasolinerasApp.swift');
const login = await read('DLCGasolineras/Views/Auth/LoginView.swift');
const branchDashboard = await read('DLCGasolineras/Views/BranchManager/BranchDashboardView.swift');
const inventory = await read('DLCGasolineras/Views/Shared/InventoryComponents.swift');
const service = await read('server/src/cuts/cuts.service.ts');

test('mobile cut workflow covers each server transition and capability', () => {
  const endpoints = [
    ['/branches/{branchId}/cuts', 'get'],
    ['/branches/{branchId}/cuts/generate', 'post'],
    ['/branches/{branchId}/cuts/{cutId}/open', 'post'],
    ['/branches/{branchId}/cuts/{cutId}/assets', 'get'],
    ['/branches/{branchId}/cuts/{cutId}/meters', 'post'],
    ['/branches/{branchId}/cuts/{cutId}/progress', 'get'],
    ['/branches/{branchId}/cuts/{cutId}/tanks', 'post'],
    ['/branches/{branchId}/cuts/{cutId}/prepare', 'post'],
    ['/branches/{branchId}/cuts/{cutId}/reconciliation', 'get'],
    ['/branches/{branchId}/cuts/{cutId}/review', 'post'],
    ['/branches/{branchId}/cuts/{cutId}/close', 'post'],
  ];
  for (const [path, method] of endpoints) assert.ok(spec.paths[path]?.[method], `falta ${method.toUpperCase()} ${path}`);
  for (const operation of ['dailyCuts', 'generateDailyCuts', 'cutAssets', 'openCut', 'captureCutMeter', 'cutProgress', 'measureCutTank', 'prepareCut', 'cutReconciliation', 'reviewCut', 'closeCut']) {
    assert.match(client, new RegExp(`func ${operation}\\(`), `falta transporte Swift ${operation}`);
    assert.match(client, new RegExp(`func ${operation}\\([^\\n]*\\) async throws`), `falta operación asíncrona ${operation}`);
  }
  assert.match(app, /contains\("cut\.read"\)[\s\S]*?RemoteCutsDirectoryView\(/);
  assert.match(app, /canCapture: appState\.remoteCapabilities\?\.permissions\.contains\("cut\.capture"\)/);
  assert.match(app, /canMeasureMeters: appState\.remoteCapabilities\?\.permissions\.contains\("inventory\.measure"\)/);
  assert.match(app, /canSubmit: appState\.remoteCapabilities\?\.permissions\.contains\("cut\.submit"\)/);
  assert.match(app, /canReviewOrClose: appState\.remoteCapabilities\?\.permissions\.contains\("cut\.close"\)/);
  assert.match(viewModel, /generated\.count == 2/);
  assert.match(viewModel, /reconciliation\.preparedBy != currentUserID/);
  assert.match(viewModel, /lastReadingType == "regular"/);
  assert.match(viewModel, /lastReadingAt\.map \{ \$0 >= cut\.startsAt && \$0 <= cut\.endsAt\.addingTimeInterval\(86_400\) \}/);
  assert.match(cutsView, /Lecturas de bombas/);
  assert.match(cutsView, /Medición física de tanques/);
  assert.match(cutsView, /Conciliación/);
  assert.match(cutsView, /scrollTransition/);
});

test('cut reconciliation preserves exact numeric strings and applied price versions', () => {
  assert.match(service, /'meterLiters',item\.value->>'meterLiters'/);
  assert.match(service, /'varianceLiters',item\.value->>'varianceLiters'/);
  assert.match(service, /'unitPriceUsd',price\.value->>'unitPriceUsd'/);
  assert.match(service, /'salesUsd',p\.financial_summary->>'salesUsd'/);
  assert.match(client, /struct RemoteDecimal: Decodable/);
  assert.match(client, /struct PriceVersion: Decodable/);
  assert.match(cutsView, /Precios aplicados en este turno/);
  assert.match(spec.components.schemas.CutReconciliation.properties.products.items.properties.priceVersions.items.properties.unitPriceUsd.type, /string/);
});

test('network dashboard reloads when the branch filter changes and exposes interactive chart selection', () => {
  assert.match(client, /func networkDashboard\(days: Int, branchID: UUID\? = nil\)/);
  assert.match(app, /private var dashboardQueryKey: String/);
  assert.match(app, /\.task\(id: dashboardQueryKey\)/);
  assert.match(app, /client\.networkDashboard\(days: days, branchID: selected\)/);
  assert.match(app, /@State private var availableBranches: \[RemoteNetworkDashboard\.Branch\] = \[\]/);
  assert.match(app, /ForEach\(availableBranches\)/);
  assert.match(app, /\.chartXSelection\(value: \$selectedDateKey\)/);
  assert.match(app, /.scrollTransition/);
});

test('dashboard, cuts and login motion respects the system Reduce Motion setting', () => {
  for (const view of [app, cutsView, login, branchDashboard, inventory]) {
    assert.match(view, /@Environment\(\\\.accessibilityReduceMotion\)/);
    assert.match(view, /\.animation\(reduceMotion \? nil :/);
  }
  assert.match(cutsView, /reduceMotion \? content : content\.opacity/);
  assert.match(app, /reduceMotion \? content : content\.opacity/);
});
