import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsDateString, IsIn, IsString, IsUUID, MaxLength, MinLength, ValidateNested } from 'class-validator';
import type { FuelTaxRule } from '../../scripts/fuel-tax.mjs';
export class FuelTaxRuleDto implements FuelTaxRule {
 @IsString() @MaxLength(24) code!: string;
 @IsString() @MinLength(1) @MaxLength(120) label!: string;
 @IsIn(['percentage','fixed_per_liter','fixed_per_us_gallon']) kind!: FuelTaxRule['kind'];
 @IsIn(['net','net_plus_fixed','observed_volume']) base!: FuelTaxRule['base'];
 @IsString() @MaxLength(25) rate!: string;
}
export class ProposeFuelTaxDto {
 @IsUUID() commandId!: string;
 @IsUUID() fuelProductId!: string;
 @IsIn(['included','exempt','unconfigured']) mode!: 'included'|'exempt'|'unconfigured';
 @IsArray() @ArrayMaxSize(8) @ValidateNested({each:true}) @Type(()=>FuelTaxRuleDto) rules!: FuelTaxRuleDto[];
 @IsString() @MinLength(1) @MaxLength(500) sourceReference!: string;
 @IsString() @MinLength(1) @MaxLength(500) reason!: string;
 @IsDateString() effectiveAt!: string;
}
export class ApproveFuelTaxDto { @IsUUID() commandId!: string; }
export class PreviewFuelTaxDto {
 @IsUUID() policyVersionId!: string;
 @IsString() @MaxLength(19) grossUsd!: string;
 @IsString() @MaxLength(25) quantityL!: string;
}
