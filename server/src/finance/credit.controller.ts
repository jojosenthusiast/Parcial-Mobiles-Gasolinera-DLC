import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { AddCommercialBuyerDto, ChangeCommercialBuyerDto, ChargeCommercialSaleDto, CommercialCustomerEventDto, CreateCommercialCustomerDto, ReceiveCommercialCreditDto, VerifyCommercialBankDto } from './credit.dto.js';
import { CreditService } from './credit.service.js';
@Controller('branches/:branchId/finance/credit')
export class CreditController {
 constructor(private readonly credit:CreditService){}
 @RequirePermission('credit.customer.manage') @Post('customers')
 create(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() x:CreateCommercialCustomerDto,@Req() r:Request){return this.credit.create(b,r.principal!,x,r.header('x-request-id')!);}
 @RequirePermission('credit.statement.read') @Get('customers')
 customers(@Param('branchId',new ParseUUIDPipe()) b:string,@Query('q') q:string|undefined,@Req() r:Request){return this.credit.customers(b,r.principal!,q);}
 @RequirePermission('credit.customer.manage') @Post('customers/:customerId/events')
 event(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('customerId',new ParseUUIDPipe()) id:string,@Body() x:CommercialCustomerEventDto,@Req() r:Request){return this.credit.event(b,id,r.principal!,x,r.header('x-request-id')!);}
 @RequirePermission('credit.customer.manage') @Post('customers/:customerId/buyers')
 buyer(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('customerId',new ParseUUIDPipe()) id:string,@Body() x:AddCommercialBuyerDto,@Req() r:Request){return this.credit.buyer(b,id,r.principal!,x,r.header('x-request-id')!);}
 @RequirePermission('credit.customer.manage') @Post('customers/:customerId/buyers/:buyerId/access')
 buyerAccess(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('customerId',new ParseUUIDPipe()) id:string,@Param('buyerId',new ParseUUIDPipe()) buyer:string,@Body() x:ChangeCommercialBuyerDto,@Req() r:Request){return this.credit.buyerAccess(b,id,buyer,r.principal!,x,r.header('x-request-id')!);}
 @RequirePermission('credit.statement.read') @Get('customers/:customerId/statement')
 statement(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('customerId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.credit.statement(b,id,r.principal!);}
 @RequirePermission('credit.sale.charge') @Post('sales/:saleId/charge')
 charge(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('saleId',new ParseUUIDPipe()) id:string,@Body() x:ChargeCommercialSaleDto,@Req() r:Request){return this.credit.charge(b,id,r.principal!,x,r.header('x-request-id')!);}
 @RequirePermission('credit.receipt.record') @Post('charges/:chargeId/receipts')
 receipt(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('chargeId',new ParseUUIDPipe()) id:string,@Body() x:ReceiveCommercialCreditDto,@Req() r:Request){return this.credit.receipt(b,id,r.principal!,x,r.header('x-request-id')!);}
 @RequirePermission('credit.bank.verify') @Post('receipts/:receiptId/verify')
 verify(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('receiptId',new ParseUUIDPipe()) id:string,@Body() x:VerifyCommercialBankDto,@Req() r:Request){return this.credit.verify(b,id,r.principal!,x,r.header('x-request-id')!);}
}
