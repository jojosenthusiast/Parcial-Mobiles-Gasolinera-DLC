import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { AuthService } from './auth.service.js';
import { PUBLIC_ROUTE } from './public.decorator.js';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly auth: AuthService, private readonly reflector: Reflector) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(PUBLIC_ROUTE, [context.getHandler(), context.getClass()]);
    if (isPublic) return true;
    const request = context.switchToHttp().getRequest<Request>();
    const authorization = request.header('authorization');
    const match = authorization?.match(/^Bearer ([A-Za-z0-9_-]{40,100})$/);
    if (!match) throw new UnauthorizedException('La sesión no es válida.');
    const principal = await this.auth.authenticate(match[1]!);
    if (!principal) throw new UnauthorizedException('La sesión venció o fue revocada.');
    request.principal = principal;
    return true;
  }
}
