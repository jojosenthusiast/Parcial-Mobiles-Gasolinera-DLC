import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Matches, Max, MaxLength, Min, ValidateNested } from 'class-validator';

export class PromotionRecurrenceDto {
  @IsIn(['once', 'weekly', 'monthly']) kind!: 'once' | 'weekly' | 'monthly';
  @IsOptional() @IsArray() @ArrayMinSize(1) @ArrayMaxSize(7) @IsInt({ each: true }) @Min(0, { each: true }) @Max(6, { each: true }) weekdays?: number[];
  @IsOptional() @IsInt() @Min(1) @Max(31) dayOfMonth?: number;
}

export class PromotionTermsDto {
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(20) @IsString({ each: true }) @MaxLength(300, { each: true }) applies!: string[];
  @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @MaxLength(300, { each: true }) excludes!: string[];
}

export class PromotionTargetMetricDto {
  @IsIn(['sales_usd_30d','fuel_liters_30d']) metric!: 'sales_usd_30d' | 'fuel_liters_30d';
  @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) threshold!: string;
}

export class CreatePromotionDto {
  @IsUUID() commandId!: string;
  @IsOptional() @IsUUID() branchId?: string;
  @IsIn(['network', 'branch']) scope!: 'network' | 'branch';
  @IsOptional() @IsArray() @ArrayMaxSize(500) @IsUUID(undefined, { each: true }) targetBranchIds?: string[];
  @IsOptional() @IsArray() @ArrayMaxSize(4) @IsIn(['occidental','central','oriental','other'], { each: true }) targetZones?: Array<'occidental'|'central'|'oriental'|'other'>;
  @IsOptional() @ValidateNested() @Type(() => PromotionTargetMetricDto) targetMetric?: PromotionTargetMetricDto;
  @IsString() @MaxLength(120) title!: string;
  @IsString() @MaxLength(500) motive!: string;
  @IsIn(['unit_discount', 'percent_discount', 'cashback', 'points_multiplier', 'announcement']) kind!: 'unit_discount' | 'percent_discount' | 'cashback' | 'points_multiplier' | 'announcement';
  @Matches(/^(?:\d{4}-\d{2}-\d{2}|\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2}))$/) startsAt!: string;
  @Matches(/^(?:\d{4}-\d{2}-\d{2}|\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2}))$/) endsAt!: string;
  @IsString() @MaxLength(80) timeZone!: string;
  @ValidateNested() @Type(() => PromotionRecurrenceDto) recurrence!: PromotionRecurrenceDto;
  @IsOptional() @IsArray() @ArrayMaxSize(50) @IsUUID(undefined, { each: true }) productIds?: string[];
  @IsOptional() @IsArray() @ArrayMinSize(1) @ArrayMaxSize(2) @IsIn(['full_service', 'self_service'], { each: true }) serviceModes?: Array<'full_service' | 'self_service'>;
  @IsOptional() @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) value?: string;
  @IsOptional() @IsIn(['liter', 'us_gallon']) valueUnit?: 'liter' | 'us_gallon';
  @IsOptional() @Matches(/^[A-Z0-9_-]{2,40}$/) bankCode?: string;
  @IsOptional() @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) minimumSpendUsd?: string;
  @IsOptional() @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) benefitCapUsd?: string;
  @IsOptional() @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) totalBudgetUsd?: string;
  @IsOptional() @IsInt() @Min(1) @Max(1000) maxUsesPerCustomer?: number;
  @IsInt() @Min(1) @Max(100) priority!: number;
  @IsIn(['none', 'with_points']) stacking!: 'none' | 'with_points';
  @ValidateNested() @Type(() => PromotionTermsDto) terms!: PromotionTermsDto;
  @IsOptional() @IsString() @MaxLength(1000) imageUrl?: string;
  @IsOptional() @IsString() @MaxLength(240) imageAlt?: string;
}

export class PromotionCommandDto {
  @IsUUID() commandId!: string;
}

export class PromotionDecisionDto extends PromotionCommandDto {
  @IsIn(['approve', 'reject']) decision!: 'approve' | 'reject';
  @IsString() @MaxLength(1000) reason!: string;
}

export class PausePromotionDto extends PromotionCommandDto {
  @IsString() @MaxLength(500) reason!: string;
}

export class CreateCashbackPartnerDto extends PromotionCommandDto {
  @Matches(/^[A-Z0-9_-]{2,40}$/) code!: string;
  @IsString() @MaxLength(120) displayName!: string;
}

export class CashbackPartnerStatusDto extends PromotionCommandDto {
  @IsIn(['active', 'inactive']) status!: 'active' | 'inactive';
}

export class UploadPromotionImageDto {
  @IsUUID() commandId!: string;
  @IsIn(['network', 'branch']) scope!: 'network' | 'branch';
  @IsOptional() @IsUUID() branchId?: string;
  @IsIn(['image/jpeg', 'image/png', 'image/webp']) mimeType!: 'image/jpeg' | 'image/png' | 'image/webp';
  @IsString() @Length(80, 1400000) @Matches(/^[A-Za-z0-9+/]+={0,2}$/) dataBase64!: string;
}
