import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { AllocatePrepaymentDto, CollectPrepaymentDto, ConfirmReleaseDto, RequestReleaseDto, ResolvePrepaymentDto } from './prepayments.dto.js';
import { RefundPaymentDto, RequestRefundDto } from './payments.dto.js';
import { PaymentsService } from './payments.service.js';
import { PrepaymentsService } from './prepayments.service.js';

@Controller('branches/:branchId')
export class PrepaymentsController {
  constructor(private readonly prepayments: PrepaymentsService, private readonly payments: PaymentsService) {}

  @RequirePermission('payment.read')
  @Get('prepayments')
  list(@Param('branchId', new ParseUUIDPipe()) branch: string, @Req() request: Request) {
    return this.prepayments.list(branch, request.principal!);
  }

  @RequirePermission('payment.collect')
  @Post('dispense-authorizations/:authorizationId/prepayments')
  collect(@Param('branchId', new ParseUUIDPipe()) branch: string, @Param('authorizationId', new ParseUUIDPipe()) authorizationId: string, @Body() body: CollectPrepaymentDto, @Req() request: Request) {
    return this.prepayments.collect(branch, authorizationId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('payment.collect')
  @Post('prepayments/:advanceId/allocate')
  allocate(@Param('branchId', new ParseUUIDPipe()) branch: string, @Param('advanceId', new ParseUUIDPipe()) advanceId: string, @Body() body: AllocatePrepaymentDto, @Req() request: Request) {
    return this.prepayments.allocate(branch, advanceId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('sale.refund.request')
  @Post('prepayments/:advanceId/refund-requests')
  requestRefund(@Param('branchId', new ParseUUIDPipe()) branch: string, @Param('advanceId', new ParseUUIDPipe()) advanceId: string, @Body() body: RequestRefundDto, @Req() request: Request) {
    return this.payments.requestAdvanceRefund(branch, advanceId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('payment.refund')
  @Post('prepayments/:advanceId/refunds')
  refund(@Param('branchId', new ParseUUIDPipe()) branch: string, @Param('advanceId', new ParseUUIDPipe()) advanceId: string, @Body() body: RefundPaymentDto, @Req() request: Request) {
    return this.payments.refundAdvance(branch, advanceId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('payment.resolve')
  @Post('prepayments/:advanceId/release-requests')
  requestRelease(@Param('branchId', new ParseUUIDPipe()) branch: string, @Param('advanceId', new ParseUUIDPipe()) advanceId: string, @Body() body: RequestReleaseDto, @Req() request: Request) {
    return this.prepayments.requestRelease(branch, advanceId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('payment.resolve')
  @Post('prepayments/:advanceId/release-confirmations')
  confirmRelease(@Param('branchId', new ParseUUIDPipe()) branch: string, @Param('advanceId', new ParseUUIDPipe()) advanceId: string, @Body() body: ConfirmReleaseDto, @Req() request: Request) {
    return this.prepayments.confirmRelease(branch, advanceId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('payment.resolve')
  @Post('prepayments/:advanceId/resolve')
  resolve(@Param('branchId', new ParseUUIDPipe()) branch: string, @Param('advanceId', new ParseUUIDPipe()) advanceId: string, @Body() body: ResolvePrepaymentDto, @Req() request: Request) {
    return this.prepayments.resolve(branch, advanceId, request.principal!, body, request.header('x-request-id')!);
  }
}
