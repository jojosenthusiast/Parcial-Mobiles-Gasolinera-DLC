import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const spec = JSON.parse(await readFile(new URL('../../../contracts/openapi.json', import.meta.url), 'utf8'));
const infrastructureService = await readFile(new URL('../../src/infrastructure/infrastructure.service.ts', import.meta.url), 'utf8');

test('el contrato tiene versión y health routes documentadas', () => {
  assert.equal(spec.openapi, '3.1.0');
  assert.equal(spec.info.version, '1.0.0');
  assert.ok(spec.paths['/health/live']);
  assert.ok(spec.paths['/health/ready']);
  assert.ok(spec.servers.some(server => server.url === '/api/v1'));
});

test('el contrato separa identidad Cliente, lecturas públicas y vínculo de venta protegido', () => {
  for (const path of [
    '/customer/me/profile', '/customer/me', '/customer/me/loyalty', '/customer/me/points', '/customer/me/qr',
    '/customer/rewards', '/customer/campaigns', '/customer/branches', '/customer/services',
  ]) assert.ok(spec.paths[path], `falta documentar ${path}`);
  for (const path of ['/customer/me/profile','/customer/me','/customer/me/loyalty','/customer/me/points','/customer/me/qr']) {
    assert.ok(spec.paths[path][Object.keys(spec.paths[path])[0]].security, `${path} debe requerir token Cliente`);
  }
  assert.equal(spec.paths['/customer/rewards'].get.security, undefined);
  const link = spec.paths['/branches/{branchId}/sales/{saleId}/customer'].post;
  assert.deepEqual(link['x-required-permission'], 'sale.create');
  assert.deepEqual(link.requestBody.content['application/json'].schema.required, ['commandId','customerCode']);
});

test('promociones y avisos de Cliente exponen reglas, revisión y seguridad explícitas', () => {
  for (const path of ['/customer/promotions', '/customer/me/notifications', '/customer/me/notifications/read', '/promotions', '/promotions/preview', '/promotions/images', '/promotions/cashback-partners', '/promotions/cashback-partners/{code}/status', '/promotions/{promotionId}/versions', '/promotions/{promotionId}/submit', '/promotions/{promotionId}/decision', '/promotions/{promotionId}/pause', '/promotions/{promotionId}/resume']) {
    assert.ok(spec.paths[path], `falta documentar ${path}`);
  }
  assert.equal(spec.paths['/customer/promotions'].get.security, undefined);
  assert.equal(spec.paths['/customer/promotions'].get.parameters[0].name, 'branchId');
  assert.ok(spec.paths['/customer/me/notifications'].get.security);
  assert.deepEqual(spec.components.schemas.PromotionDecisionRequest.required, ['commandId', 'decision', 'reason']);
  const definition = spec.components.schemas.CreatePromotionRequest;
  assert.deepEqual(definition.properties.kind.enum, ['unit_discount', 'percent_discount', 'cashback', 'points_multiplier', 'announcement']);
  assert.equal(definition.properties.recurrence.oneOf.length, 3);
  assert.ok(definition.properties.targetBranchIds);
  assert.deepEqual(definition.properties.targetZones.items.enum, ['occidental','central','oriental','other']);
  assert.deepEqual(definition.properties.targetMetric.properties.metric.enum, ['sales_usd_30d','fuel_liters_30d']);
  assert.equal(definition.properties.terms.properties.applies.minItems, 1);
  assert.ok(spec.components.schemas.UploadPromotionImageRequest.required.includes('commandId'));
});

test('las respuestas del contrato declaran error estructurado', () => {
  assert.ok(spec.components.schemas.ApiError);
  assert.equal(spec.components.schemas.ApiError.required.includes('code'), true);
  assert.equal(spec.components.schemas.ApiError.required.includes('correlationId'), true);
});

