import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller.js';
import { AuthGuard } from './auth.guard.js';
import { AuthService } from './auth.service.js';
import { UsersController } from './users.controller.js';
import { UserAdminService } from './user-admin.service.js';
import { AuditModule } from '../audit/audit.module.js';

@Module({ imports: [AuditModule], controllers: [AuthController, UsersController], providers: [AuthService, AuthGuard, UserAdminService], exports: [AuthService, AuthGuard, UserAdminService] })
export class AuthModule {}
