import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { AssignOperationalAssetDto, ChangeOperationalAssetStatusDto, CreateOperationalAssetDto, TransferOperationalAssetDto, UpdateOperationalAssetDto } from './operational-assets.dto.js';
import { OperationalAssetsService } from './operational-assets.service.js';

@Controller('branches/:branchId/operational-assets')
export class OperationalAssetsController {
 constructor(private readonly assets:OperationalAssetsService){}
 @RequirePermission('operational_asset.read') @Get('summary')
 summary(@Param('branchId',new ParseUUIDPipe()) branch:string,@Req() req:Request){return this.assets.summary(branch,req.principal!);}
 @RequirePermission('operational_asset.read') @Get()
 list(@Param('branchId',new ParseUUIDPipe()) branch:string,@Query('status') status:string|undefined,@Query('assetType') assetType:string|undefined,
  @Query('q') q:string|undefined,@Query('cursor') cursor:string|undefined,@Query('limit') limit:string|undefined,@Req() req:Request){
  return this.assets.list(branch,req.principal!,{...(status===undefined?{}:{status}),...(assetType===undefined?{}:{assetType}),...(q===undefined?{}:{q}),...(cursor===undefined?{}:{cursor}),...(limit===undefined?{}:{limit})});
 }
 @RequirePermission('operational_asset.manage') @Post()
 create(@Param('branchId',new ParseUUIDPipe()) branch:string,@Body() body:CreateOperationalAssetDto,@Req() req:Request){return this.assets.create(branch,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('operational_asset.read') @Get(':assetId')
 detail(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('assetId',new ParseUUIDPipe()) id:string,@Req() req:Request){return this.assets.detail(branch,id,req.principal!);}
 @RequirePermission('operational_asset.manage') @Post(':assetId/profile')
 update(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('assetId',new ParseUUIDPipe()) id:string,@Body() body:UpdateOperationalAssetDto,@Req() req:Request){return this.assets.update(branch,id,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('operational_asset.manage') @Post(':assetId/assignment')
 assign(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('assetId',new ParseUUIDPipe()) id:string,@Body() body:AssignOperationalAssetDto,@Req() req:Request){return this.assets.assign(branch,id,req.principal!,body,req.header('x-request-id')!);}
 @Post(':assetId/status')
 status(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('assetId',new ParseUUIDPipe()) id:string,@Body() body:ChangeOperationalAssetStatusDto,@Req() req:Request){return this.assets.changeStatus(branch,id,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('operational_asset.transfer') @Post(':assetId/transfer')
 transfer(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('assetId',new ParseUUIDPipe()) id:string,@Body() body:TransferOperationalAssetDto,@Req() req:Request){return this.assets.transfer(branch,id,req.principal!,body,req.header('x-request-id')!);}
}
