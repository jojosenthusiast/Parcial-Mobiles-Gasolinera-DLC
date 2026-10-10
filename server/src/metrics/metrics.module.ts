import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuditModule } from '../audit/audit.module.js';
import { MetricsController } from './metrics.controller.js';
import { MetricsService } from './metrics.service.js';
@Module({imports:[AuthModule,AuditModule],controllers:[MetricsController],providers:[MetricsService]})
export class MetricsModule {}
