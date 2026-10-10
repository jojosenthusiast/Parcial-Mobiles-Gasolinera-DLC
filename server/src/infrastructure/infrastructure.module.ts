import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool } from 'pg';
import { databaseConnectionOptions } from '../../scripts/database-connection.mjs';
import { InfrastructureController } from './infrastructure.controller.js';
import { InfrastructureService } from './infrastructure.service.js';
import { AuditModule } from '../audit/audit.module.js';
import { InventoryModule } from '../inventory/inventory.module.js';
import { DEVICE_PG_POOL, DispenseDeviceService } from './dispense-device.service.js';

@Module({ imports: [AuditModule,InventoryModule], controllers: [InfrastructureController], providers: [InfrastructureService,DispenseDeviceService,{
  provide:DEVICE_PG_POOL,inject:[ConfigService],useFactory:(config:ConfigService)=>new Pool({
    ...databaseConnectionOptions({DATABASE_URL:config.getOrThrow<string>('DATABASE_URL'),
      DATABASE_SSL_MODE:config.get<string>('DATABASE_SSL_MODE'),DATABASE_SSL_CA_FILE:config.get<string>('DATABASE_SSL_CA_FILE'),NODE_ENV:config.get<string>('NODE_ENV')}),
    max:2,connectionTimeoutMillis:5_000,application_name:'dlc-device-operations',keepAlive:true,statement_timeout:10_000,
  }),
}], exports: [InfrastructureService] })
export class InfrastructureModule {}
