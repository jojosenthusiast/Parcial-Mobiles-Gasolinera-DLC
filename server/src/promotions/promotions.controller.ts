import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { Public } from '../auth/public.decorator.js';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { CashbackPartnerStatusDto, CreateCashbackPartnerDto, CreatePromotionDto, PausePromotionDto, PromotionCommandDto, PromotionDecisionDto, UploadPromotionImageDto } from './promotion.dto.js';
import { PromotionsService } from './promotions.service.js';

@Controller('promotions')
export class PromotionsController {
  constructor(private readonly promotions: PromotionsService) {}

  @RequirePermission('promotion.read')
  @Get()
  list(@Query('branchId', new ParseUUIDPipe({ optional: true })) branchId: string | undefined, @Req() request: Request) {
    return this.promotions.list(request.principal!, branchId);
  }

  @RequirePermission('promotion.read')
  @Post('preview')
  preview(@Body() body: CreatePromotionDto, @Req() request: Request) { return this.promotions.preview(body, request.principal!); }

  @RequirePermission('promotion.read')
  @Post('images')
  uploadImage(@Body() body: UploadPromotionImageDto, @Req() request: Request) {
    return this.promotions.uploadImage(request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('promotion.read')
  @Get('cashback-partners')
  cashbackPartners(@Req() request: Request) { return this.promotions.cashbackPartners(request.principal!); }

  @RequirePermission('promotion.read')
  @Post('cashback-partners')
  createCashbackPartner(@Body() body: CreateCashbackPartnerDto, @Req() request: Request) {
    return this.promotions.createCashbackPartner(request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('promotion.read')
  @Post('cashback-partners/:code/status')
  cashbackPartnerStatus(@Param('code') code: string, @Body() body: CashbackPartnerStatusDto, @Req() request: Request) {
    return this.promotions.cashbackPartnerStatus(code, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('promotion.read')
  @Post()
  create(@Body() body: CreatePromotionDto, @Req() request: Request) {
    return this.promotions.create(request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('promotion.read')
  @Post(':promotionId/versions')
  createVersion(@Param('promotionId', new ParseUUIDPipe()) id: string, @Body() body: CreatePromotionDto, @Req() request: Request) {
    return this.promotions.createVersion(id, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('promotion.read')
  @Post(':promotionId/submit')
  submit(@Param('promotionId', new ParseUUIDPipe()) id: string, @Body() body: PromotionCommandDto, @Req() request: Request) {
    return this.promotions.submit(id, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('promotion.read')
  @Post(':promotionId/decision')
  decide(@Param('promotionId', new ParseUUIDPipe()) id: string, @Body() body: PromotionDecisionDto, @Req() request: Request) {
    return this.promotions.decide(id, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('promotion.read')
  @Post(':promotionId/pause')
  pause(@Param('promotionId', new ParseUUIDPipe()) id: string, @Body() body: PausePromotionDto, @Req() request: Request) {
    return this.promotions.pause(id, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('promotion.read')
  @Post(':promotionId/resume')
  resume(@Param('promotionId', new ParseUUIDPipe()) id: string, @Body() body: PromotionCommandDto, @Req() request: Request) {
    return this.promotions.resume(id, request.principal!, body, request.header('x-request-id')!);
  }
}

@Public()
@Controller('customer/promotions')
export class CustomerPromotionsController {
  constructor(private readonly promotions: PromotionsService) {}

  @Get()
  feed(@Query('branchId', new ParseUUIDPipe({ optional: true })) branchId?: string) {
    return this.promotions.publicFeed(branchId);
  }
}
