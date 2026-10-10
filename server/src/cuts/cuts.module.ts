import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuditModule } from '../audit/audit.module.js';
import { CutsController } from './cuts.controller.js';
import { CutsService } from './cuts.service.js';

@Module({imports:[AuthModule,AuditModule],controllers:[CutsController],providers:[CutsService]})
export class CutsModule {}
