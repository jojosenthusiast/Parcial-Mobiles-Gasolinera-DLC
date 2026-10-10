import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { PermissionGuard } from './permission.guard.js';
import { ApprovalService } from './approval.service.js';
import { ApprovalController } from './approval.controller.js';
import { AuditModule } from '../audit/audit.module.js';

@Module({ imports: [AuthModule, AuditModule], controllers: [ApprovalController], providers: [PermissionGuard, ApprovalService], exports: [PermissionGuard, ApprovalService] })
export class AuthorizationModule {}
