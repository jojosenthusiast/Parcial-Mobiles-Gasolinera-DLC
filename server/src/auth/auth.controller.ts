import { Body, Controller, Get, HttpCode, HttpStatus, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { AuthService } from './auth.service.js';
import { LoginDto, RefreshDto } from './auth.dto.js';
import { Public } from './public.decorator.js';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('login')
  @Public()
  @HttpCode(HttpStatus.OK)
  login(@Body() body: LoginDto, @Req() request: Request) {
    return this.auth.login(body.email, body.password, body.deviceLabel, request.ip, request.header('x-request-id')!);
  }

  @Post('refresh')
  @Public()
  @HttpCode(HttpStatus.OK)
  refresh(@Body() body: RefreshDto, @Req() request: Request) {
    return this.auth.refresh(body.refreshToken, request.header('x-request-id')!);
  }

  @Post('logout')
  async logout(@Req() request: Request) {
    await this.auth.logout(request.principal!, request.header('x-request-id')!);
    return { data: { revoked: true } };
  }

  @Get('me')
  async me(@Req() request: Request) {
    return { data: await this.auth.me(request.principal!) };
  }

  @Get('me/capabilities')
  async capabilities(@Req() request: Request) {
    const branchId = request.query.branchId;
    return { data: { permissions: await this.auth.capabilities(request.principal!, typeof branchId === 'string' ? branchId : undefined) } };
  }
}
