import { IsIn, IsInt, IsString, IsUUID, Length, Matches, Min } from 'class-validator';
export class ContaminationDto {
 @IsUUID() commandId!:string;
 @IsUUID() purchaseOrderLineId!:string;
 @IsUUID() tankId!:string;
 @IsInt() @Min(1) expectedBalanceVersion!:number;
 @IsString() @Matches(/^(?=.*[1-9])(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$/) actualQuantity!:string;
 @IsIn(['liter','us_gallon']) unit!:'liter'|'us_gallon';
 @IsString() @Length(3,120) documentReference!:string;
 @IsString() @Length(12,2000) description!:string;
}
export class ContaminationApprovalDto {
 @IsUUID() commandId!:string;
 @IsString() @Length(8,500) reason!:string;
}
export class ContaminationDisposalDto {
 @IsUUID() commandId!:string;
 @IsString() @Matches(/^(?=.*[1-9])(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$/) measuredLiters!:string;
 @IsString() @Length(3,120) evidenceReference!:string;
 @IsString() @Length(12,1000) note!:string;
}
