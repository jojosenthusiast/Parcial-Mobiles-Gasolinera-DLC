import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { AuthService } from '../auth/auth.service.js';
import { REQUIRED_PERMISSION } from './permission.decorator.js';

@Injectable()
export class PermissionGuard implements CanActivate {
  constructor(private readonly reflector: Reflector, private readonly auth: AuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const required = this.reflector.getAllAndOverride<string>(REQUIRED_PERMISSION, [context.getHandler(), context.getClass()]);
    if (!required) return true;
    const request = context.switchToHttp().getRequest<Request>();
    if (!request.principal) throw new ForbiddenException('Se requiere una sesión autenticada.');
    const rawBranch = request.params.branchId ?? request.query.branchId ?? (request.body as Record<string, unknown> | undefined)?.branchId;
    const branchId = typeof rawBranch === 'string' ? rawBranch : undefined;
    const capabilities = await this.auth.capabilities(request.principal, branchId);
    if (!capabilities.includes(required)) throw new ForbiddenException('No tienes permiso para esta acción en el ámbito solicitado.');
    return true;
  }
}
