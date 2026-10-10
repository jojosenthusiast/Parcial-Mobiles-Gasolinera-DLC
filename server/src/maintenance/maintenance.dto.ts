import { IsIn, IsInt, IsISO8601, IsOptional, IsString, IsUUID, Length, Matches, Max, Min } from 'class-validator';

export class RegisterAssetDto {
 @IsIn(['tank','dispenser','nozzle']) assetType!:string;
 @IsUUID() assetId!:string;
 @IsIn(['low','medium','high','critical']) criticality!:string;
 @IsOptional() @IsString() @Length(1,160) manufacturer?:string;
 @IsOptional() @IsString() @Length(1,160) model?:string;
 @IsOptional() @IsString() @Length(1,160) serialNumber?:string;
 @IsOptional() @IsString() @Length(1,160) locationLabel?:string;
 @IsOptional() @IsUUID() supplierId?:string;
}
export class CreateMaintenancePlanDto {
 @IsUUID() assetProfileId!:string;
 @IsString() @Length(1,40) code!:string;
 @IsString() @Length(8,500) description!:string;
 @IsOptional() @IsInt() @Min(1) cadenceDays?:number;
 @IsOptional() @IsString() cadenceUsage?:string;
 @IsOptional() @IsString() usageUnit?:string;
 @IsOptional() @IsISO8601({strict:true}) nextDueAt?:string;
 @IsOptional() @IsString() nextDueUsage?:string;
}
export class CreateWorkOrderDto {
 @IsUUID() assetProfileId!:string;
 @IsOptional() @IsUUID() planId?:string;
 @IsOptional() @IsUUID() incidentId?:string;
 @IsOptional() @IsUUID() targetBlockId?:string;
 @IsIn(['preventive','corrective','inspection']) kind!:string;
 @IsString() @Length(1,100) dueKey!:string;
 @IsString() @Length(8,1000) description!:string;
 @IsOptional() @IsUUID() assignedTo?:string;
 @IsOptional() @IsISO8601({strict:true}) dueAt?:string;
 @IsOptional() @IsString() estimateUsd?:string;
}
export class WorkTaskDto {
 @IsString() @Length(5,500) description!:string;
 @IsString() @Length(5,1000) result!:string;
 @IsOptional() @IsInt() @Min(0) @Max(1000000) laborMinutes?:number;
 @IsOptional() @IsString() laborEstimateUsd?:string;
}
export class ObservationDto {
 @IsUUID() assetProfileId!:string;
 @IsOptional() @IsUUID() workOrderId?:string;
 @IsIn(['water_level','fuel_temperature','line_pressure','leak_test','calibration','usage_counter','other']) metric!:string;
 @IsOptional() @IsString() value?:string;
 @IsOptional() @IsString() unit?:string;
 @IsIn(['pass','fail','observed','unknown']) outcome!:string;
 @IsIn(['manual','device','laboratory']) source!:string;
 @IsOptional() @IsString() instrumentReference?:string;
 @IsOptional() @IsString() evidenceReference?:string;
 @IsISO8601({strict:true}) observedAt!:string;
}
export class AdvanceWorkOrderDto {
 @IsInt() @Min(1) expectedVersion!:number;
 @IsIn(['in_progress','completed','verified','cancelled']) nextStatus!:string;
 @IsOptional() @IsString() diagnosis?:string;
}
export class ReleaseBlockDto {
 @IsUUID() blockId!:string;
 @IsString() @Length(8,500) reason!:string;
}
export class GenerateMaintenanceDto {
 @IsISO8601({strict:true}) asOf!:string;
}
export class AssetIntervalDto {
 @IsIn(['available','maintenance','technical_failure','staffing','no_product','closed']) reason!:string;
 @IsISO8601({strict:true}) effectiveAt!:string;
 @IsOptional() @IsUUID() sourceOrderId?:string;
}
export class UseMaintenancePartDto {
 @IsUUID() commandId!:string;
 @IsUUID() lotId!:string;
 @Matches(/^[1-9][0-9]{0,8}$/) quantity!:string;
 @IsString() @Length(5,300) taskReference!:string;
}
