import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { CaptureCutMeterDto, CreateCutProfileDto, CutReconciliationPolicyDto, GenerateCutsDto, MeasureCutTankDto, OpenCutDto, PrepareCutDto, ReviewCutDto } from './cuts.dto.js';
import { CutsService } from './cuts.service.js';

@Controller('branches/:branchId/cuts')
export class CutsController {
 constructor(private readonly cuts:CutsService) {}
 @RequirePermission('branch.manage') @Post('profiles')
 profile(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:CreateCutProfileDto,@Req() r:Request){return this.cuts.createProfile(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('cut.capture') @Post('generate')
 generate(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:GenerateCutsDto,@Req() r:Request){return this.cuts.generate(b,r.principal!,body);}
 @RequirePermission('cut.read') @Get()
 list(@Param('branchId',new ParseUUIDPipe()) b:string,@Query('date') date:string,@Req() r:Request){return this.cuts.list(b,r.principal!,date);}
 @RequirePermission('cut.capture') @Post(':cutId/open')
 open(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('cutId',new ParseUUIDPipe()) id:string,@Body() body:OpenCutDto,@Req() r:Request){return this.cuts.open(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('cut.read') @Get(':cutId/assets')
 assets(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('cutId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.cuts.assets(b,id,r.principal!);}
 @RequirePermission('cut.capture') @Post(':cutId/meters')
 capture(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('cutId',new ParseUUIDPipe()) id:string,@Body() body:CaptureCutMeterDto,@Req() r:Request){return this.cuts.capture(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('cut.read') @Get(':cutId/progress')
 progress(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('cutId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.cuts.progress(b,id,r.principal!);}
 @RequirePermission('cut.capture') @Post(':cutId/tanks')
 tank(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('cutId',new ParseUUIDPipe()) id:string,@Body() body:MeasureCutTankDto,@Req() r:Request){return this.cuts.measureTank(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('branch.manage') @Post('policies')
 policy(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:CutReconciliationPolicyDto,@Req() r:Request){return this.cuts.createPolicy(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('cut.submit') @Post(':cutId/prepare')
 prepare(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('cutId',new ParseUUIDPipe()) id:string,@Body() body:PrepareCutDto,@Req() r:Request){return this.cuts.prepare(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('cut.read') @Get(':cutId/reconciliation')
 reconciliation(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('cutId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.cuts.reconciliation(b,id,r.principal!);}
 @RequirePermission('cut.close') @Post(':cutId/review')
 review(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('cutId',new ParseUUIDPipe()) id:string,@Body() body:ReviewCutDto,@Req() r:Request){return this.cuts.review(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('cut.close') @Post(':cutId/close')
 close(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('cutId',new ParseUUIDPipe()) id:string,@Body() body:PrepareCutDto,@Req() r:Request){return this.cuts.close(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('cut.read') @Get(':cutId/closure')
 closure(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('cutId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.cuts.closure(b,id,r.principal!);}
}
