import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { ApproveFuelTaxDto,PreviewFuelTaxDto,ProposeFuelTaxDto } from './tax-policy.dto.js';
import { TaxPolicyService } from './tax-policy.service.js';
@Controller('branches/:branchId/fuel-tax-policies')
export class TaxPolicyController {
 constructor(private readonly policies:TaxPolicyService) {}
 @RequirePermission('sale.read') @Get()
 list(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Query('fuelProductId') productId:string|undefined,@Req() req:Request){return this.policies.list(branchId,req.principal!,productId);}
 @RequirePermission('tax.policy.propose') @Post('proposals')
 propose(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Body() body:ProposeFuelTaxDto,@Req() req:Request){return this.policies.propose(branchId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('tax.policy.approve') @Post('proposals/:proposalId/approve')
 approve(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Param('proposalId',new ParseUUIDPipe()) proposalId:string,@Body() body:ApproveFuelTaxDto,@Req() req:Request){return this.policies.approve(branchId,proposalId,req.principal!,body,req.header('x-request-id')!);}
 @RequirePermission('sale.read') @HttpCode(200) @Post('preview')
 preview(@Param('branchId',new ParseUUIDPipe()) branchId:string,@Body() body:PreviewFuelTaxDto,@Req() req:Request){return this.policies.preview(branchId,req.principal!,body);}
}
