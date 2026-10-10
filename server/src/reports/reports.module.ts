import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuditModule } from '../audit/audit.module.js';
import { JobsModule } from '../jobs/jobs.module.js';
import { ReportsController } from './reports.controller.js';
import { ReportsService } from './reports.service.js';
import { ReportsWorker } from './reports.worker.js';
@Module({imports:[AuthModule,AuditModule,JobsModule],controllers:[ReportsController],providers:[ReportsService,ReportsWorker],exports:[ReportsWorker]})
export class ReportsModule {}
