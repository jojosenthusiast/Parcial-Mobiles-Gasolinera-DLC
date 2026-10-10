import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { AddServiceMaterialDto, ConfigureServiceDto, FulfillServiceDto } from './services.dto.js';
import { ServicesService } from './services.service.js';
@Controller('branches/:branchId/pos/services')
export class ServicesController {
 constructor(private readonly services:ServicesService){}
 @RequirePermission('pos.service.catalog.manage') @Post(':productId/details')
 configure(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('productId',new ParseUUIDPipe()) id:string,@Body() body:ConfigureServiceDto,@Req() req:Request){return this.services.configure(branch,id,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.service.catalog.manage') @Post('offers/:offerId/materials')
 material(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('offerId',new ParseUUIDPipe()) id:string,@Body() body:AddServiceMaterialDto,@Req() req:Request){return this.services.material(branch,id,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.catalog.read') @Get('offers/:offerId/materials')
 recipe(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('offerId',new ParseUUIDPipe()) id:string,@Req() req:Request){return this.services.recipe(branch,id,req.principal!);}
 @RequirePermission('pos.service.fulfill') @Post('sale-lines/:saleLineId/fulfill')
 fulfill(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('saleLineId',new ParseUUIDPipe()) id:string,@Body() body:FulfillServiceDto,@Req() req:Request){return this.services.fulfill(branch,id,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('pos.catalog.read') @Get('sale-lines/:saleLineId/fulfillment')
 detail(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('saleLineId',new ParseUUIDPipe()) id:string,@Req() req:Request){return this.services.detail(branch,id,req.principal!);}
}
