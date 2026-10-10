import { IsArray, IsBoolean, IsIn, IsInt, IsISO8601, IsOptional, IsString, IsUUID, Length, Matches, Min } from 'class-validator';
export class CreateEmployeeDto {
 @IsString() @Length(2,40) employeeCode!:string;
 @IsString() @Length(2,160) legalName!:string;
 @IsString() @Length(2,100) positionTitle!:string;
 @IsOptional() @IsString() contactEmail?:string;
 @IsOptional() @Matches(/^\+?[0-9 ()-]{7,24}$/) contactPhone?:string;
 @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) hiredOn?:string;
}
export class UpdateEmployeeProfileDto {
 @IsString() @Length(2,160) legalName!:string;
 @IsString() @Length(2,100) positionTitle!:string;
 @IsOptional() @Matches(/^[^\s@]+@[^\s@]+\.[^\s@]+$/) contactEmail?:string|null;
 @IsOptional() @Matches(/^\+?[0-9 ()-]{7,24}$/) contactPhone?:string|null;
 @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) hiredOn?:string|null;
 @IsInt() @Min(1) expectedVersion!:number;
}
export class ChangeEmployeeDto {
 @IsUUID() commandId!:string;
 @IsInt() @Min(1) expectedVersion!:number;
 @IsIn(['active','leave','suspended','terminated']) status!:string;
 @IsOptional() @IsUUID() branchId?:string|null;
 @Matches(/^\d{4}-\d{2}-\d{2}$/) effectiveOn!:string;
 @IsString() @Length(10,500) reason!:string;
}
export class ScheduleShiftDto {
 @IsUUID() commandId!:string;
 @IsUUID() employeeId!:string;
 @IsIn(['cashier','forecourt','store','manager','maintenance']) position!:string;
 @IsOptional() @IsUUID() cashRegisterId?:string;
 @IsOptional() @IsUUID() dispenserId?:string;
 @IsISO8601({strict:true}) startsAt!:string;
 @IsISO8601({strict:true}) endsAt!:string;
}
export class CancelShiftDto {
 @IsUUID() commandId!:string;
 @IsString() @Length(10,500) reason!:string;
}
export class AttendanceDto {
 @IsUUID() commandId!:string;
 @IsIn(['clock_in','clock_out','correction']) kind!:string;
 @IsISO8601({strict:true}) occurredAt!:string;
 @IsOptional() @IsUUID() correctsEventId?:string;
 @IsOptional() @IsString() @Length(10,500) reason?:string;
}
export class HandoverDto {
 @IsUUID() commandId!:string;
 @IsUUID() incomingShiftId!:string;
 @IsArray() pendingItems!:unknown[];
 @IsString() @Length(5,500) equipmentNote!:string;
 @IsOptional() @IsUUID() cashSessionId?:string;
 @IsOptional() @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) observedCashUsd?:string;
}
export class AcknowledgeHandoverDto {
 @IsUUID() commandId!:string;
 @IsString() @Length(5,500) note!:string;
}
export class StaffingBlockDto {
 @IsUUID() commandId!:string;
 @IsBoolean() blocked!:boolean;
 @IsString() @Length(10,500) reason!:string;
}
export class ApplyEmployeePlanDto {
 @IsUUID() commandId!:string;
}
