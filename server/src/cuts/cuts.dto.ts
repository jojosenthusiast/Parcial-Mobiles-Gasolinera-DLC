import { IsIn, IsInt, IsISO8601, IsOptional, IsString, IsUUID, Matches, MaxLength, Min } from 'class-validator';

export class CreateCutProfileDto {
 @IsString() @Matches(/^\d{4}-\d{2}-\d{2}$/) effectiveDate!:string;
 @IsString() @Matches(/^([01]\d|2[0-3]):[0-5]\d$/) dayStart!:string;
 @IsString() @Matches(/^([01]\d|2[0-3]):[0-5]\d$/) splitAt!:string;
}

export class GenerateCutsDto {
 @IsString() @Matches(/^\d{4}-\d{2}-\d{2}$/) operationalDate!:string;
}

export class OpenCutDto {
 @IsInt() @Min(1) expectedVersion!:number;
}

export class CaptureCutMeterDto {
 @IsUUID() nozzleId!:string;
 @IsUUID() readingId!:string;
 @IsInt() @Min(1) expectedVersion!:number;
}

export class MeasureCutTankDto {
 @IsUUID() tankId!:string;
 @IsInt() @Min(1) expectedVersion!:number;
 @IsString() @Matches(/^(0|[1-9]\d{0,8})(\.\d{1,9})?$/) measuredL!:string;
 @IsOptional() @IsString() @Matches(/^(0|[1-9]\d{0,8})(\.\d{1,9})?$/) waterL?:string;
 @IsOptional() @IsString() @Matches(/^-?\d{1,3}(\.\d{1,4})?$/) temperatureC?:string;
 @IsISO8601({strict:true}) observedAt!:string;
 @IsIn(['manual','device','simulated']) source!:'manual'|'device'|'simulated';
 @IsOptional() @IsString() @MaxLength(200) evidenceReference?:string;
}

export class CutReconciliationPolicyDto {
 @IsString() @Matches(/^\d{4}-\d{2}-\d{2}$/) effectiveDate!:string;
 @IsString() @Matches(/^(0|[1-9]\d{0,5})(\.\d{1,6})?$/) meterToleranceL!:string;
 @IsString() @Matches(/^(0|[1-9]\d{0,5})(\.\d{1,6})?$/) tankToleranceL!:string;
 @IsString() @Matches(/^(0|[1-9]\d{0,5})(\.\d{1,2})?$/) collectionToleranceUsd!:string;
 @IsIn([true,false]) autoCloseEnabled!:boolean;
}

export class PrepareCutDto {
 @IsInt() @Min(1) expectedVersion!:number;
}

export class ReviewCutDto extends PrepareCutDto {
 @IsString() @Matches(/^\s*\S.{6,498}\S\s*$/) reason!:string;
}
