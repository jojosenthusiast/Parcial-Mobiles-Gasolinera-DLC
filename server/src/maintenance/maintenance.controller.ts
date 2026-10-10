import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { AdvanceWorkOrderDto, AssetIntervalDto, CreateMaintenancePlanDto, CreateWorkOrderDto, GenerateMaintenanceDto, ObservationDto, RegisterAssetDto, ReleaseBlockDto, UseMaintenancePartDto, WorkTaskDto } from './maintenance.dto.js';
import { MaintenanceService } from './maintenance.service.js';

@Controller('branches/:branchId/maintenance')
export class MaintenanceController {
 constructor(private readonly maintenance:MaintenanceService) {}
 @RequirePermission('maintenance.plan') @Get('assets') assets(@Param('branchId',new ParseUUIDPipe()) b:string,@Req() r:Request){return this.maintenance.assets(b,r.principal!);}
 @RequirePermission('maintenance.plan') @Post('assets')
 asset(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:RegisterAssetDto,@Req() r:Request){return this.maintenance.registerAsset(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('maintenance.plan') @Post('plans')
 plan(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:CreateMaintenancePlanDto,@Req() r:Request){return this.maintenance.plan(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('maintenance.plan') @Post('orders')
 order(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:CreateWorkOrderDto,@Req() r:Request){return this.maintenance.order(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('maintenance.plan') @Get('orders')
 list(@Param('branchId',new ParseUUIDPipe()) b:string,@Query('status') status:string|undefined,@Query('q') q:string|undefined,@Query('cursor') cursor:string|undefined,@Query('limit') limit:string|undefined,@Req() r:Request){return this.maintenance.list(b,r.principal!,{...(status===undefined?{}:{status}),...(q===undefined?{}:{q}),...(cursor===undefined?{}:{cursor}),...(limit===undefined?{}:{limit})});}
 @RequirePermission('maintenance.work') @Post('observations')
 observe(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:ObservationDto,@Req() r:Request){return this.maintenance.observe(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('maintenance.plan') @Get('orders/:orderId')
 detail(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('orderId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.maintenance.detail(b,id,r.principal!);}
 @RequirePermission('maintenance.work') @Post('orders/:orderId/tasks')
 task(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('orderId',new ParseUUIDPipe()) id:string,@Body() body:WorkTaskDto,@Req() r:Request){return this.maintenance.task(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('maintenance.part.use') @Post('orders/:orderId/parts/use')
 usePart(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('orderId',new ParseUUIDPipe()) id:string,@Body() body:UseMaintenancePartDto,@Req() r:Request){return this.maintenance.usePart(b,id,r.principal!,body,r.header('x-request-id')!);}
 @Post('orders/:orderId/transition')
 advance(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('orderId',new ParseUUIDPipe()) id:string,@Body() body:AdvanceWorkOrderDto,@Req() r:Request){return this.maintenance.advance(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('maintenance.release') @Post('orders/:orderId/release')
 release(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('orderId',new ParseUUIDPipe()) id:string,@Body() body:ReleaseBlockDto,@Req() r:Request){return this.maintenance.release(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('maintenance.plan') @Post('plans/generate')
 generate(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:GenerateMaintenanceDto,@Req() r:Request){return this.maintenance.generate(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('maintenance.plan') @Post('assets/:assetId/intervals')
 interval(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('assetId',new ParseUUIDPipe()) id:string,@Body() body:AssetIntervalDto,@Req() r:Request){return this.maintenance.interval(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('maintenance.plan') @Get('assets/:assetId/availability')
 availability(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('assetId',new ParseUUIDPipe()) id:string,@Query('from') from:string,@Query('to') to:string,@Req() r:Request){return this.maintenance.availability(b,id,r.principal!,from,to);}
}