test('el contrato publica rutas reales de identidad, sesiones y aprobación', () => {
  for (const path of [
    '/auth/login', '/auth/refresh', '/auth/me', '/auth/me/capabilities', '/auth/logout',
    '/auth/activate', '/auth/password-reset/complete', '/users/invitations',
    '/users/{userId}/password-reset', '/users/{userId}/status', '/users/{userId}/assignments',
    '/approvals/{approvalId}/decision',
  ]) assert.ok(spec.paths[path], `falta documentar ${path}`);
  assert.ok(spec.components.securitySchemes.bearerAuth);
  const identity = spec.paths['/auth/me'].get.responses['200'].content['application/json'].schema.properties.data;
  assert.equal(identity.$ref, '#/components/schemas/CurrentIdentity');
  assert.deepEqual(spec.components.schemas.CurrentIdentity.required, ['id', 'organizationId', 'displayName', 'email', 'roles']);
  assert.equal(spec.components.schemas.ActivateRequest.properties.password.minLength, 12);
});

test('el contrato publica navegación maestro-detalle de combustible e infraestructura', () => {
  for (const path of [
    '/branches/{branchId}/operating-profile', '/branches/{branchId}/configuration',
    '/fuel-products', '/fuel-products/{productId}', '/fuel-products/{productId}/specifications',
    '/branches/{branchId}/fuel-offers/{fuelProductId}', '/branches/{branchId}/tanks', '/branches/{branchId}/tanks/{tankId}',
    '/branches/{branchId}/dispensers', '/branches/{branchId}/dispensers/{dispenserId}',
    '/branches/{branchId}/dispensers/{dispenserId}/nozzles',
    '/branches/{branchId}/nozzles/{nozzleId}/tank-connection',
    '/branches/{branchId}/nozzles/{nozzleId}/availability',
    '/branches/{branchId}/asset-blocks', '/branches/{branchId}/asset-blocks/{blockId}/resolve',
    '/branches/{branchId}/{assetType}/{assetId}/status',
  ]) assert.ok(spec.paths[path], `falta documentar ${path}`);
  assert.ok(spec.components.schemas.OperatingProfile);
  assert.ok(spec.components.schemas.TankCreate);
});

test('el directorio de sucursales permite filtrar todos los estados y paginar', () => {
  const operation = spec.paths['/branches']?.get;
  assert.ok(operation);
  const parameters = new Map(operation.parameters.map(parameter => [parameter.name, parameter]));
  assert.equal(parameters.get('query').schema.maxLength, 100);
  assert.deepEqual(parameters.get('status').schema.enum, ['draft', 'configured', 'active', 'suspended', 'archived']);
  assert.equal(parameters.get('cursor').schema.format, 'uuid');
  assert.equal(parameters.get('limit').schema.maximum, 100);
});

test('el directorio de tanques documenta búsqueda, estados y ledger paginado', () => {
  const tanks = spec.paths['/branches/{branchId}/tanks']?.get;
  assert.ok(tanks);
  const parameters = new Map(tanks.parameters.map(parameter => [parameter.name, parameter]));
  assert.equal(parameters.get('query').schema.maxLength, 100);
  assert.deepEqual(parameters.get('status').schema.enum, ['active', 'maintenance', 'offline', 'decommissioned']);
  assert.equal(parameters.get('limit').schema.maximum, 200);
  assert.ok(spec.paths['/branches/{branchId}/tanks/{tankId}']?.get);
  assert.ok(spec.paths['/branches/{branchId}/tanks/{tankId}/inventory']?.get);
  const ledger = spec.paths['/branches/{branchId}/tanks/{tankId}/inventory/movements']?.get;
  assert.ok(ledger);
  assert.equal(new Map(ledger.parameters.map(parameter => [parameter.name, parameter])).get('limit').schema.maximum, 100);
});

test('el contrato publica alta reanudable de sucursales y readiness', () => {
  for (const path of ['/branches', '/branches/{branchId}', '/branches/{branchId}/onboarding', '/branches/{branchId}/readiness', '/branches/{branchId}/activate']) {
    assert.ok(spec.paths[path], `falta documentar ${path}`);
  }
  assert.ok(spec.components.schemas.BranchDraftRequest);
  assert.ok(spec.components.schemas.BranchDraftRequest.properties.profile.enum.includes('academicLab22'));
  assert.ok(spec.components.schemas.BranchDraftRequest.properties.expectedDispenserCount);
  assert.ok(spec.components.schemas.OnboardingStepRequest);
  assert.ok(spec.components.schemas.BranchActivationRequest);
  assert.deepEqual(spec.components.schemas.OnboardingStepRequest.properties.step.enum, [
    'identity', 'products', 'tanks', 'dispensers', 'staff', 'openingBalances', 'prices', 'review',
  ]);
});

