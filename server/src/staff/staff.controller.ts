import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RequirePermission } from '../authorization/permission.decorator.js';
import { AcknowledgeHandoverDto, ApplyEmployeePlanDto, AttendanceDto, CancelShiftDto, ChangeEmployeeDto, CreateEmployeeDto, HandoverDto, ScheduleShiftDto, StaffingBlockDto, UpdateEmployeeProfileDto } from './staff.dto.js';
import { StaffService } from './staff.service.js';
@Controller('branches/:branchId/staff')
export class StaffController {
 constructor(private readonly staff:StaffService){}
 @RequirePermission('staff.manage') @Post('employees')
 create(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:CreateEmployeeDto,@Req() r:Request){return this.staff.create(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('staff.manage') @Patch('employees/:employeeId')
 updateProfile(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('employeeId',new ParseUUIDPipe()) id:string,@Body() body:UpdateEmployeeProfileDto,@Req() r:Request){return this.staff.updateProfile(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('staff.read') @Get('employees')
 employees(@Param('branchId',new ParseUUIDPipe()) b:string,@Query() q:{q?:string;status?:string;cursor?:string;limit?:string},@Req() r:Request){
  const {limit,...filters}=q;
  return this.staff.employees(b,r.principal!,{...filters,...(limit===undefined?{}:{limit:Number(limit)})});
 }
 @RequirePermission('staff.manage') @Post('employees/:employeeId/transition')
 change(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('employeeId',new ParseUUIDPipe()) id:string,@Body() body:ChangeEmployeeDto,@Req() r:Request){return this.staff.change(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('staff.manage') @Post('employee-plans/:planId/apply')
 applyPlan(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('planId',new ParseUUIDPipe()) id:string,@Body() body:ApplyEmployeePlanDto,@Req() r:Request){return this.staff.applyPlan(b,id,r.principal!,body.commandId,r.header('x-request-id')!);}
 @RequirePermission('staff.read') @Get('employee-plans')
 plans(@Param('branchId',new ParseUUIDPipe()) b:string,@Req() r:Request){return this.staff.plans(b,r.principal!);}
 @RequirePermission('staff.shifts.plan') @Post('shifts')
 schedule(@Param('branchId',new ParseUUIDPipe()) b:string,@Body() body:ScheduleShiftDto,@Req() r:Request){return this.staff.schedule(b,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('staff.read') @Get('shifts')
 shifts(@Param('branchId',new ParseUUIDPipe()) b:string,@Query('from') from:string|undefined,@Query('to') to:string|undefined,@Req() r:Request){return this.staff.shifts(b,r.principal!,{...(from===undefined?{}:{from}),...(to===undefined?{}:{to})});}
 @RequirePermission('staff.shifts.plan') @Post('shifts/:shiftId/cancel')
 cancel(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('shiftId',new ParseUUIDPipe()) id:string,@Body() body:CancelShiftDto,@Req() r:Request){return this.staff.cancel(b,id,r.principal!,body,r.header('x-request-id')!);}
 @Post('shifts/:shiftId/attendance')
 attendance(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('shiftId',new ParseUUIDPipe()) id:string,@Body() body:AttendanceDto,@Req() r:Request){return this.staff.attendance(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('staff.handover') @Post('shifts/:shiftId/handovers')
 handover(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('shiftId',new ParseUUIDPipe()) id:string,@Body() body:HandoverDto,@Req() r:Request){return this.staff.handover(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('staff.handover') @Post('handovers/:handoverId/acknowledge')
 acknowledge(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('handoverId',new ParseUUIDPipe()) id:string,@Body() body:AcknowledgeHandoverDto,@Req() r:Request){return this.staff.acknowledge(b,id,r.principal!,body,r.header('x-request-id')!);}
 @RequirePermission('staff.staffing.block') @Post('dispensers/:dispenserId/availability')
 block(@Param('branchId',new ParseUUIDPipe()) b:string,@Param('dispenserId',new ParseUUIDPipe()) id:string,@Body() body:StaffingBlockDto,@Req() r:Request){return this.staff.block(b,id,r.principal!,body,r.header('x-request-id')!);}
}
