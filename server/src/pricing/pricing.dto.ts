import { IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';

const positiveDecimal = /^(?:0|[1-9]\d{0,9})(?:\.\d{1,8})?$/;

export class MarketPriceReferenceDto {
  @IsUUID()
  fuelProductId!: string;

  @IsIn(['occidental','central','oriental','other'])
  zone!: 'occidental' | 'central' | 'oriental' | 'other';

  @IsDateString()
  announcedAt!: string;

  @IsOptional()
  @IsDateString()
  effectiveAt?: string;

  @IsIn(['increase','decrease','unchanged','unknown'])
  direction!: 'increase' | 'decrease' | 'unchanged' | 'unknown';

  @IsOptional()
  @IsString()
  @Matches(positiveDecimal)
  referencePrice?: string;

  @IsIn(['liter','us_gallon'])
  unit!: 'liter' | 'us_gallon';

  @IsString()
  @MinLength(1)
  @MaxLength(120)
  sourceName!: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  sourceReference?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

export class FuelPriceProposalDto {
  @IsUUID()
  fuelProductId!: string;

  @IsIn(['full_service','self_service'])
  serviceMode!: 'full_service' | 'self_service';

  @IsString()
  @Matches(/^(?:0|[1-9]\d{0,5})(?:\.\d{1,8})?$/)
  priceUsdPerUnit!: string;

  @IsIn(['liter','us_gallon'])
  unit!: 'liter' | 'us_gallon';

  @IsDateString()
  effectiveAt!: string;

  @IsOptional()
  @IsUUID()
  marketReferenceId?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reason!: string;
}

export class PriceDecisionDto {
  @IsInt()
  @Min(1)
  @Max(2147483647)
  expectedVersion!: number;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}
