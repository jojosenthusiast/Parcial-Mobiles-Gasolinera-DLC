import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const spec = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
const apiClient = await readFile(new URL('../../../DLCGasolineras/Services/RemoteAPIClient.swift', import.meta.url), 'utf8');
const apiImplementation = apiClient.slice(apiClient.indexOf('final class RemoteAPIClient'));
const branchViews = await readFile(new URL('../../../DLCGasolineras/Views/GeneralManager/BranchesView.swift', import.meta.url), 'utf8');
const app = await readFile(new URL('../../../DLCGasolineras/App/DLCGasolinerasApp.swift', import.meta.url), 'utf8');
const infrastructureController = await readFile(new URL('../../src/infrastructure/infrastructure.controller.ts', import.meta.url), 'utf8');
const infrastructureService = await readFile(new URL('../../src/infrastructure/infrastructure.service.ts', import.meta.url), 'utf8');
const staffController = await readFile(new URL('../../src/staff/staff.controller.ts', import.meta.url), 'utf8');
const staffService = await readFile(new URL('../../src/staff/staff.service.ts', import.meta.url), 'utf8');
const pricingController = await readFile(new URL('../../src/pricing/pricing.controller.ts', import.meta.url), 'utf8');
const pricingService = await readFile(new URL('../../src/pricing/pricing.service.ts', import.meta.url), 'utf8');

test('SwiftUI branch onboarding uses the documented server create/readiness/save/activate API', () => {
  for (const [path, method] of [
    ['/branches', 'post'],
    ['/branches/{branchId}/readiness', 'get'],
    ['/branches/{branchId}/onboarding', 'patch'],
    ['/branches/{branchId}/activate', 'post'],
  ]) {
    assert.ok(spec.paths[path]?.[method], `falta contrato ${method.toUpperCase()} ${path}`);
  }
  for (const method of ['createBranchDraft', 'branchReadiness', 'saveOnboardingStep', 'activateBranch']) {
    assert.match(apiClient, new RegExp(`func ${method}\\(`), `falta cliente Swift ${method}`);
    assert.match(apiClient, new RegExp(`func ${method}\\([^\\n]*\\) async throws`), `falta transporte asíncrono para ${method}`);
  }
  for (const method of ['createBranchDraft', 'branchDetail', 'branchReadiness', 'saveOnboardingStep', 'activateBranch']) {
    const start = apiImplementation.indexOf(`func ${method}(`);
    const end = apiImplementation.indexOf('\n    func ', start + 1);
    const implementation = apiImplementation.slice(start, end < 0 ? undefined : end);
    assert.match(implementation, /try await send\(/, `${method} debe decodificar el cuerpo que realmente devuelve el controller`);
    assert.doesNotMatch(implementation, /Envelope</, `${method} no devuelve un wrapper data según BranchesService`);
  }
  assert.match(branchViews, /RemoteBranchOnboardingView/);
  assert.match(branchViews, /expectedVersion: readiness\.onboardingVersion/);
  assert.match(branchViews, /readiness\.activeEmployeeCount < 1/);
  assert.match(branchViews, /readiness\.canActivate && canActivateBranches/);
  assert.match(branchViews, /"products", "tanks", "dispensers", "openingBalances", "staff", "prices", "review"/);
  assert.match(app, /canManageBranches: appState\.remoteCapabilities\?\.permissions\.contains\("branch\.manage"\)/);
});

test('SwiftUI onboarding routes match the API endpoints and response envelopes', () => {
  for (const [path, methods] of [
    ['/branches/{branchId}/configuration', ['get']],
    ['/fuel-products', ['get', 'post']],
    ['/branches/{branchId}/fuel-offers/{fuelProductId}', ['put']],
    ['/branches/{branchId}/staff/employees', ['get', 'post']],
    ['/branches/{branchId}/fuel-prices', ['get']],
    ['/branches/{branchId}/fuel-price-proposals', ['get', 'post']],
  ]) {
    for (const method of methods) assert.ok(spec.paths[path]?.[method], `falta contrato ${method.toUpperCase()} ${path}`);
  }

  assert.match(infrastructureController, /@Get\('branches\/:branchId\/configuration'\)/);
  assert.match(infrastructureService, /return \{ data: \{ \.\.\.branch, fuelOffers:/);
  assert.match(apiImplementation, /Envelope<RemoteBranchConfiguration>/);
  assert.match(infrastructureController, /@Put\('branches\/:branchId\/fuel-offers\/:fuelProductId'\)/);
  assert.match(infrastructureService, /RETURNING branch_id AS "branchId",fuel_product_id AS "fuelProductId",status,version,valid_from AS "validFrom"/);
  assert.match(apiImplementation, /Envelope<RemoteFuelOfferActivationResult>/);
  assert.doesNotMatch(apiImplementation, /Envelope<RemoteBranchFuelOffer> = try await send\(path: "branches\/.*fuel-offers/);

  assert.match(staffController, /@Get\('employees'\)/);
  assert.match(staffService, /return \{data,meta:\{limit,nextCursor:/);
  assert.match(apiImplementation, /RemotePage<RemoteEmployeeSummary>/);
  assert.match(staffService, /return \{data:\{\.\.\.value\.data,idempotentReplay:/);
  assert.match(apiImplementation, /Envelope<Result> = try await send\(path: "branches\/.*staff\/employees/);

  assert.match(pricingController, /@Get\('branches\/:branchId\/fuel-prices'\)/);
  assert.match(pricingService, /return \{ current: result\.rows, upcoming: upcoming\.rows \}/);
  assert.match(pricingService, /p\.display_name AS "productName"/);
  assert.match(apiImplementation, /func fuelPriceBoard\(branchID: UUID\) async throws -> RemoteBranchFuelPriceBoard \{[\s\S]*?fuel-prices/);
  assert.match(pricingController, /@Get\('branches\/:branchId\/fuel-price-proposals'\)/);
  assert.match(pricingService, /return \{ data: result\.rows \}/);
  assert.match(apiImplementation, /Envelope<\[RemoteFuelPriceProposal\]>/);
  assert.match(pricingController, /@Post\('branches\/:branchId\/fuel-price-proposals'\)/);
  assert.match(apiImplementation, /RemoteFuelPriceProposal = try await send\(path: "branches\/.*fuel-price-proposals/);

  for (const view of ['RemoteFuelOfferSetupView', 'RemoteBranchStaffSetupView', 'RemoteBranchPriceSetupView']) {
    assert.match(branchViews, new RegExp(`NavigationLink \\{ ${view}`), `el paso de onboarding no enlaza ${view}`);
  }
  assert.match(branchViews, /@State private var unit = "us_gallon"/);
  assert.match(branchViews, /canProposePrices && canReadFuel && canReadInfrastructure/);
});
