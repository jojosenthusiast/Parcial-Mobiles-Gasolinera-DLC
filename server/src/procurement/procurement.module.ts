import { ContaminationService } from './contamination.service.js';
import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module.js';
import { ProcurementController } from './procurement.controller.js';
import { ProcurementService } from './procurement.service.js';
import { InventoryModule } from '../inventory/inventory.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { PlanningController } from './planning.controller.js';
import { PlanningService } from './planning.service.js';

@Module({ imports: [AuditModule,InventoryModule,AuthModule], controllers: [ProcurementController,PlanningController], providers: [ContaminationService,ProcurementService,PlanningService] })
export class ProcurementModule {}
