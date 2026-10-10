import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req, BadRequestException } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { UserAdminService } from './user-admin.service.js';
import { ActivateAccountDto, InviteUserDto, ReassignRoleDto, UserStatusDto } from './user-admin.dto.js';
import { Public } from './public.decorator.js';

@Controller()
export class UsersController {
  constructor(private readonly users: UserAdminService) {}

  @RequirePermission('user.manage')
  @Get('users')
  list(@Query('branchId') branchId: string | undefined, @Query('query') query: string | undefined,
    @Query('status') status: string | undefined, @Query('cursor') cursor: string | undefined, @Query('limit') limit: string | undefined, @Req() request: Request) {
    if (branchId && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(branchId)) throw new BadRequestException('branchId debe ser UUID.');
    if (query && query.length > 100) throw new BadRequestException('query no puede superar 100 caracteres.');
    if (status && !['invited','active','suspended','locked'].includes(status)) throw new BadRequestException('status no es válido.');
    if (cursor && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(cursor)) throw new BadRequestException('cursor debe ser UUID.');
    const parsedLimit=limit===undefined?100:Number(limit);if(!Number.isInteger(parsedLimit)||parsedLimit<1||parsedLimit>200)throw new BadRequestException('limit debe estar entre 1 y 200.');
    return this.users.list(request.principal!, { ...(branchId ? { branchId } : {}), ...(query !== undefined ? { query } : {}), ...(status !== undefined ? { status } : {}), ...(cursor ? { cursor } : {}), limit:parsedLimit });
  }

  @RequirePermission('user.manage')
  @Get('roles')
  roles(@Req() request: Request) {
    return this.users.listRoles(request.principal!);
  }

  @RequirePermission('user.manage')
  @Post('users/invitations')
  async invite(@Body() body: InviteUserDto, @Req() request: Request) {
    const principal = request.principal!;
    const invited = await this.users.invite({
      actor: principal, email: body.email, displayName: body.displayName,
      roleId: body.roleId,
      ...(body.branchId ? { branchId: body.branchId } : {}),
      ...(body.employeeId ? { employeeId: body.employeeId } : {}),
      correlationId: request.header('x-request-id')!,
    });
    return { data: invited };
  }

  @RequirePermission('user.manage')
  @Post('users/:userId/password-reset')
  async reset(@Param('userId', new ParseUUIDPipe()) userId: string, @Req() request: Request) {
    const principal = request.principal!;
    const reset = await this.users.issuePasswordReset(userId, principal, request.header('x-request-id')!);
    return { data: reset };
  }

  @RequirePermission('user.manage')
  @Post('users/:userId/status')
  async setStatus(@Param('userId', new ParseUUIDPipe()) userId: string, @Body() body: UserStatusDto, @Req() request: Request) {
    const principal = request.principal!;
    await this.users.setStatus(userId, principal, body.status, request.header('x-request-id')!);
    return { data: { userId, status: body.status } };
  }

  @RequirePermission('user.manage')
  @Post('users/:userId/assignments')
  async reassign(@Param('userId', new ParseUUIDPipe()) userId: string, @Body() body: ReassignRoleDto, @Req() request: Request) {
    const principal = request.principal!;
    await this.users.reassignRole({ actor: principal, userId, roleId: body.roleId, branchId: body.branchId ?? null, correlationId: request.header('x-request-id')! });
    return { data: { userId, roleId: body.roleId, branchId: body.branchId ?? null } };
  }

  @Post('auth/activate')
  @Public()
  async activate(@Body() body: ActivateAccountDto, @Req() request: Request) {
    await this.users.activateOrReset(body.token, body.password, 'invite', request.header('x-request-id')!);
    return { data: { activated: true } };
  }

  @Post('auth/password-reset/complete')
  @Public()
  async completeReset(@Body() body: ActivateAccountDto, @Req() request: Request) {
    await this.users.activateOrReset(body.token, body.password, 'password_reset', request.header('x-request-id')!);
    return { data: { passwordChanged: true } };
  }
}
