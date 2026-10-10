import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { AdvanceIncidentDto, ApproveIncidentLossDto, AssessIncidentDto, CreateIncidentDto, CreateRecoveryClaimDto, ReceiveRecoveryDto, ReviewAnomalyDto } from './incidents.dto.js';
import { IncidentsService } from './incidents.service.js';

@Controller('branches/:branchId/incidents')
export class IncidentsController {
 constructor(private readonly incidents:IncidentsService) {}
 @RequirePermission('incident.create') @Post()
 create(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:CreateIncidentDto,@Req() r:Request){return this.incidents.create(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('incident.read') @Get()
 list(@Param('branchId',new ParseUUIDPipe()) b:string,@Query('status') status:string|undefined,@Query('severity') severity:string|undefined,@Query('q') q:string|undefined,@Query('cursor') cursor:string|undefined,@Query('limit') limit:string|undefined,@Req() r:Request){return this.incidents.list(b,r.principal!,{...(status===undefined?{}:{status}),...(severity===undefined?{}:{severity}),...(q===undefined?{}:{q}),...(cursor===undefined?{}:{cursor}),...(limit===undefined?{}:{limit})});}
 @RequirePermission('incident.read') @Get(':incidentId')
 detail(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('incidentId',new ParseUUIDPipe()) id:string,@Req() r:Request){return this.incidents.detail(b,id,r.principal!);}
 @Post(':incidentId/transition')
 advance(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('incidentId',new ParseUUIDPipe()) id:string,@Body() body:AdvanceIncidentDto,@Req() r:Request){return this.incidents.advance(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('incident.assign') @Post(':incidentId/assessments')
 assess(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('incidentId',new ParseUUIDPipe()) id:string,@Body() body:AssessIncidentDto,@Req() r:Request){return this.incidents.assess(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('loss.approve') @Post(':incidentId/assessments/:assessmentId/approve-loss')
 approveLoss(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('incidentId',new ParseUUIDPipe()) id:string,@Param('assessmentId',new ParseUUIDPipe()) assessment:string,@Body() body:ApproveIncidentLossDto,@Req() r:Request){return this.incidents.approveLoss(b,id,assessment,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('incident.resolve') @Post(':incidentId/recovery-claims')
 claim(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('incidentId',new ParseUUIDPipe()) id:string,@Body() body:CreateRecoveryClaimDto,@Req() r:Request){return this.incidents.createClaim(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('incident.resolve') @Post(':incidentId/recovery-claims/:claimId/receipts')
 receive(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('incidentId',new ParseUUIDPipe()) id:string,@Param('claimId',new ParseUUIDPipe()) claim:string,@Body() body:ReceiveRecoveryDto,@Req() r:Request){return this.incidents.receiveRecovery(b,id,claim,r.principal!,body,r.header('x-request-id')!);}
}

@Controller('branches/:branchId/anomalies')
export class AnomaliesController {
 constructor(private readonly incidents:IncidentsService) {}
 @RequirePermission('incident.read') @Get()
 list(@Param('branchId',new ParseUUIDPipe()) b:string,@Query('status') status:string|undefined,@Req() r:Request){return this.incidents.anomalies(b,r.principal!,status);}
 @RequirePermission('incident.resolve') @Post(':alertId/review')
 review(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('alertId',new ParseUUIDPipe()) id:string,@Body() body:ReviewAnomalyDto,@Req() r:Request){return this.incidents.reviewAnomaly(b,id,r.principal!,body,r.header('x-request-id')!);}
}
