import { IsInt, IsUUID, Max, Min } from 'class-validator';

export class CreateCustomerPointQuoteDto {
  @IsUUID() commandId!: string;
  @IsUUID() cashSessionId!: string;
  @IsInt() @Min(1) @Max(2_000_000_000) points!: number;
}

export class CustomerPointQuoteDecisionDto {
  @IsUUID() commandId!: string;
}
