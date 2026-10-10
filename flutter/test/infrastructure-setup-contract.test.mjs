import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../', import.meta.url);
const read = (path) => readFile(new URL(path, root), 'utf8');

test('Flutter infrastructure setup uses server routes and permission contract', async () => {
  const [api, controller, inventoryController, screen, main, staffController, staffScreen, branchController, branchService, onboarding, pricingController, pricesScreen, maintenanceController, maintenanceService, maintenanceScreen] = await Promise.all([
    read('flutter/packages/dlc_api/lib/src/employee_session.dart'),
    read('server/src/infrastructure/infrastructure.controller.ts'),
    read('server/src/inventory/fuel-inventory.controller.ts'),
    read('flutter/apps/dlc_operations/lib/infrastructure_setup_screen.dart'),
    read('flutter/apps/dlc_operations/lib/main.dart'),
    read('server/src/staff/staff.controller.ts'),
    read('flutter/apps/dlc_operations/lib/staff_shifts_screen.dart'),
    read('server/src/branches/branches.controller.ts'),
    read('server/src/staff/staff.service.ts'),
    read('flutter/apps/dlc_operations/lib/branch_onboarding_screen.dart'),
    read('server/src/pricing/pricing.controller.ts'),
    read('flutter/apps/dlc_operations/lib/branch_prices_screen.dart'),
    read('server/src/maintenance/maintenance.controller.ts'),
    read('server/src/maintenance/maintenance.service.ts'),
    read('flutter/apps/dlc_operations/lib/maintenance_screen.dart'),
  ]);

  for (const route of [
    '/configuration', '/fuel-products?', '/fuel-offers/', '/tanks',
    '/dispensers', '/nozzles/', '/tank-connection', '/inventory/opening',
  ]) assert.ok(api.includes(route), `API client must call ${route}`);

  assert.match(controller, /@RequirePermission\('infrastructure\.read'\)\s+@Get\('branches\/:branchId\/configuration'\)/);
  assert.match(controller, /@RequirePermission\('fuel\.read'\)\s+@Get\('fuel-products'\)/);
  assert.match(controller, /@RequirePermission\('branch\.manage'\)\s+@Put\('branches\/:branchId\/fuel-offers/);
  assert.match(controller, /@RequirePermission\('infrastructure\.propose'\)\s+@Post\('branches\/:branchId\/tanks'\)/);
  assert.match(controller, /@RequirePermission\('infrastructure\.propose'\)\s+@Post\('branches\/:branchId\/dispensers'\)/);
  assert.match(controller, /@RequirePermission\('infrastructure\.propose'\)\s+@Put\('branches\/:branchId\/nozzles\/:nozzleId\/tank-connection'\)/);
  assert.match(inventoryController, /@RequirePermission\('branch\.manage'\)\s+@Post\('opening'\)/);

  assert.match(screen, /valuationQuality: 'unknown'/);
  assert.match(screen, /widget\.permissions\.contains\('infrastructure\.propose'\)/);
  assert.match(screen, /tankOptions\s*\.where\(\(t\)\s*=>\s*_str\(t\['fuelProductId'\]\)\s*==\s*productId\)/);
  assert.match(main, /InfrastructureSetupScreen\(\s*api:\s*controller\.api,\s*branchId:\s*controller\.branch!\.id,\s*permissions:\s*controller\.permissions,?\s*\)/);
  assert.match(api, /developer\.log\([\s\S]{0,80}'Network failure/);
  assert.match(api, /developer\.log\([\s\S]{0,80}'HTTP \$\{response\.statusCode/);
  assert.match(api, /developer\.log\([\s\S]{0,80}'Export HTTP/);
  assert.match(api, /'X-Request-ID': requestId/);
  assert.match(api, /correlationId: requestId/);
  assert.match(api, /String _safeRoute\(String path\)/);
  assert.doesNotMatch(api, /developer\.log\([^\n]*(?:_accessToken|request\.body|response\.body)/);
  for (const route of ['/staff/employees?', '/staff/shifts?', '/staff/shifts\'']) assert.ok(api.includes(route), `Staff API client must call ${route}`);
  assert.match(staffController, /@RequirePermission\('staff\.read'\) @Get\('shifts'\)/);
  assert.match(staffController, /@RequirePermission\('staff\.shifts\.plan'\) @Post\('shifts'\)/);
  assert.match(api, /'employeeCode': employeeCode.trim\(\)/);
  assert.match(staffScreen, /Turnos · próximos 7 días/);
  assert.match(main, /StaffShiftsScreen\([\s\S]{0,160}controller\.permissions/);
  assert.match(api, /Future<Map<String, dynamic>> createBranchDraft/);
  assert.match(api, /Future<Map<String, dynamic>> branchReadiness/);
  assert.match(api, /Future<Map<String, dynamic>> activateBranch/);
  assert.match(api, /Future<Map<String, dynamic>> createStaffEmployee/);
  assert.match(branchController, /@RequirePermission\('branch\.manage'\)\s+@Post\(\)/);
  assert.match(branchController, /@RequirePermission\('branch\.activate'\)\s+@Post\(':branchId\/activate'\)/);
  assert.match(branchService, /async create\(branch:string,p:AuthPrincipal,input:CreateEmployeeDto,correlation:string\)[\s\S]*?access\(branch,p,'staff\.manage',true\)/);
  assert.match(branchService, /async employees\([\s\S]*?access\(branch,p,'staff\.read',true\)/);
  assert.match(branchService, /async schedule\([\s\S]*?access\(branch,p,'staff\.shifts\.plan'\)/);
  assert.match(onboarding, /'Requisitos del servidor'/);
  assert.match(onboarding, /_readiness\['canActivate'\] != true/);
  assert.match(onboarding, /saveBranchStep\(\s*id,\s*expectedVersion:/);
  assert.match(main, /BranchOnboardingScreen\(\s*api:\s*controller\.api/);
  for (const route of ['/fuel-price-proposals', '/fuel-price-proposals/${Uri.encodeComponent(proposalId)}/approve', '/maintenance/assets', '/maintenance/orders?limit=100', '/maintenance/orders/${Uri.encodeComponent(orderId)}/transition']) {
    assert.ok(api.includes(route), `Flutter API client must call ${route}`);
  }
  assert.match(pricingController, /@RequirePermission\('price\.propose'\)\s+@Post\('branches\/:branchId\/fuel-price-proposals'\)/);
  assert.match(pricingController, /@RequirePermission\('price\.approve'\)\s+@Post\('fuel-price-proposals\/:proposalId\/approve'\)/);
  assert.match(pricesScreen, /Requiere otra persona para aprobar/);
  assert.match(pricesScreen, /price\.apply/);
  assert.match(maintenanceController, /@RequirePermission\('maintenance\.work'\) @Post\('orders\/:orderId\/tasks'\)/);
  assert.match(maintenanceService, /input\.nextStatus==='verified'\?'maintenance\.verify':'maintenance\.work'/);
  assert.match(maintenanceScreen, /Registrar tarea y completar/);
  assert.match(maintenanceScreen, /maintenance\.verify/);
  assert.match(main, /MaintenanceScreen\(\s*api:\s*controller\.api/);
});
