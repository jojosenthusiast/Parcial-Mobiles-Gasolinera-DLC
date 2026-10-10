import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuditModule } from '../audit/audit.module.js';
import { InventoryModule } from '../inventory/inventory.module.js';
import { AnomaliesController, IncidentsController } from './incidents.controller.js';
import { IncidentsService } from './incidents.service.js';
@Module({imports:[AuthModule,AuditModule,InventoryModule],controllers:[IncidentsController,AnomaliesController],providers:[IncidentsService]})
export class IncidentsModule {}
