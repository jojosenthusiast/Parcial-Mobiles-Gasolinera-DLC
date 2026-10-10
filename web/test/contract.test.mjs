import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const contract = JSON.parse(await readFile(new URL('../../contracts/openapi.json', import.meta.url), 'utf8'));
const app = await readFile(new URL('../public/app.js', import.meta.url), 'utf8');
const inventoryService = await readFile(new URL('../../server/src/inventory/fuel-inventory.service.ts', import.meta.url), 'utf8');
const contaminationService = await readFile(new URL('../../server/src/procurement/contamination.service.ts', import.meta.url), 'utf8');
const salesService = await readFile(new URL('../../server/src/sales/sales.service.ts', import.meta.url), 'utf8');

test('el futuro cliente web comparte la API versionada y sus respuestas de error', () => {
  assert.equal(contract.servers[0].url, '/api/v1');
  assert.ok(contract.components.schemas.ApiError.properties.correlationId);
  assert.ok(contract.paths['/users']?.get, 'el contrato debe exponer el listado acotado de cuentas');
});

test('la descarga contaminante exige selección explícita y muestra combustible y volumen legibles', () => {
  assert.match(app, /Selecciona combustible/);
  assert.match(app, /Selecciona el tanque afectado/);
  assert.match(app, /volumeBoth\(preview\.priorQuantityL\)/);
  assert.match(app, /if\(value==null\|\|value===\'\'\)return \'Desconocido\'/);
  assert.match(app, /products\.find\(p=>p\.id===l\.fuelProductId\)/);
});

test('el retiro se habilita tras aprobar las pérdidas y la lista conserva responsables y evidencia', () => {
  assert.match(app, /r\.incoming_loss_approval_id&&\(Number\(r\.prior_quantity_l\)===0\|\|r\.prior_loss_approval_id\)/);
  assert.match(app, /incoming_loss_approver_name/);
  assert.match(app, /prior_loss_approver_name/);
  assert.match(app, /disposal_evidence_reference/);
  assert.match(contaminationService, /a\.reason AS incoming_loss_approval_reason/);
  assert.match(contaminationService, /x\.evidence_reference AS disposal_evidence_reference/);
});

test('los errores del cliente web muestran una referencia rastreable sin imprimir datos sensibles', () => {
  assert.match(app, /class DlcApiError extends Error/);
  assert.match(app, /correlationId:payload\?\.correlationId\|\|r\.headers\.get\('x-request-id'\)/);
  assert.match(app, /Ref\. \$\{error\.correlationId\}/);
  assert.match(app, /console\.error\('\[DLC error\]',JSON\.stringify\(\{event:'client\.request\.failed',status:error\?\.status\|\|0,code:error\?\.code\|\|'CLIENT_ERROR',correlationId:error\?\.correlationId\|\|null\}\)\)/);
});

test('las pantallas invocadas desde el router tienen implementación', () => {
  const definitions = new Set([...app.matchAll(/(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(/g)].map(match => match[1]));
  const routeBlock = app.match(/async function render\(\)\{([\s\S]*?)\nfunction stat\(/)?.[1];
  assert.ok(routeBlock, 'render debe existir y cerrar antes de stat');
  const calls = [...routeBlock.matchAll(/await\s+([A-Za-z_$][\w$]*)\s*\(/g)].map(match => match[1]);
  assert.ok(calls.length > 0);
  for (const name of calls) assert.ok(definitions.has(name), `falta implementar ${name}()`);
  assert.match(app, /data-assessment/);
  assert.match(app, /fuel-price-proposals/);
  assert.match(app, /meter-readings\?limit=50/);
  assert.match(app, /shifts\/\$\{id\}\/attendance/);
  assert.match(app, /includes\('infrastructure\.read'\)/);
  assert.match(app, /<option value="forecourt">Despacho/);
  assert.match(app, /No hay combustibles activos disponibles para este formulario/);
  assert.match(app, /branches\/\$\{id\}\/readiness/);
  assert.match(app, /fuel-product-create/);
  assert.match(app, /branches\/\$\{state\.branchId\}\/dispensers\/\$\{v\.id\}\/nozzles/);
  assert.match(app, /tank-connection/);
  assert.match(app, /async function usersPage\(/);
  assert.match(app, /data-user-detail/);
  assert.match(app, /id="users-detail"/);
  assert.match(app, /data-reassign-role/);
  assert.match(app, /users\/\$\{userId\}\/assignments/);
  assert.match(app, /function syncRoute\(\)/);
  assert.match(app, /function restoreRoute\(\)/);
  assert.match(app, /window\.addEventListener\('popstate',\(\)=>\{if\(state\.me\)restoreRoute\(\)\}\)/);
  assert.match(app, /history\.pushState\(\{\},'',location\.href\)/);
  assert.match(app, /const storedDays=Number\(new URL\(location\.href\)\.searchParams\.get\('days'\)\)/);
  assert.match(app, /days:\[1,7,30\]\.includes\(storedDays\)\?storedDays:7/);
  assert.match(app, /url\.searchParams\.set\('days',\[1,7,30\]\.includes\(Number\(state\.days\)\)\?String\(state\.days\):'7'\)/);
  assert.match(app, /branch-select'\)\.onchange=e=>\{if\(state\.branchId!==\(e\.target\.value\|\|null\)\)history\.pushState/);
  assert.match(app, /period'\)\.onchange=e=>\{const days=Number\(e\.target\.value\);if\(state\.days!==days\)history\.pushState/);
  assert.match(app, /requestedBranch&&state\.branches\.some\(b=>b\.id===requestedBranch\)/);
  assert.match(app, /function filterValue\(key,fallback=''/);
  assert.match(app, /saveFilter\('cuts\.date',date\)/);
  assert.match(app, /saveFilter\('incidents\.query'/);
  assert.match(app, /saveFilter\('incidents\.severity'/);
  assert.match(app, /p\.set\('severity',\$\('#incident-severity'\)\.value\)/);
  assert.match(app, /saveFilter\('store\.kind'/);
  assert.match(app, /saveFilter\('users\.status'/);
  assert.match(app, /supplier-detail/);
  assert.match(app, /data-supplier=/);
  assert.match(app, /Usar en una orden/);
  assert.match(app, /data-supplier-offer/);
  assert.match(app, /offers\.length\?\{offers\}/);
  assert.match(app, /supplier\?\.offers\?\.some\(o=>o\.fuelProductId===p\.id\)/);
  assert.match(app, /data-quoted-price/);
  assert.match(app, /cotización vencida/);
  assert.match(app, /async function storePage\(/);
  assert.match(app, /async function cashPage\(/);
  assert.match(app, /cash\/sessions\/\$\{id\}\/close/);
  assert.match(app, /payments\/\$\{b\.dataset\.resolvePayment\}\/resolve/);
  assert.match(app, /result\?\.meta\?\.nextCursor/);
  assert.match(app, /res\?\.meta\?\.nextCursor/);
  assert.match(app, /pos\/stock\/receipts/);
  assert.match(app, /pos\/stock\/counts/);
  assert.match(app, /pos\/stock\/lots\/\$\{lotId\}\/condition/);
  assert.match(app, /classify-count/);
  assert.match(app, /asset-blocks/);
  assert.match(app, /branches\/\$\{state\.branchId\}\/tanks/);
  assert.match(app, /branch-more/);
  assert.match(app, /cursor:branchCursor/);
  assert.match(app, /onboarding-grid/);
  assert.match(app, /data-edit-identity/);
  assert.match(app, /confirm-staff-review/);
  assert.match(app, /defer-staff-review/);
  assert.match(app, /El borrador se guarda en el servidor/);
  assert.match(app, /branches\/\$\{id\}\/onboarding/);
  assert.match(app, /saveFilter\('staff\.query'/);
  assert.match(app, /saveFilter\('staff\.status'/);
  assert.match(app, /saveFilter\('staff\.from'/);
  assert.match(app, /saveFilter\('staff\.to'/);
  assert.match(app, /staff\/employees\?\$\{employeeParams\}/);
  assert.match(app, /data-employee-detail/);
  assert.match(app, /data-edit-employee/);
  assert.match(app, /staff\.private\.read/);
  assert.match(app, /method:'PATCH',data:payload/);
  assert.ok(contract.paths['/branches/{branchId}/staff/employees/{employeeId}']?.patch);
  assert.match(app, /staff\/shifts\?from=\$\{encodeURIComponent\(from\)\}&to=\$\{encodeURIComponent\(to\)\}/);
  assert.match(app, /staff-more/);
  assert.match(app, /El periodo debe tener fechas válidas y abarcar entre 1 y 31 días/);
  assert.match(app, /dailySeries/);
  assert.match(app, /Tendencia diaria de ventas/);
  assert.match(app, /Ver valores exactos por día/);
  assert.match(app, /timeZone:'America\/El_Salvador'/);
  assert.match(app, /Consumo y venta por combustible/);
  assert.match(app, /Tu cuenta no tiene permiso para consultar métricas de ventas/);
  assert.match(app, /saveFilter\('finance\.from'/);
  assert.match(app, /saveFilter\('finance\.status'/);
  assert.match(app, /expenseParams\(expenseCursor\)/);
  assert.match(app, /Mostrar más gastos/);
  assert.equal(contract.paths['/branches/{branchId}/finance/expenses'].get.parameters.find(parameter => parameter.name === 'q').schema.maxLength, 100);
  assert.match(app, /incident-more/);
  assert.match(app, /p\.set\('q',\$\('#incident-search'\)\.value\.trim\(\)\)/);
  assert.equal(contract.paths['/branches/{branchId}/incidents'].get.parameters.find(parameter => parameter.name === 'cursor').schema.format, 'uuid');
  assert.match(app, /purchases\.orderStatus/);
  assert.match(app, /purchase-order-more/);
  assert.match(app, /saveFilter\('maintenance\.status'/);
  assert.match(app, /work-order-more/);
  assert.equal(contract.paths['/branches/{branchId}/maintenance/orders'].get.parameters.find(parameter => parameter.name === 'cursor').schema.format, 'uuid');
  assert.match(app, /cash-movement-kind/);
  assert.match(app, /cash-movement-more/);
  assert.match(app, /beforeAt',movementCursor\.beforeAt/);
  assert.match(app, /beforeId',movementCursor\.beforeId/);
  assert.ok(contract.components.schemas.BranchReadiness.properties.activeEmployeeCount);
  assert.equal(contract.paths['/branches/{branchId}/readiness'].get.responses['200'].content['application/json'].schema.$ref, '#/components/schemas/BranchReadiness');
  assert.match(app, /saveFilter\('inventory\.query'/);
  assert.match(app, /saveFilter\('inventory\.state'/);
  assert.match(app, /saveFilter\('inventory\.tank'/);
  assert.match(app, /inventory\/movements\?\$\{params\}/);
  assert.match(app, /page\?\.meta\?\.nextCursor/);
  assert.match(app, /inventory-movement-more/);
  assert.match(app, /cr\[ií\]tico/);
  assert.match(app, /atenci\[oó\]n/);
  assert.match(inventoryService, /meta: \{ limit: pageLimit, nextCursor:/);
  assert.ok(contract.paths['/branches/{branchId}/tanks/{tankId}/inventory/movements']?.get);
  assert.match(app, /filterValue\('prices\.product'\)/);
  assert.match(app, /saveFilter\('prices\.product'/);
  assert.match(app, /saveFilter\('prices\.mode'/);
  assert.match(app, /saveFilter\('prices\.proposalStatus'/);
  assert.match(app, /saveFilter\('prices\.marketZone'/);
  assert.match(app, /saveFilter\('prices\.marketProduct'/);
  assert.match(app, /priceQuery\.set\('fuelProductId',priceProduct\)/);
  assert.match(app, /priceQuery\.set\('serviceMode',priceMode\)/);
  assert.match(app, /proposalQuery\.set\('status',proposalStatus\)/);
  assert.match(app, /marketQuery\.set\('zone',marketZone\)/);
  assert.match(app, /marketQuery\.set\('fuelProductId',marketProduct\)/);
});

test('el contrato de precios mantiene filtros de servidor y permisos de lectura', async () => {
  const pricingController = await readFile(new URL('../../server/src/pricing/pricing.controller.ts', import.meta.url), 'utf8');
  const pricingService = await readFile(new URL('../../server/src/pricing/pricing.service.ts', import.meta.url), 'utf8');
  assert.match(pricingController, /@RequirePermission\('price\.read'\)[\s\S]*?@Get\('branches\/:branchId\/fuel-prices'\)[\s\S]*?@Query\('fuelProductId'\)[\s\S]*?@Query\('serviceMode'\)/);
  assert.match(pricingController, /@Get\('branches\/:branchId\/fuel-price-proposals'\)[\s\S]*?@Query\('status'\)/);
  assert.match(pricingController, /@Get\('fuel-market-references'\)[\s\S]*?@Query\('zone'\)[\s\S]*?@Query\('fuelProductId'\)/);
  assert.match(pricingService, /v\.fuel_product_id=\$\$\{values\.length\}/);
  assert.match(pricingService, /v\.service_mode=\$\$\{values\.length\}/);
  assert.match(pricingService, /p\.status=\$3/);
  assert.match(pricingService, /zone=\$\$\{values\.length\}/);
  assert.match(pricingService, /fuel_product_id=\$\$\{values\.length\}/);
});

test('tablas, navegación móvil y movimiento respetan accesibilidad básica', async () => {
  const styles = await readFile(new URL('../public/styles.css', import.meta.url), 'utf8');
  const html = await readFile(new URL('../public/index.html', import.meta.url), 'utf8');
  assert.match(app, /role="group" aria-label="Tabla desplazable horizontalmente" tabindex="0"/);
  assert.match(app, /aria-current="\$\{state\.page===id\?'page':'false'\}"/);
  assert.match(app, /<th scope="col">/);
  assert.match(app, /function scrollToSection\(element,block='start'\)/);
  assert.match(app, /prefers-reduced-motion: reduce/);
  assert.match(styles, /env\(safe-area-inset-bottom\)/);
  assert.match(styles, /\.table-wrap:focus-visible/);
  assert.match(styles, /a:focus-visible,summary:focus-visible/);
  assert.match(styles, /@media\(prefers-reduced-motion:reduce\)/);
  assert.match(html, /class="skip-link" href="#content"/);
  assert.match(html, /nav id="navigation" aria-label="Módulos de operación"/);
});

test('reportes conservan el periodo en hora de El Salvador y cierran la paginación correctamente', () => {
  assert.match(app, /filterValue\('reports\.from'\)/);
  assert.match(app, /filterValue\('reports\.to'\)/);
  assert.match(app, /filterValue\('reports\.type'\)/);
  assert.match(app, /saveFilter\('reports\.from',from\)/);
  assert.match(app, /saveFilter\('reports\.groupBy'/);
  assert.match(app, /Date\.UTC\(reportYear,reportMonth-1,reportDay-rangeDays\)/);
  assert.match(app, /validReportDate\(from\).*span>365/);
  assert.match(app, /id="more-rows" data-offset=/);
  assert.match(app, /button\.hidden=!Number\.isInteger\(d\.nextOffset\)/);
});

test('el dashboard de sucursal distingue inventario en cero de mediciones ausentes', () => {
  assert.match(app, /measuredTanks=tanks\.filter\(t=>t\.percentage!==null&&t\.percentage!==undefined&&Number\.isFinite\(Number\(t\.percentage\)\)\)/);
  assert.match(app, /pct===null\?'Sin mediciones de nivel'/);
  assert.match(app, /inventory\.totalLiters===null\|\|inventory\.totalLiters===undefined\?'Sin dato'/);
  assert.doesNotMatch(app, /inventory\.totalLiters\?`\$\{Math\.round\(inventory\.totalLiters\)/);
});

test('el flujo de cortes ofrece captura, conciliación y cierre con permisos y versiones', async () => {
  assert.match(app, /cuts\/generate/);
  assert.match(app, /cuts\/\$\{id\}\/open/);
  assert.match(app, /meter-readings/);
  assert.match(app, /cuts\/\$\{id\}\/meters/);
  assert.match(app, /cuts\/\$\{id\}\/tanks/);
  assert.match(app, /cuts\/\$\{id\}\/prepare/);
  assert.match(app, /cuts\/\$\{id\}\/review/);
  assert.match(app, /cuts\/\$\{id\}\/close/);
  assert.match(app, /expectedVersion:Number\(cut\.version\)/);
  assert.match(app, /n\.meterVersion===null\|\|n\.meterVersion===undefined/);
  assert.match(app, /inReview/);
  assert.match(app, /ledgerLiters/);
  assert.match(app, /closedByName/);
  assert.doesNotMatch(app, /JSON\.stringify\(rec,null,2\)/);
  const controller = await readFile(new URL('../../server/src/cuts/cuts.controller.ts', import.meta.url), 'utf8');
  assert.match(controller, /@RequirePermission\('cut\.submit'\).*@Post\(':cutId\/prepare'\)/s);
  assert.match(controller, /@RequirePermission\('cut\.close'\).*@Post\(':cutId\/review'\)/s);
  assert.match(controller, /@RequirePermission\('cut\.close'\).*@Post\(':cutId\/close'\)/s);
});

test('la ficha de equipo permite fijar una línea base y enlaza la lectura capturada al corte', async () => {
  const infrastructureController = await readFile(new URL('../../server/src/infrastructure/infrastructure.controller.ts', import.meta.url), 'utf8');
  const infrastructureService = await readFile(new URL('../../server/src/infrastructure/infrastructure.service.ts', import.meta.url), 'utf8');
  assert.match(app, /nozzle-meter-entry/);
  assert.match(app, /meter-readings\/baseline/);
  assert.match(app, /expectedVersion:baseline\?0:Number\(form\.dataset\.version\)/);
  assert.match(app, /n\.lastReadingType==='regular'/);
  assert.match(infrastructureController, /@RequirePermission\('inventory\.measure'\)\s*@Post\('branches\/:branchId\/nozzles\/:nozzleId\/meter-readings\/baseline'\)/);
  assert.match(infrastructureService, /if\(current\|\|input\.expectedVersion!==0\) throw new ConflictException/);
  assert.match(infrastructureService, /if\(readingType==='regular'&&reading\.lt\(current\.last_value\)\)/);
  assert.ok(contract.paths['/branches/{branchId}/nozzles/{nozzleId}/meter-readings/baseline']?.post);
});

test('caja representa importes cero y enlaza los formularios con los permisos requeridos', async () => {
  assert.doesNotMatch(app, /selectedSession\s*=/, 'la apertura no debe fallar por asignar a una variable global no declarada');
  assert.match(app, /value===null\|\|value===undefined\?'—'/, 'cero debe mostrarse como $0.00 y no como dato ausente');
  assert.match(app, /paymentForm\.elements\.evidenceReference\.required=card&&paymentForm\.elements\.mode\.value==='manual'&&paymentForm\.elements\.outcome\.value!=='unknown'/);
  assert.match(app, /cash\/sessions\/\$\{id\}\/close/);
  assert.match(app, /payments\/\$\{b\.dataset\.resolvePayment\}\/resolve/);
  const staff = await readFile(new URL('../../server/src/staff/staff.controller.ts', import.meta.url), 'utf8');
  assert.match(staff, /@Get\('employees'\)/);
  assert.match(staff, /@Get\('shifts'\)/);
  const payments = await readFile(new URL('../../server/src/sales/payments.controller.ts', import.meta.url), 'utf8');
  for (const route of ['cash/registers', 'cash/sessions', 'cash/sessions/:sessionId/review', 'cash/sessions/:sessionId/movements', 'payments/:attemptId/resolve']) {
    assert.ok(payments.includes(route), `payments controller debe exponer ${route}`);
  }
});

test('la caja web aplica el saldo pendiente y expone el recibo PDF marcado no fiscal', () => {
  assert.ok(salesService.includes('cb.outstanding_usd::text AS \"outstandingUsd\"'));
  assert.ok(app.includes('sale.outstandingUsd??sale.totalUsd'));
  assert.ok(app.includes('commandId:paymentCommandId'));
  assert.ok(app.includes('/sales/${saleId}/receipt.pdf'));
  assert.ok(contract.paths['/branches/{branchId}/sales/{saleId}/receipt.pdf'].get.responses['200'].content['application/pdf']);
});


test('quick retail products use store lots and have server-backed category filters', () => {
  assert.match(app, /id=\"store-category\"/);
  assert.match(app, /id=\"store-create-category\"/);
  assert.match(app, /pos\/catalog\/categories/);
  assert.match(app, /p\.set\('category',\$\('#store-category'\)\.value\)/);
  assert.ok(contract.paths['/branches/{branchId}/pos/catalog/categories']);
  assert.ok(contract.paths['/branches/{branchId}/pos/catalog'].get.parameters.some(parameter => parameter.name === 'category'));
});
