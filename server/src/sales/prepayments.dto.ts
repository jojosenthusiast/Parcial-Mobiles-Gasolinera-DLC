import { IsIn, IsOptional, IsString, IsUUID, Matches, MaxLength } from 'class-validator';

export class CollectPrepaymentDto {
  @IsUUID() commandId!: string;
  @IsUUID() cashSessionId!: string;
  @IsIn(['cash', 'card']) method!: 'cash' | 'card';
  @IsIn(['manual', 'simulated']) mode!: 'manual' | 'simulated';
  @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) amountUsd!: string;
  @IsOptional() @IsIn(['USD']) currency?: 'USD';
  @IsIn(['captured', 'authorization_hold']) tenderKind!: 'captured' | 'authorization_hold';
  @IsIn(['confirmed', 'declined', 'unknown']) outcome!: 'confirmed' | 'declined' | 'unknown';
  @IsOptional() @IsString() @MaxLength(200) evidenceReference?: string;
}

export class ResolvePrepaymentDto {
  @IsUUID() commandId!: string;
  @IsIn(['confirmed', 'declined']) outcome!: 'confirmed' | 'declined';
  @IsString() @MaxLength(200) evidenceReference!: string;
}

export class AllocatePrepaymentDto {
  @IsUUID() saleId!: string;
  @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) amountUsd!: string;
  @IsUUID() commandId!: string;
  @IsOptional() @IsUUID() paymentEventId?: string;
}

export class RequestReleaseDto {
  @IsUUID() commandId!: string;
  @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) amountUsd!: string;
}

export class ConfirmReleaseDto {
  @IsUUID() commandId!: string;
  @IsString() @MaxLength(200) confirmationReference!: string;
}
