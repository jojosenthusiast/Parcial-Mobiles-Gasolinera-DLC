import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module.js';
import { FuelInventoryController } from './fuel-inventory.controller.js';
import { FuelInventoryService } from './fuel-inventory.service.js';

@Module({ imports: [AuditModule], controllers: [FuelInventoryController], providers: [FuelInventoryService], exports: [FuelInventoryService] })
export class InventoryModule {}
