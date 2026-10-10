import { IsIn, IsInt, IsISO8601, IsOptional, IsString, IsUUID, Length, Matches, Min } from 'class-validator';

const assetTypes = ['payment_terminal','tire_gauge','air_hose','tool','safety_equipment','other'] as const;
export class CreateOperationalAssetDto {
  @IsUUID() commandId!: string;
  @Matches(/^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$/) code!: string;
  @IsIn(assetTypes) assetType!: typeof assetTypes[number];
  @IsString() @Length(2,120) name!: string;
  @IsOptional() @IsString() @Length(0,1000) description?: string;
  @IsOptional() @IsString() @Length(1,100) manufacturer?: string;
  @IsOptional() @IsString() @Length(1,100) model?: string;
  @IsOptional() @IsString() @Length(1,120) serialNumber?: string;
  @IsOptional() @IsISO8601({strict:true}) acquiredOn?: string;
  @IsOptional() @Matches(/^(0|[1-9]\d{0,15})(\.\d{1,2})?$/) acquisitionCostUsd?: string;
  @IsOptional() @IsString() @Length(1,160) locationLabel?: string;
  @IsString() @Length(4,500) note!: string;
}

export class UpdateOperationalAssetDto {
  @IsUUID() commandId!: string;
  @IsInt() @Min(1) expectedVersion!: number;
  @IsString() @Length(2,120) name!: string;
  @IsOptional() @IsString() @Length(0,1000) description?: string;
  @IsOptional() @IsString() @Length(1,100) manufacturer?: string;
  @IsOptional() @IsString() @Length(1,100) model?: string;
  @IsOptional() @IsString() @Length(1,120) serialNumber?: string;
  @IsOptional() @IsISO8601({strict:true}) acquiredOn?: string;
  @IsOptional() @Matches(/^(0|[1-9]\d{0,15})(\.\d{1,2})?$/) acquisitionCostUsd?: string;
  @IsOptional() @IsString() @Length(1,160) locationLabel?: string;
  @IsString() @Length(4,500) note!: string;
}

export class AssignOperationalAssetDto {
  @IsUUID() commandId!: string;
  @IsInt() @Min(1) expectedVersion!: number;
  @IsOptional() @IsUUID() custodianEmployeeId?: string | null;
  @IsString() @Length(4,500) note!: string;
}

export class ChangeOperationalAssetStatusDto {
  @IsUUID() commandId!: string;
  @IsInt() @Min(1) expectedVersion!: number;
  @IsIn(['available','under_repair','retired']) status!: 'available'|'under_repair'|'retired';
  @IsString() @Length(8,500) note!: string;
}

export class TransferOperationalAssetDto {
  @IsUUID() commandId!: string;
  @IsInt() @Min(1) expectedVersion!: number;
  @IsUUID() targetBranchId!: string;
  @IsString() @Length(8,500) note!: string;
}
