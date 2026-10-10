import { Body, Controller, Get, Inject, Param, ParseUUIDPipe, Patch, Query, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { Pool } from 'pg';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { PG_POOL } from '../database/database.module.js';
import { MetricsService } from './metrics.service.js';
import { InventoryAlertPolicyDto } from './metrics.dto.js';
import { httpMetrics, renderPrometheusMetrics } from '../observability/http-metrics.js';
@Controller('metrics')
export class MetricsController {
 constructor(private readonly metrics:MetricsService,@Inject(PG_POOL) private readonly pool:Pool){}
 @RequirePermission('inventory.read') @Get('branches/:branchId/dashboard')
 branch(@Param('branchId',new ParseUUIDPipe()) id:string,@Req() req:Request){return this.metrics.branch(id,req.principal!);}
 @RequirePermission('branch.manage') @Patch('branches/:branchId/inventory-alert-policy')
 policy(@Param('branchId',new ParseUUIDPipe()) id:string,@Body() body:InventoryAlertPolicyDto,@Req() req:Request){
  return this.metrics.setInventoryPolicy(id,req.principal!,body,req.header('x-request-id')!);
 }
 @RequirePermission('branch.read') @Get('network/dashboard')
 network(@Query('days') days:string|undefined,@Query('branchId') branchId:string|undefined,@Req() req:Request){
  return this.metrics.network(req.principal!,days,branchId);
 }
 @RequirePermission('branch.manage') @Get('http')
 http(@Res() response:Response){
  const body=renderPrometheusMetrics(httpMetrics.snapshot(),{
   total:this.pool.totalCount,idle:this.pool.idleCount,waiting:this.pool.waitingCount,
  });
  response.setHeader('Content-Type','text/plain; version=0.0.4; charset=utf-8');
  return response.send(body);
 }
}
