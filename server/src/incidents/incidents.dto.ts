import { IsIn, IsInt, IsISO8601, IsOptional, IsString, IsUUID, Length, Min } from 'class-validator';

export class CreateIncidentDto {
 @IsUUID() commandId!:string;
 @IsIn(['personal_injury','third_party_damage','premises_damage','equipment_damage','asset_missing','fuel_spill','wrong_tank_delivery','fuel_variance','safety','other']) category!:string;
 @IsIn(['low','medium','high','critical']) severity!:string;
 @IsIn(['branch','dispenser','nozzle','tank','sale','operational_asset','other']) assetType!:string;
 @IsOptional() @IsUUID() assetId?:string;
 @IsString() @Length(12,2000) description!:string;
 @IsISO8601({strict:true}) occurredAt!:string;
}

export class AdvanceIncidentDto {
 @IsInt() @Min(1) expectedVersion!:number;
 @IsIn(['assessed','in_progress','resolved','closed']) nextStatus!:string;
 @IsOptional() @IsUUID() assigneeId?:string;
 @IsOptional() @IsISO8601({strict:true}) dueAt?:string;
 @IsString() @Length(5,1000) note!:string;
}

export class AssessIncidentDto {
 @IsIn(['fuel_loss','repair','third_party']) impactType!:string;
 @IsOptional() @IsUUID() tankId?:string;
 @IsOptional() @IsString() @Length(1,40) quantityL?:string;
 @IsOptional() @IsIn(['full_service','self_service']) serviceMode?:string;
 @IsOptional() @IsString() @Length(1,30) estimateUsd?:string;
 @IsString() @Length(8,1000) note!:string;
}

export class ApproveIncidentLossDto {
 @IsUUID() commandId!:string;
 @IsString() @Length(8,500) reason!:string;
}

export class CreateRecoveryClaimDto {
 @IsIn(['third_party','insurer']) counterpartyType!:string;
 @IsString() @Length(2,160) counterpartyName!:string;
 @IsString() @Length(3,120) reference!:string;
 @IsString() @Length(1,30) claimedUsd!:string;
}

export class ReceiveRecoveryDto {
 @IsUUID() commandId!:string;
 @IsString() @Length(1,30) amountUsd!:string;
 @IsIn(['cash','bank_transfer','other']) method!:string;
 @IsString() @Length(3,200) evidenceReference!:string;
}

export class ReviewAnomalyDto {
 @IsIn(['open','investigating']) expectedStatus!:string;
 @IsIn(['investigating','dismissed','confirmed_loss']) nextStatus!:string;
 @IsString() @Length(8,500) note!:string;
}
