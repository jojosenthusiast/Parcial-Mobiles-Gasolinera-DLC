import { IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';

export class CreateLoyaltyProgramDto {
  @IsUUID() commandId!: string;
  @IsNumber({ maxDecimalPlaces: 6 }) @Min(0.000001) @Max(1000) pointsPerEligibleUsd!: number;
  @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(1000000) minimumEligibleUsd!: number;
  @IsNumber({ maxDecimalPlaces: 6 }) @Min(0) @Max(1000) redemptionUsdPerPoint!: number;
}

export class LoyaltyProgramCommandDto {
  @IsUUID() commandId!: string;
}

export class LoyaltyProgramDecisionDto {
  @IsUUID() commandId!: string;
  @IsString() decision!: 'approve' | 'reject';
  @IsOptional() @IsString() @MaxLength(500) reason?: string;
}