test('el contrato publica movimientos inmutables de inventario en unidades explícitas', () => {
  for (const path of [
    '/branches/{branchId}/tanks/{tankId}/inventory',
    '/branches/{branchId}/tanks/{tankId}/inventory/movements',
    '/branches/{branchId}/tanks/{tankId}/inventory/opening',
    '/branches/{branchId}/tanks/{tankId}/inventory/receipts',
    '/branches/{branchId}/tanks/{tankId}/inventory/sales',
    '/branches/{branchId}/tanks/{tankId}/inventory/losses',
    '/branches/{branchId}/tanks/{tankId}/inventory/adjustments',
  ]) assert.ok(spec.paths[path], `falta documentar ${path}`);
  assert.deepEqual(spec.components.schemas.InventoryCommandRequest.properties.unit.enum, ['liter', 'us_gallon']);
  assert.ok(spec.components.schemas.InventoryCommandRequest.properties.compensatedQuantity);
  assert.ok(spec.components.schemas.InventoryOpeningRequest.required.includes('valuationQuality'));
});

test('el contrato separa referencia, propuesta, aprobación y precio vigente', () => {
  for (const path of [
    '/fuel-market-references', '/branches/{branchId}/fuel-prices',
    '/branches/{branchId}/fuel-prices/{fuelProductId}/history',
    '/branches/{branchId}/fuel-price-proposals', '/fuel-price-proposals/{proposalId}/approve',
    '/fuel-price-proposals/{proposalId}/reject', '/fuel-price-proposals/{proposalId}/schedule',
  ]) assert.ok(spec.paths[path], `falta documentar ${path}`);
  assert.deepEqual(spec.components.schemas.FuelPriceProposalRequest.properties.serviceMode.enum, ['full_service','self_service']);
  assert.equal(spec.components.schemas.FuelPriceProposalRequest.properties.effectiveAt.format, 'date-time');
  assert.ok(spec.components.schemas.MarketPriceReferenceRequest.properties.sourceName);
});

test('el contrato publica proveedores y transiciones de órdenes de compra', () => {
  for (const path of [
    '/suppliers', '/branches/{branchId}/purchase-orders', '/branches/{branchId}/purchase-orders/{orderId}',
    '/branches/{branchId}/purchase-orders/{orderId}/submit',
    '/branches/{branchId}/purchase-orders/{orderId}/approve',
    '/branches/{branchId}/purchase-orders/{orderId}/reject',
    '/branches/{branchId}/purchase-orders/{orderId}/mark-ordered',
    '/branches/{branchId}/purchase-orders/{orderId}/receipts',
    '/branches/{branchId}/purchase-orders/{orderId}/invoices',
    '/branches/{branchId}/supplier-invoices/{invoiceId}/payments',
    '/branches/{branchId}/purchase-orders/{orderId}/cancel',
  ]) assert.ok(spec.paths[path], `falta documentar ${path}`);
  assert.ok(spec.components.schemas.SupplierCreateRequest.properties.offers);
  assert.deepEqual(spec.components.schemas.PurchaseOrderLineRequest.properties.unit.enum, ['liter','us_gallon']);
  assert.equal(spec.components.schemas.PurchaseOrderDecisionRequest.properties.expectedVersion.type, 'integer');
  assert.ok(spec.components.schemas.PurchaseReceiptRequest.properties.inventory);
  assert.ok(spec.components.schemas.SupplierPaymentRequest.properties.commandId);
});

test('el contrato publica lecturas continuas y reemplazos autorizados de totalizador', () => {
  for (const path of [
    '/branches/{branchId}/nozzles/{nozzleId}/meter-readings',
    '/branches/{branchId}/nozzles/{nozzleId}/meter-readings/baseline',
    '/branches/{branchId}/nozzles/{nozzleId}/meter-changes',
  ]) assert.ok(spec.paths[path], `falta documentar ${path}`);
  assert.equal(spec.components.schemas.NozzleMeterChangeRequest.properties.newSerial.minLength, 1);
  assert.equal(spec.components.schemas.NozzleMeterReadingRequest.properties.expectedVersion.minimum, 0);
});

