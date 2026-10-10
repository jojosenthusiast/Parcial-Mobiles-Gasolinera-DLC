import { IsBoolean, IsOptional, IsString, IsUUID, Length, Matches, MaxLength } from 'class-validator';

export class CustomerProfileDto {
  @IsString() @Length(2, 160) fullName!: string;
  @IsOptional() @IsString() @Matches(/^\+?[0-9 ()-]{7,24}$/) phone?: string;
  @IsString() @Length(1, 40) termsVersion!: string;
  @IsBoolean() termsAccepted!: boolean;
  @IsBoolean() communicationsConsent!: boolean;
}

export class CustomerHistoryQueryDto {
  @IsOptional() @IsString() @MaxLength(200) cursor?: string;
}

export class LinkCustomerSaleDto {
  @IsUUID() commandId!: string;
  @IsUUID() customerCode!: string;
}

export class MarkCustomerNotificationDto {
  @IsUUID() notificationId!: string;
}
