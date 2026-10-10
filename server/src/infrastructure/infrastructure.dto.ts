import { IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';

export class CreateFuelProductDto {
  @IsString() @Matches(/^[A-Za-z0-9._-]{1,40}$/) sku!: string;
  @IsString() @MinLength(1) @MaxLength(100) displayName!: string;
  @IsIn(['super', 'regular', 'diesel', 'other']) family!: 'super' | 'regular' | 'diesel' | 'other';
  @IsOptional() @IsString() @MaxLength(100) brand?: string;
}

export class UpdateFuelProductDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(100) displayName?: string;
  @IsOptional() @IsString() @MaxLength(100) brand?: string | null;
  @IsOptional() @IsIn(['active', 'inactive', 'archived']) status?: 'active' | 'inactive' | 'archived';
  @IsInt() @Min(1) expectedVersion!: number;
}

export class UpdateFuelOfferDto {
  @IsIn(['active', 'inactive']) status!: 'active' | 'inactive';
  @IsInt() @Min(1) expectedVersion!: number;
}

export class FuelSpecificationDto {
  @IsString() @Matches(/^[a-z][a-z0-9_.-]{1,60}$/) attributeCode!: string;
  @IsString() @MinLength(1) @MaxLength(160) value!: string;
  @IsOptional() @IsString() @MaxLength(30) unit?: string;
  @IsOptional() @IsString() @MaxLength(80) testMethod?: string;
  @IsString() @MinLength(2) @MaxLength(160) sourceName!: string;
  @IsOptional() @IsString() @MaxLength(300) sourceReference?: string;
  @IsDateString() validFrom!: string;
  @IsOptional() @IsDateString() validUntil?: string;
}

export class CreateTankDto {
  @IsString() @Matches(/^[A-Za-z0-9._-]{1,32}$/) code!: string;
  @IsString() @MinLength(1) @MaxLength(80) name!: string;
  @IsUUID() fuelProductId!: string;
  @IsString() @Matches(/^(0|[1-9]\d{0,11})(\.\d{1,12})?$/) nominalCapacityL!: string;
  @IsString() @Matches(/^(0|[1-9]\d{0,11})(\.\d{1,12})?$/) safeFillLimitL!: string;
  @IsString() @Matches(/^(0|[1-9]\d{0,11})(\.\d{1,12})?$/) unusableReserveL!: string;
}

export class CreateDispenserDto {
  @IsString() @Matches(/^[A-Za-z0-9._-]{1,32}$/) code!: string;
  @IsOptional() @IsString() @MaxLength(80) name?: string;
  @IsOptional() @IsDateString() commissionedAt?: string;
}

export class CreateNozzleDto {
  @IsString() @Matches(/^[A-Za-z0-9._-]{1,32}$/) code!: string;
  @IsString() @Matches(/^[A-Za-z0-9._-]{1,32}$/) productCode!: string;
  @IsUUID() fuelProductId!: string;
  @IsIn(['full_service', 'self_service']) serviceMode!: 'full_service' | 'self_service';
  @IsIn(['gallon_us', 'liter']) meterUnit!: 'gallon_us' | 'liter';
  @IsInt() @Min(0) @Max(9) meterPrecision!: number;
}

export class ConnectNozzleDto {
  @IsUUID() tankId!: string;
  @IsString() @MinLength(3) @MaxLength(500) reason!: string;
}

export class BranchProfileDto {
  @IsIn(['academicLab22', 'operational']) profile!: 'academicLab22' | 'operational';
  @IsInt() @Min(1) @Max(200) expectedDispenserCount!: number;
  @IsInt() @Min(0) expectedVersion!: number;
}

export class ChangePhysicalStatusDto {
  @IsIn(['active', 'maintenance', 'offline', 'decommissioned', 'removed']) status!: 'active' | 'maintenance' | 'offline' | 'decommissioned' | 'removed';
  @IsOptional() @IsString() @MaxLength(500) reason?: string;
  @IsInt() @Min(1) expectedVersion!: number;
}

export class CreateAssetBlockDto {
  @IsIn(['tank', 'dispenser', 'nozzle']) assetType!: 'tank' | 'dispenser' | 'nozzle';
  @IsUUID() assetId!: string;
  @IsIn(['technical', 'operational', 'safety', 'inventory']) blockType!: 'technical' | 'operational' | 'safety' | 'inventory';
  @IsString() @Matches(/^[A-Z0-9_]{2,50}$/) reasonCode!: string;
  @IsString() @MinLength(3) @MaxLength(500) reason!: string;
}

export class ResolveAssetBlockDto {
  @IsString() @MinLength(3) @MaxLength(500) resolution!: string;
}

export class NozzleMeterReadingDto {
  @IsUUID() commandId!: string;
  @IsString() @Matches(/^(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$/) value!: string;
  @IsOptional() @IsString() @MaxLength(80) meterSerial?: string;
  @IsIn(['manual','simulated','device']) source!: 'manual' | 'simulated' | 'device';
  @IsInt() @Min(0) expectedVersion!: number;
}

export class NozzleMeterBaselineDto extends NozzleMeterReadingDto {
  @IsOptional() @IsString() @MaxLength(120) note?: string;
}

export class NozzleMeterChangeDto {
  @IsUUID() commandId!: string;
  @IsString() @Matches(/^(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$/) value!: string;
  @IsString() @MinLength(1) @MaxLength(240) reason!: string;
  @IsString() @MinLength(1) @MaxLength(80) newSerial!: string;
  @IsOptional() @IsString() @MaxLength(80) oldSerial?: string;
  @IsIn(['manual','simulated','device']) source!: 'manual' | 'simulated' | 'device';
  @IsInt() @Min(1) expectedVersion!: number;
}
