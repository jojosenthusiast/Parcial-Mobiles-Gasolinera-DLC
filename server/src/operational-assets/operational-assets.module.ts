import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuditModule } from '../audit/audit.module.js';
import { OperationalAssetsController } from './operational-assets.controller.js';
import { OperationalAssetsService } from './operational-assets.service.js';

@Module({imports:[AuthModule,AuditModule],controllers:[OperationalAssetsController],providers:[OperationalAssetsService]})
export class OperationalAssetsModule {}
