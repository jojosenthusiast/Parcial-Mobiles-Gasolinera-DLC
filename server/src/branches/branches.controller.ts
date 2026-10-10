import { BadRequestException, Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { BranchesService } from './branches.service.js';
import { ActivateBranchDto, CreateBranchDraftDto, SaveBranchOnboardingStepDto } from './branch-onboarding.dto.js';

@Controller('branches')
export class BranchesController {
  constructor(private readonly branches: BranchesService) {}

  @RequirePermission('branch.read')
  @Get()
  list(@Query('query') query: string | undefined, @Query('status') status: string | undefined, @Query('branchId') branchId: string | undefined,
    @Query('countryCode') countryCode: string | undefined, @Query('cursor') cursor: string | undefined, @Query('limit') limit: string | undefined, @Req() request: Request) {
    if (query && query.length > 100) throw new BadRequestException('query no puede superar 100 caracteres.');
    if (status && !['draft','configured','active','suspended','archived'].includes(status)) throw new BadRequestException('status no es válido.');
    if (branchId && !isUuid(branchId)) throw new BadRequestException('branchId debe ser UUID.');
    if (countryCode && !/^[A-Za-z]{2}$/.test(countryCode)) throw new BadRequestException('countryCode debe ser un código ISO 3166-1 alpha-2.');
    if (cursor && !isUuid(cursor)) throw new BadRequestException('cursor debe ser UUID.');
    const parsedLimit = limit === undefined ? 50 : Number(limit);
    if (!Number.isInteger(parsedLimit) || parsedLimit < 1 || parsedLimit > 100) throw new BadRequestException('limit debe estar entre 1 y 100.');
    return this.branches.list(request.principal!, { limit: parsedLimit, ...(query !== undefined ? { query } : {}), ...(status !== undefined ? { status } : {}), ...(branchId ? { branchId } : {}), ...(countryCode ? { countryCode: countryCode.toUpperCase() } : {}), ...(cursor ? { cursor } : {}) });
  }

  @RequirePermission('branch.manage')
  @Post()
  create(@Body() body: CreateBranchDraftDto, @Req() request: Request) {
    return this.branches.createDraft(request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('branch.read')
  @Get(':branchId')
  detail(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Req() request: Request) {
    return this.branches.detail(branchId, request.principal!);
  }

  @RequirePermission('branch.manage')
  @Patch(':branchId/onboarding')
  saveStep(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Body() body: SaveBranchOnboardingStepDto, @Req() request: Request) {
    return this.branches.saveStep(branchId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('branch.read')
  @Get(':branchId/readiness')
  readiness(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Req() request: Request) {
    return this.branches.readiness(branchId, request.principal!);
  }

  @RequirePermission('branch.activate')
  @Post(':branchId/activate')
  activate(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Body() body: ActivateBranchDto, @Req() request: Request) {
    return this.branches.activate(branchId, request.principal!, body, request.header('x-request-id')!);
  }
}

function isUuid(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
