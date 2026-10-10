import { SalesModule } from './sales/sales.module.js';
import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { DatabaseModule } from './database/database.module.js';
import { HealthModule } from './health/health.module.js';
import { IdempotencyModule } from './idempotency/idempotency.module.js';
import { JobsModule } from './jobs/jobs.module.js';
import { AuthModule } from './auth/auth.module.js';
import { AuthorizationModule } from './authorization/authorization.module.js';
import { AuditModule } from './audit/audit.module.js';
import { validateEnvironment } from './core/environment.js';
import { AuthGuard } from './auth/auth.guard.js';
import { PermissionGuard } from './authorization/permission.guard.js';
import { InfrastructureModule } from './infrastructure/infrastructure.module.js';
import { ImportsModule } from './imports/imports.module.js';
import { BranchesModule } from './branches/branches.module.js';
import { InventoryModule } from './inventory/inventory.module.js';
import { PricingModule } from './pricing/pricing.module.js';
import { ProcurementModule } from './procurement/procurement.module.js';
import { CutsModule } from './cuts/cuts.module.js';
import { IncidentsModule } from './incidents/incidents.module.js';
import { MaintenanceModule } from './maintenance/maintenance.module.js';
import { StaffModule } from './staff/staff.module.js';
import { ExpensesModule } from './finance/expenses.module.js';
import { MetricsModule } from './metrics/metrics.module.js';
import { ReportsModule } from './reports/reports.module.js';
import { CustomersModule } from './customers/customers.module.js';
import { PromotionsModule } from './promotions/promotions.module.js';
import { OperationalAssetsModule } from './operational-assets/operational-assets.module.js';

@Module({
  imports: [SalesModule, CutsModule, IncidentsModule, MaintenanceModule, StaffModule, ExpensesModule, MetricsModule, ReportsModule, CustomersModule, PromotionsModule, OperationalAssetsModule, ConfigModule.forRoot({ isGlobal: true, validate: validateEnvironment }), DatabaseModule, IdempotencyModule, JobsModule, AuthModule, AuthorizationModule, AuditModule, InfrastructureModule, ImportsModule, BranchesModule, InventoryModule, PricingModule, ProcurementModule, HealthModule],
  providers: [
    { provide: APP_GUARD, useExisting: AuthGuard },
    { provide: APP_GUARD, useExisting: PermissionGuard },
  ],
})
export class AppModule {}
