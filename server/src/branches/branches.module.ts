import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module.js';
import { BranchesController } from './branches.controller.js';
import { BranchesService } from './branches.service.js';

@Module({ imports: [AuditModule], controllers: [BranchesController], providers: [BranchesService], exports: [BranchesService] })
export class BranchesModule {}
