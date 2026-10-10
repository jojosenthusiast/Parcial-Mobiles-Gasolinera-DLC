import { ContaminationDto, ContaminationApprovalDto, ContaminationDisposalDto } from './contamination.dto.js';
import { ContaminationService } from './contamination.service.js';
import { BadRequestException, Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { PurchaseOrderCreateDto, PurchaseOrderDecisionDto, PurchaseReceiptDto, SupplierCreateDto, SupplierInvoiceCreateDto, SupplierPaymentDto } from './procurement.dto.js';
import { ProcurementService } from './procurement.service.js';

@Controller()
export class ProcurementController {
  constructor(private readonly procurement: ProcurementService, private readonly contamination:ContaminationService) {}

  @RequirePermission('loss.approve')
  @Post('branches/:branchId/contaminations/:id/incoming-loss-approval')
  approveContamination(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('id',new ParseUUIDPipe()) id:string,@Body() body:ContaminationApprovalDto,@Req() r:Request){return this.contamination.resolve(b,id,r.principal!,body,r.header('x-request-id')!,false);}
  @RequirePermission('incident.resolve')
  @Post('branches/:branchId/contaminations/:id/disposal-verification')
  disposeContamination(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('id',new ParseUUIDPipe()) id:string,@Body() body:ContaminationDisposalDto,@Req() r:Request){return this.contamination.resolve(b,id,r.principal!,body,r.header('x-request-id')!,true);}

  @RequirePermission('purchase.receive')
  @Get('branches/:branchId/tanks/:tankId/contamination-preview')
  preview(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('tankId',new ParseUUIDPipe()) t:string,@Req() r:Request){return this.contamination.tank(b,t,r.principal!);}
  @RequirePermission('purchase.read')
  @Get('branches/:branchId/purchase-orders/:orderId/contaminations')
  contaminationList(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('orderId',new ParseUUIDPipe()) o:string,@Req() r:Request){return this.contamination.list(b,o,r.principal!);}
  @RequirePermission('purchase.receive')
  @Post('branches/:branchId/purchase-orders/:orderId/contaminations')
  contaminated(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('orderId',new ParseUUIDPipe()) o:string,@Body() body:ContaminationDto,@Req() r:Request){return this.contamination.report(b,o,r.principal!,body,r.header('x-request-id')!);}

  @RequirePermission('purchase.read')
  @Get('suppliers')
  suppliers(@Query('q') q: string | undefined, @Query('limit') limit: string | undefined, @Req() request: Request) {
    if (q && q.length > 120) throw new BadRequestException('q no puede superar 120 caracteres.');
    const parsed = limit === undefined ? 50 : Number(limit);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > 100) throw new BadRequestException('limit debe estar entre 1 y 100.');
    return this.procurement.suppliers(request.principal!, q, parsed);
  }

  @RequirePermission('purchase.create')
  @Post('suppliers')
  createSupplier(@Body() body: SupplierCreateDto, @Req() request: Request) {
    return this.procurement.createSupplier(request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('purchase.read')
  @Get('branches/:branchId/purchase-orders')
  orders(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Query('status') status: string | undefined,
    @Query('q') q: string | undefined, @Query('cursor') cursor: string | undefined, @Query('limit') limit: string | undefined, @Req() request: Request) {
    const states = ['draft','pending_approval','approved','ordered','partially_received','received','rejected','cancelled'];
    if (status && !states.includes(status)) throw new BadRequestException('status no es válido.');
    if (q && q.length > 100) throw new BadRequestException('q no puede superar 100 caracteres.');
    const parsed = limit === undefined ? 50 : Number(limit);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > 100) throw new BadRequestException('limit debe estar entre 1 y 100.');
    if (cursor && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(cursor)) throw new BadRequestException('cursor no es válido.');
    return this.procurement.listPurchaseOrders(branchId, request.principal!, status, cursor, parsed, q);
  }

  @RequirePermission('purchase.read')
  @Get('branches/:branchId/purchase-orders/:orderId')
  order(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('orderId', new ParseUUIDPipe()) orderId: string, @Req() request: Request) {
    return this.procurement.purchaseOrder(orderId, branchId, request.principal!);
  }

  @RequirePermission('purchase.create')
  @Post('branches/:branchId/purchase-orders')
  createOrder(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Body() body: PurchaseOrderCreateDto, @Req() request: Request) {
    return this.procurement.createPurchaseOrder(branchId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('purchase.create')
  @Post('branches/:branchId/purchase-orders/:orderId/submit')
  submit(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('orderId', new ParseUUIDPipe()) orderId: string,
    @Body() body: PurchaseOrderDecisionDto, @Req() request: Request) {
    return this.procurement.submit(branchId, orderId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('purchase.approve')
  @Post('branches/:branchId/purchase-orders/:orderId/approve')
  approve(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('orderId', new ParseUUIDPipe()) orderId: string,
    @Body() body: PurchaseOrderDecisionDto, @Req() request: Request) {
    return this.procurement.decide(branchId, orderId, request.principal!, body, request.header('x-request-id')!, 'approve');
  }

  @RequirePermission('purchase.approve')
  @Post('branches/:branchId/purchase-orders/:orderId/reject')
  reject(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('orderId', new ParseUUIDPipe()) orderId: string,
    @Body() body: PurchaseOrderDecisionDto, @Req() request: Request) {
    return this.procurement.decide(branchId, orderId, request.principal!, body, request.header('x-request-id')!, 'reject');
  }

  @RequirePermission('purchase.create')
  @Post('branches/:branchId/purchase-orders/:orderId/mark-ordered')
  markOrdered(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('orderId', new ParseUUIDPipe()) orderId: string,
    @Body() body: PurchaseOrderDecisionDto, @Req() request: Request) {
    return this.procurement.markOrdered(branchId, orderId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('purchase.receive')
  @Post('branches/:branchId/purchase-orders/:orderId/receipts')
  receive(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('orderId', new ParseUUIDPipe()) orderId: string,
    @Body() body: PurchaseReceiptDto, @Req() request: Request) {
    return this.procurement.receive(branchId, orderId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('supplier.invoice.manage')
  @Get('branches/:branchId/purchase-orders/:orderId/invoices')
  invoices(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('orderId', new ParseUUIDPipe()) orderId: string, @Req() request: Request) {
    return this.procurement.invoices(branchId, orderId, request.principal!);
  }

  @RequirePermission('supplier.invoice.manage')
  @Post('branches/:branchId/purchase-orders/:orderId/invoices')
  invoice(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('orderId', new ParseUUIDPipe()) orderId: string,
    @Body() body: SupplierInvoiceCreateDto, @Req() request: Request) {
    return this.procurement.createInvoice(branchId, orderId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('supplier.payment.record')
  @Post('branches/:branchId/supplier-invoices/:invoiceId/payments')
  payInvoice(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('invoiceId', new ParseUUIDPipe()) invoiceId: string,
    @Body() body: SupplierPaymentDto, @Req() request: Request) {
    return this.procurement.payInvoice(branchId, invoiceId, request.principal!, body, request.header('x-request-id')!);
  }

  @RequirePermission('purchase.create')
  @Post('branches/:branchId/purchase-orders/:orderId/cancel')
  cancel(@Param('branchId', new ParseUUIDPipe()) branchId: string, @Param('orderId', new ParseUUIDPipe()) orderId: string,
    @Body() body: PurchaseOrderDecisionDto, @Req() request: Request) {
    return this.procurement.cancel(branchId, orderId, request.principal!, body, request.header('x-request-id')!);
  }
}
