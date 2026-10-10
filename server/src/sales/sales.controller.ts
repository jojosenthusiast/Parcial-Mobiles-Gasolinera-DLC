import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req, Res } from '@nestjs/common';
import type { Response } from 'express';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { CreateCombinedReceiptDto, CreateFuelSaleDto } from './sales.dto.js';
import { SalesService } from './sales.service.js';
@Controller('branches/:branchId')
export class SalesController {
 constructor(private readonly sales:SalesService) {}
 @RequirePermission('sale.create') @Post('sales/from-dispatch')
 create(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Body() body:CreateFuelSaleDto,@Req() req:Request) {
  return this.sales.createFuelSale(branchId,req.principal!,body,req.header('x-request-id')!);
 }
 @RequirePermission('sale.create') @Post('sales/combined-receipts')
 createCombinedReceipt(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Body() body:CreateCombinedReceiptDto,@Req() req:Request) {
  return this.sales.createCombinedReceipt(branchId,req.principal!,body,req.header('x-request-id')!);
 }
 @RequirePermission('sale.read') @Get('sales/combined-receipts/:receiptId')
 combinedReceipt(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('receiptId',new ParseUUIDPipe()) receiptId:string,@Req() req:Request) {
  return this.sales.combinedReceipt(branchId,receiptId,req.principal!);
 }
 @RequirePermission('sale.read') @Get('sales/:saleId/combined-receipt')
 combinedReceiptForSale(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('saleId',new ParseUUIDPipe()) saleId:string,@Req() req:Request) {
  return this.sales.combinedReceiptForSale(branchId,saleId,req.principal!);
 }
 @RequirePermission('sale.read') @Get('sales')
 list(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Query('q') q:string|undefined,@Query('cursor') cursor:string|undefined,
  @Query('limit') limit:string|undefined,@Req() req:Request) {
  return this.sales.list(branchId,req.principal!,{...(q===undefined?{}:{q}),...(cursor===undefined?{}:{cursor}),...(limit===undefined?{}:{limit:Number(limit)})});
 }
 @RequirePermission('sale.read') @Get('sales/:saleId/receipt.pdf')
 async receiptPdf(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('saleId',new ParseUUIDPipe()) saleId:string,@Req() req:Request,@Res() res:Response) {
  const pdf=await this.sales.receiptPdf(branchId,saleId,req.principal!);
  res.setHeader('Content-Type','application/pdf');res.setHeader('Content-Disposition','attachment; filename="comprobante-'+saleId+'.pdf"');res.setHeader('Cache-Control','private, no-store');res.send(pdf);
 }
 @RequirePermission('sale.read') @Get('sales/:saleId')
 detail(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('saleId',new ParseUUIDPipe()) saleId:string,@Req() req:Request) {
  return this.sales.detail(branchId,saleId,req.principal!);
 }
 @RequirePermission('sale.read') @Get('dispense-authorizations/:authorizationId/sale')
 forDispatch(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('authorizationId',new ParseUUIDPipe()) authorizationId:string,@Req() req:Request) {
  return this.sales.forDispatch(branchId,authorizationId,req.principal!);
 }
}
