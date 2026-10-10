import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { AcceptStoreReturnDto, ApproveStoreCountDto, CaptureStoreCountDto, ChangeLotConditionDto, ClassifyStoreLossDto, CloseStoreTransferDto, CreatePosSaleDto, DispatchStoreTransferDto, PublishPosOfferDto, ReceivePosLotDto, ReceiveStoreTransferDto, UpdateAssortmentDto, UpdateGlobalCatalogDto } from './pos.dto.js';
import { PosService } from './pos.service.js';
@Controller('branches/:branchId')
export class PosController {
 constructor(private readonly pos:PosService) {}
 @RequirePermission('pos.catalog.read') @Get('pos/catalog')
 catalog(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Query() query:{q?:string;kind?:string;category?:string;cursor?:string;limit?:string;includeInactive?:string},@Req() req:Request){
  const {limit,...filters}=query;
  return this.pos.catalog(branchId,req.principal!,{...filters,...(limit===undefined?{}:{limit:Number(limit)})});
 }
 @RequirePermission('pos.catalog.read') @Get('pos/catalog/categories')
 categories(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Req() req:Request){return this.pos.categories(branchId,req.principal!);}
 @RequirePermission('pos.catalog.read') @Get('pos/catalog/:productId')
 product(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('productId',new ParseUUIDPipe()) productId:string,@Req() req:Request){return this.pos.product(branchId,productId,req.principal!);}
 @RequirePermission('pos.catalog.global.manage') @Patch('pos/catalog/global/:catalogId')
 globalCatalog(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('catalogId',new ParseUUIDPipe()) catalogId:string,@Body() body:UpdateGlobalCatalogDto,@Req() req:Request){return this.pos.updateGlobalCatalog(branchId,catalogId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.catalog.manage') @Patch('pos/catalog/:productId/assortment')
 assortment(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('productId',new ParseUUIDPipe()) productId:string,@Body() body:UpdateAssortmentDto,@Req() req:Request){return this.pos.updateAssortment(branchId,productId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.catalog.read') @Get('pos/stock/alerts')
 stockAlerts(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Req() req:Request){return this.pos.stockAlerts(branchId,req.principal!);}
 @RequirePermission('pos.catalog.manage') @Post('pos/catalog/offers')
 publish(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Body() body:PublishPosOfferDto,@Req() req:Request){return this.pos.publish(branchId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.stock.receive') @Post('pos/stock/receipts')
 receive(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Body() body:ReceivePosLotDto,@Req() req:Request){return this.pos.receive(branchId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.catalog.read') @Get('pos/catalog/:productId/lots')
 lots(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('productId',new ParseUUIDPipe()) productId:string,@Query('cursor') cursor:string|undefined,@Query('limit') limit:string|undefined,@Req() req:Request){
  return this.pos.lots(branchId,productId,req.principal!,{...(cursor===undefined?{}:{cursor}),...(limit===undefined?{}:{limit:Number(limit)})});
 }
 @RequirePermission('pos.stock.quarantine') @Post('pos/stock/lots/:lotId/condition')
 condition(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('lotId',new ParseUUIDPipe()) lotId:string,@Body() body:ChangeLotConditionDto,@Req() req:Request){return this.pos.condition(branchId,lotId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.stock.transfer.send') @Post('pos/transfers')
 dispatch(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Body() body:DispatchStoreTransferDto,@Req() req:Request){return this.pos.dispatch(branchId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.stock.transfer.receive') @Post('pos/transfers/:transferId/receipts')
 transferReceipt(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('transferId',new ParseUUIDPipe()) transferId:string,@Body() body:ReceiveStoreTransferDto,@Req() req:Request){return this.pos.transferReceipt(branchId,transferId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.stock.transfer.close') @Post('pos/transfers/:transferId/close')
 transferClose(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('transferId',new ParseUUIDPipe()) transferId:string,@Body() body:CloseStoreTransferDto,@Req() req:Request){return this.pos.transferClose(branchId,transferId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.catalog.read') @Get('pos/transfers')
 transfers(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Query('cursor') cursor:string|undefined,@Query('limit') limit:string|undefined,@Req() req:Request){return this.pos.transfers(branchId,req.principal!,{...(cursor===undefined?{}:{cursor}),...(limit===undefined?{}:{limit:Number(limit)})});}
 @RequirePermission('pos.catalog.read') @Get('pos/transfers/:transferId')
 transfer(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('transferId',new ParseUUIDPipe()) transferId:string,@Req() req:Request){return this.pos.transfer(branchId,transferId,req.principal!);}
 @RequirePermission('pos.stock.count') @Post('pos/stock/counts')
 count(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Body() body:CaptureStoreCountDto,@Req() req:Request){return this.pos.count(branchId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.stock.adjust.approve') @Post('pos/stock/counts/:countId/approve')
 approveCount(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('countId',new ParseUUIDPipe()) countId:string,@Body() body:ApproveStoreCountDto,@Req() req:Request){return this.pos.approveCount(branchId,countId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.stock.loss.classify') @Post('pos/stock/counts/:countId/loss')
 classifyLoss(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('countId',new ParseUUIDPipe()) countId:string,@Body() body:ClassifyStoreLossDto,@Req() req:Request){return this.pos.classifyLoss(branchId,countId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.catalog.read') @Get('pos/stock/counts')
 counts(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Query('cursor') cursor:string|undefined,@Query('limit') limit:string|undefined,@Req() req:Request){return this.pos.counts(branchId,req.principal!,{...(cursor===undefined?{}:{cursor}),...(limit===undefined?{}:{limit:Number(limit)})});}
 @RequirePermission('pos.stock.return') @Post('pos/returns')
 acceptReturn(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Body() body:AcceptStoreReturnDto,@Req() req:Request){return this.pos.acceptReturn(branchId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.catalog.read') @Get('pos/returns')
 returns(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Query('cursor') cursor:string|undefined,@Query('limit') limit:string|undefined,@Req() req:Request){return this.pos.returns(branchId,req.principal!,{...(cursor===undefined?{}:{cursor}),...(limit===undefined?{}:{limit:Number(limit)})});}
 @RequirePermission('sale.create') @Post('sales/pos')
 create(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Body() body:CreatePosSaleDto,@Req() req:Request){return this.pos.createSale(branchId,req.principal!,body,req.header('x-request-id')!);}
}
