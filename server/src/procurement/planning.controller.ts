import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { ComparePurchaseDto, DecidePurchaseScenarioDto, DemandQueryDto, PublishSupplierQuoteDto, SavePurchaseScenarioDto } from './planning.dto.js';
import { PlanningService } from './planning.service.js';
@Controller('branches/:branchId/procurement/planning')
export class PlanningController {
 constructor(private readonly planning:PlanningService){}
 @RequirePermission('purchase.read') @Get('demand')
 demand(@Param('branchId',new ParseUUIDPipe()) branch:string,@Query() q:DemandQueryDto,@Req() req:Request){
  return this.planning.demand(branch,req.principal!,q);
 }
 @RequirePermission('purchase.quote.manage') @Post('supplier-quotes')
 quote(@Param('branchId',new ParseUUIDPipe()) branch:string,@Body() x:PublishSupplierQuoteDto,@Req() req:Request){return this.planning.publishQuote(branch,req.principal!,x,req.header('x-request-id')!);}
 @RequirePermission('purchase.read') @Get('supplier-quotes')
 quotes(@Param('branchId',new ParseUUIDPipe()) branch:string,@Query('fuelProductId') fuel:string,@Req() req:Request){return this.planning.quotes(branch,req.principal!,fuel);}
 @RequirePermission('purchase.read') @Post('compare')
 compare(@Param('branchId',new ParseUUIDPipe()) branch:string,@Body() x:ComparePurchaseDto,@Req() req:Request){return this.planning.compare(branch,req.principal!,x);}
 @RequirePermission('purchase.create') @Post('scenarios')
 save(@Param('branchId',new ParseUUIDPipe()) branch:string,@Body() x:SavePurchaseScenarioDto,@Req() req:Request){return this.planning.save(branch,req.principal!,x,req.header('x-request-id')!);}
 @RequirePermission('purchase.read') @Get('scenarios')
 scenarios(@Param('branchId',new ParseUUIDPipe()) branch:string,@Req() req:Request){return this.planning.scenarios(branch,req.principal!);}
 @RequirePermission('purchase.read') @Get('scenarios/:scenarioId')
 scenario(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('scenarioId',new ParseUUIDPipe()) id:string,@Req() req:Request){return this.planning.scenario(branch,id,req.principal!);}
 @RequirePermission('purchase.scenario.approve') @Post('scenarios/:scenarioId/decision')
 decide(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('scenarioId',new ParseUUIDPipe()) id:string,@Body() x:DecidePurchaseScenarioDto,@Req() req:Request){return this.planning.decide(branch,id,req.principal!,x,req.header('x-request-id')!);}
 @RequirePermission('purchase.create') @Post('scenarios/:scenarioId/purchase-order')
 convert(@Param('branchId',new ParseUUIDPipe()) branch:string,@Param('scenarioId',new ParseUUIDPipe()) id:string,@Req() req:Request){return this.planning.convert(branch,id,req.principal!,req.header('x-request-id')!);}
}
