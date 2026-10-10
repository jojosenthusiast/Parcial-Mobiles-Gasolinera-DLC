import { Body, Controller, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from './permission.decorator.js';
import { ApprovalService } from './approval.service.js';
import { DecideApprovalDto } from './approval.dto.js';

@Controller('approvals')
export class ApprovalController {
  constructor(private readonly approvals: ApprovalService) {}

  @RequirePermission('approval.decide')
  @Post(':approvalId/decision')
  async decide(@Param('approvalId', new ParseUUIDPipe()) id: string, @Body() body: DecideApprovalDto, @Req() request: Request) {
    const principal = request.principal!;
    const branchId = body.branchId ?? null;
    await this.approvals.decide(id, principal, body.decision, body.reason, branchId, request.header('x-request-id')!);
    return { data: { id, status: body.decision } };
  }
}
