import { BadRequestException, Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { FuelPriceProposalDto, MarketPriceReferenceDto, PriceDecisionDto } from './pricing.dto.js';
import { PricingService } from './pricing.service.js';

@Controller()
export class PricingController {
  constructor(private readonly pricing: PricingService) {}

  @RequirePermission('price.read')
  @Get('branches/:branchId/fuel-prices')
  prices(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Query('fuelProductId') productId: string | undefined,
    @Query('serviceMode') serviceMode: string | undefined, @Req() request: Request) {
    if (productId && !isUuid(productId)) throw new BadRequestException('fuelProductId debe ser UUID.');
    if (serviceMode && !['full_service','self_service'].includes(serviceMode)) throw new BadRequestException('serviceMode no es válido.');
    return this.pricing.prices(branchId,request.principal!,productId,serviceMode);
  }

  @RequirePermission('price.read')
  @Get('branches/:branchId/fuel-prices/:fuelProductId/history')
  history(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('fuelProductId', new ParseUUIDPipe()) productId: string, @Req() request: Request) {
    return this.pricing.priceHistory(branchId,request.principal!,productId);
  }

  @RequirePermission('price.read')
  @Get('branches/:branchId/fuel-price-proposals')
  proposals(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Query('status') status: string | undefined, @Req() request: Request) {
    if (status && !['pending_approval','approved','scheduled','rejected','cancelled'].includes(status)) throw new BadRequestException('status no es válido.');
    return this.pricing.proposals(branchId,request.principal!,status);
  }

  @RequirePermission('price.propose')
  @Post('branches/:branchId/fuel-price-proposals')
  propose(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Body() body: FuelPriceProposalDto, @Req() request: Request) {
    return this.pricing.createProposal(branchId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('price.approve')
  @Post('fuel-price-proposals/:proposalId/approve')
  approve(@Param('proposalId', new ParseUUIDPipe()) proposalId: string, @Body() body: PriceDecisionDto, @Req() request: Request) {
    return this.pricing.decide(proposalId,request.principal!,body,'approve',request.header('x-request-id')!);
  }

  @RequirePermission('price.approve')
  @Post('fuel-price-proposals/:proposalId/reject')
  reject(@Param('proposalId', new ParseUUIDPipe()) proposalId: string, @Body() body: PriceDecisionDto, @Req() request: Request) {
    return this.pricing.decide(proposalId,request.principal!,body,'reject',request.header('x-request-id')!);
  }

  @RequirePermission('price.apply')
  @Post('fuel-price-proposals/:proposalId/schedule')
  schedule(@Param('proposalId', new ParseUUIDPipe()) proposalId: string, @Body() body: PriceDecisionDto, @Req() request: Request) {
    return this.pricing.schedule(proposalId,request.principal!,body,request.header('x-request-id')!);
  }

  @RequirePermission('price.read')
  @Get('fuel-market-references')
  marketReferences(@Query('zone') zone: string | undefined, @Query('fuelProductId') productId: string | undefined,
    @Query('limit') limit: string | undefined, @Req() request: Request) {
    if (zone && !['occidental','central','oriental','other'].includes(zone)) throw new BadRequestException('zone no es válida.');
    if (productId && !isUuid(productId)) throw new BadRequestException('fuelProductId debe ser UUID.');
    const count = limit === undefined ? 30 : Number(limit);
    if (!Number.isInteger(count) || count < 1 || count > 100) throw new BadRequestException('limit debe estar entre 1 y 100.');
    return this.pricing.listMarketReferences(request.principal!,{limit:count,...(zone ? {zone} : {}),...(productId ? {productId} : {})});
  }

  @RequirePermission('price.propose')
  @Post('fuel-market-references')
  createMarketReference(@Body() body: MarketPriceReferenceDto, @Req() request: Request) {
    return this.pricing.createMarketReference(request.principal!,body,request.header('x-request-id')!);
  }
}

function isUuid(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
