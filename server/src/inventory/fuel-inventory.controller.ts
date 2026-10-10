import { BadRequestException, Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { FuelInventoryService } from './fuel-inventory.service.js';
import { FuelInventoryCommandDto, FuelInventoryOpeningDto } from './inventory.dto.js';

@Controller('branches/:branchId/tanks/:tankId/inventory')
export class FuelInventoryController {
  constructor(private readonly inventory: FuelInventoryService) {}

  @RequirePermission('inventory.read')
  @Get()
  balance(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('tankId', new ParseUUIDPipe()) tankId: string, @Req() request: Request) {
    return this.inventory.balance(branchId, tankId, request.principal!);
  }

  @RequirePermission('inventory.read')
  @Get('movements')
  history(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('tankId', new ParseUUIDPipe()) tankId: string,
    @Query('limit') limit: string | undefined, @Query('cursor') cursor: string | undefined, @Req() request: Request) {
    const parsed = limit === undefined ? 30 : Number(limit);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > 100) throw new BadRequestException('limit debe estar entre 1 y 100.');
    if (cursor && cursor.length > 300) throw new BadRequestException('cursor no es válido.');
    return this.inventory.history(branchId, tankId, request.principal!, parsed, cursor);
  }

  @RequirePermission('branch.manage')
  @Post('opening')
  open(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('tankId', new ParseUUIDPipe()) tankId: string, @Body() body: FuelInventoryOpeningDto, @Req() request: Request) {
    return this.inventory.open(branchId, tankId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('inventory.receive')
  @Post('receipts')
  receive(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('tankId', new ParseUUIDPipe()) tankId: string, @Body() body: FuelInventoryCommandDto, @Req() request: Request) {
    return this.inventory.receive(branchId, tankId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('sale.create')
  @Post('sales')
  sell(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('tankId', new ParseUUIDPipe()) tankId: string, @Body() body: FuelInventoryCommandDto, @Req() request: Request) {
    return this.inventory.sell(branchId, tankId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('inventory.adjust.request')
  @Post('losses')
  lose(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('tankId', new ParseUUIDPipe()) tankId: string, @Body() body: FuelInventoryCommandDto, @Req() request: Request) {
    return this.inventory.lose(branchId, tankId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('inventory.adjust.request')
  @Post('adjustments')
  adjust(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('tankId', new ParseUUIDPipe()) tankId: string, @Body() body: FuelInventoryCommandDto, @Req() request: Request) {
    return this.inventory.adjust(branchId, tankId, request.principal!, body, request.header('x-request-id')!);
  }
}
