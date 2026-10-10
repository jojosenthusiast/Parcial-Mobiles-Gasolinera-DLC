import { IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, Min, MaxLength, Length } from 'class-validator';

const volumePattern=/^(?=.*[1-9])(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$/;
const amountPattern=/^(?=.*[1-9])(?:0|[1-9]\d{0,11})(?:\.\d{1,2})?$/;

export class CreateDispenseAuthorizationDto {
  @IsUUID() commandId!: string;
  @IsOptional() @IsString() @Matches(amountPattern) requestedAmountUsd?: string;
  @IsOptional() @IsString() @Matches(volumePattern) requestedVolume?: string;
  @IsOptional() @IsIn(['gallon_us','liter']) volumeUnit?: 'gallon_us'|'liter';
  @IsOptional() @IsInt() @Min(15) @Max(300) expiresInSeconds?: number;
}

export class DispenseProgressDto {
  @IsUUID() commandId!: string;
  @IsString() @Matches(volumePattern) quantity!: string;
  @IsIn(['gallon_us','liter']) unit!: 'gallon_us'|'liter';
  @IsInt() @Min(1) expectedVersion!: number;
}

export class DispenseCompletionDto extends DispenseProgressDto {
  @IsOptional() @IsString() @MaxLength(120) documentReference?: string;
}

export class DispenseReasonDto {
  @IsUUID() commandId!: string;
  @IsInt() @Min(1) expectedVersion!: number;
  @IsOptional() @IsString() @MaxLength(240) reason?: string;
}

export class DispenseNoFlowReconciliationDto {
  @IsUUID() commandId!: string;
  @IsInt() @Min(1) expectedVersion!: number;
  @IsString() @Length(1,120) evidenceReference!: string;
  @IsString() @Length(1,240) reason!: string;
}
