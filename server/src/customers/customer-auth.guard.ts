import { CanActivate, ExecutionContext, Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Request } from 'express';

export interface CustomerIdentity { authUserId: string; email: string; }
type CustomerRequest = Request & { customer?: CustomerIdentity };

@Injectable()
export class CustomerAuthGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<CustomerRequest>();
    const match = request.header('authorization')?.match(/^Bearer ([A-Za-z0-9._~-]{30,4096})$/);
    if (!match) throw new UnauthorizedException('Inicia sesión para continuar.');
    const baseUrl = this.config.get<string>('SUPABASE_URL')?.trim();
    const publishableKey = this.config.get<string>('SUPABASE_PUBLISHABLE_KEY')?.trim();
    if (!baseUrl || !publishableKey) throw new ServiceUnavailableException('La autenticación de Clientes no está configurada.');
    let endpoint: URL;
    try { endpoint = new URL('/auth/v1/user', baseUrl); } catch { throw new ServiceUnavailableException('La autenticación de Clientes no está configurada.'); }
    try {
      const response = await fetch(endpoint, {
        headers: { apikey: publishableKey, authorization: `Bearer ${match[1]}` },
        signal: AbortSignal.timeout(5_000),
      });
      if (response.status === 401 || response.status === 403) throw new UnauthorizedException('La sesión de Clientes venció o no es válida.');
      if (!response.ok) throw new ServiceUnavailableException('No se pudo validar la sesión de Clientes.');
      const user = await response.json() as { id?: unknown; email?: unknown; email_confirmed_at?: unknown };
      if (typeof user.id !== 'string' || !isUuid(user.id) || typeof user.email !== 'string' || !user.email_confirmed_at) {
        throw new UnauthorizedException('Confirma tu correo antes de continuar.');
      }
      request.customer = { authUserId: user.id, email: user.email.trim().normalize('NFKC').toLowerCase() };
      return true;
    } catch (error) {
      if (error instanceof UnauthorizedException || error instanceof ServiceUnavailableException) throw error;
      throw new ServiceUnavailableException('No se pudo validar la sesión de Clientes.');
    }
  }
}

export function customerIdentity(request: Request): CustomerIdentity {
  const identity = (request as CustomerRequest).customer;
  if (!identity) throw new UnauthorizedException('Inicia sesión para continuar.');
  return identity;
}

function isUuid(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
