import { IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min } from 'class-validator';

const decimalPattern = /^\d{1,12}(?:\.\d{1,12})?$/;

export class FuelInventoryCommandDto {
  @IsUUID()
  commandId!: string;

  @IsString()
  @Matches(decimalPattern)
  quantity!: string;

  @IsIn(['liter', 'us_gallon'])
  unit!: 'liter' | 'us_gallon';

  @IsIn(['observed', 'compensated', 'nominal'])
  volumeBasis!: 'observed' | 'compensated' | 'nominal';

  @IsOptional()
  @IsString()
  @Matches(decimalPattern)
  compensatedQuantity?: string;

  @IsOptional()
  @IsString()
  @Matches(/^-?\d{1,3}(?:\.\d{1,4})?$/)
  temperatureC?: string;

  @IsOptional()
  @IsString()
  @Matches(/^-?\d{1,3}(?:\.\d{1,4})?$/)
  referenceTemperatureC?: string;

  @IsOptional()
  @IsString()
  @Matches(decimalPattern)
  waterLiters?: string;

  @IsOptional()
  @IsString()
  @Matches(decimalPattern)
  totalCostUsd?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  reasonCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  documentReference?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  sourceId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  sourceLine?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(2147483647)
  expectedBalanceVersion?: number;

  @IsOptional()
  @IsIn(['in', 'out'])
  direction?: 'in' | 'out';
}

export class FuelInventoryOpeningDto extends FuelInventoryCommandDto {
  @IsIn(['known', 'unknown', 'provisional'])
  valuationQuality!: 'known' | 'unknown' | 'provisional';
}