test('repetir una acción idempotente devuelve el detalle actualizado de despacho', () => {
  for (const method of ['reportDispenseProgress', 'dispenseTransition']) {
    const start = infrastructureService.indexOf(`async ${method}(`);
    assert.notEqual(start, -1, `falta ${method}`);
    const end = infrastructureService.indexOf('\n  async ', start + 1);
    const body = infrastructureService.slice(start, end === -1 ? undefined : end);
    assert.match(body, /if\(replay\).*return this\.dispenseDetail\(authorizationId,branchId,principal\)/s);
  }
});

test('el contrato publica autorización, reserva, progreso y conciliación de despacho', () => {
  for (const path of [
    '/branches/{branchId}/nozzles/{nozzleId}/dispense-authorizations',
    '/branches/{branchId}/dispense-authorizations/{authorizationId}',
    '/branches/{branchId}/dispense-authorizations/{authorizationId}/start',
    '/branches/{branchId}/dispense-authorizations/{authorizationId}/progress',
    '/branches/{branchId}/dispense-authorizations/{authorizationId}/complete',
    '/branches/{branchId}/dispense-authorizations/{authorizationId}/cancel',
    '/branches/{branchId}/dispense-authorizations/{authorizationId}/unknown',
    '/branches/{branchId}/dispense-authorizations/{authorizationId}/reconcile-no-flow',
  ]) assert.ok(spec.paths[path], `falta documentar ${path}`);
  assert.equal(spec.components.schemas.CreateDispenseAuthorizationRequest.properties.expiresInSeconds.maximum, 300);
  assert.ok(spec.components.schemas.DispenseCompletionRequest.properties.documentReference);
  assert.deepEqual(spec.components.schemas.DispenseNoFlowReconciliationRequest.required, ['commandId','expectedVersion','evidenceReference','reason']);
});

test('el contrato permite recuperar autorizaciones activas con permiso de lectura y cursor', () => {
  const operation = spec.paths['/branches/{branchId}/dispense-authorizations']?.get;
  assert.ok(operation);
  const parameters = new Map(operation.parameters.map(parameter => [parameter.name, parameter]));
  assert.deepEqual(parameters.get('status').schema.enum, ['active', 'authorized', 'dispensing', 'unknown', 'posting', 'completed', 'cancelled', 'expired']);
  assert.equal(parameters.get('cursor').schema.format, 'uuid');
  assert.equal(parameters.get('limit').schema.maximum, 100);
  assert.ok(operation.responses['403'].description.includes('dispense.read'));
});

test('la consulta de despachos limita el alcance y diferencia reservas activas vencidas', () => {
  const start = infrastructureService.indexOf('async listDispenseAuthorizations(');
  const end = infrastructureService.indexOf('\n  async dispenseDetail(', start);
  assert.notEqual(start, -1);
  const body = infrastructureService.slice(start, end);
  assert.match(body, /await this\.requireBranch\(this\.pool,branchId,principal\)/);
  assert.match(body, /a\.organization_id=\$1/);
  assert.match(body, /a\.branch_id=\$2/);
  assert.match(body, /a\.status IN \('dispensing','unknown','posting'\)/);
  assert.match(body, /a\.status='authorized' AND a\.expires_at>now\(\)/);
  assert.match(body, /a\.status='authorized' AND a\.expires_at<=now\(\)/);
  assert.match(body, /CASE WHEN a\.status='authorized' AND a\.expires_at<=now\(\) THEN 'expired'/);
  assert.match(body, /ORDER BY a\.id DESC LIMIT \$\$\{values\.length\}/);
  assert.match(body, /const limit=Math\.max\(1,Math\.min\(100,filters\.limit\)\)/);
});

test('el contrato contempla preview de migración como permiso protegido sin publicar inventario', () => {
  assert.ok(spec.paths['/imports/preview']);
  assert.ok(spec.paths['/imports/{batchId}']);
  assert.ok(spec.components.schemas.LegacyPreviewRequest);
});
