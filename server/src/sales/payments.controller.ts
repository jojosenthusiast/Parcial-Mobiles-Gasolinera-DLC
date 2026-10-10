import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { CashMovementDto, CloseCashDto, CollectPaymentDto, CreateRegisterDto, OpenCashDto, RefundPaymentDto, RequestRefundDto, ResolvePaymentDto } from './payments.dto.js';
import { PaymentsService } from './payments.service.js';
@Controller('branches/:branchId')
export class PaymentsController {
 constructor(private readonly payments:PaymentsService) {}
 @RequirePermission('cash.read') @Get('cash/registers')
 registers(@Param('branchId',new ParseUUIDPipe()) b:string,@Req() r:Request){return this.payments.registers(b,r.principal!);}
 @RequirePermission('cash.register.manage') @Post('cash/registers')
 register(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:CreateRegisterDto,@Req() r:Request){return this.payments.createRegister(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('cash.open') @Post('cash/sessions')
 open(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:OpenCashDto,@Req() r:Request){return this.payments.open(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('cash.read') @Get('cash/sessions/:sessionId')
 session(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('sessionId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.payments.session(b,id,r.principal!);}
 @RequirePermission('cash.read') @Get('cash/sessions/:sessionId/review')
 review(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('sessionId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.payments.cashReview(b,id,r.principal!);}
 @RequirePermission('cash.read') @Get('cash/reviews')
 reviews(@Param('branchId',new ParseUUIDPipe()) b:string,@Query('status') status:string|undefined,@Req() r:Request){return this.payments.cashReviews(b,r.principal!,status);}
 @RequirePermission('cash.read') @Get('cash/sessions/:sessionId/movements')
 movements(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('sessionId',new ParseUUIDPipe()) id:string,
  @Query('kind') kind:string|undefined,@Query('limit') limit:string|undefined,@Query('beforeAt') beforeAt:string|undefined,
  @Query('beforeId') beforeId:string|undefined,@Req() r:Request){return this.payments.cashMovements(b,id,r.principal!,{...(kind===undefined?{}:{kind}),...(limit===undefined?{}:{limit}),...(beforeAt===undefined?{}:{beforeAt}),...(beforeId===undefined?{}:{beforeId})});}
 @RequirePermission('cash.move') @Post('cash/sessions/:sessionId/movements')
 move(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('sessionId',new ParseUUIDPipe()) id:string,@Body() body:CashMovementDto,@Req() r:Request){return this.payments.move(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('cash.close') @Post('cash/sessions/:sessionId/close')
 close(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('sessionId',new ParseUUIDPipe()) id:string,@Body() body:CloseCashDto,@Req() r:Request){return this.payments.close(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('payment.collect') @Post('payments')
 collect(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:CollectPaymentDto,@Req() r:Request){return this.payments.collect(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('payment.resolve') @Post('payments/:attemptId/resolve')
 resolve(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('attemptId',new ParseUUIDPipe()) id:string,@Body() body:ResolvePaymentDto,@Req() r:Request){return this.payments.resolve(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('sale.refund.request') @Post('payment-events/:paymentEventId/refund-requests')
 requestRefund(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('paymentEventId',new ParseUUIDPipe()) id:string,@Body() body:RequestRefundDto,@Req() r:Request){return this.payments.requestRefund(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('payment.refund') @Post('payment-events/:paymentEventId/refunds')
 refund(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('paymentEventId',new ParseUUIDPipe()) id:string,@Body() body:RefundPaymentDto,@Req() r:Request){return this.payments.refund(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('payment.read') @Get('sales/:saleId/refund-requests')
 refundRequests(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('saleId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.payments.refundRequests(b,id,r.principal!);}
 @RequirePermission('payment.read') @Get('sales/:saleId/payments')
 paymentsForSale(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('saleId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.payments.payments(b,id,r.principal!);}
}
