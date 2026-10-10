import { IsIn, IsOptional, IsString, IsUUID, Length, Matches } from 'class-validator';
export class DemandQueryDto {
 @IsUUID() fuelProductId!:string;
 @IsIn(['7','14','30']) days!:'7'|'14'|'30';
 @IsOptional() @Matches(/^(0|[1-9][0-9]{0,2})$/) supplierLeadDays?:string;
 @IsOptional() @Matches(/^(0|[1-9][0-9]{0,2})$/) safetyDays?:string;
}
export class PublishSupplierQuoteDto {
 @IsUUID() supplierId!:string;
 @IsUUID() fuelProductId!:string;
 @IsIn(['liter','us_gallon']) unit!:string;
 @Matches(/^[1-9][0-9]{0,8}(\.[0-9]{1,8})?$/) unitPriceUsd!:string;
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) transportUsd!:string;
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) financingUsd!:string;
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,3})?$/) minimumDeliveryL!:string;
 @Matches(/^(0|[1-9][0-9]{0,2})$/) leadDays!:string;
 @Matches(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/) validFrom!:string;
 @Matches(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/) validUntil!:string;
 @IsIn(['confirmed','indicative']) confidence!:string;
 @IsString() @Length(5,200) documentReference!:string;
}
export class ComparePurchaseDto {
 @IsUUID() fuelProductId!:string;
 @IsUUID() currentQuoteId!:string;
 @IsOptional() @IsUUID() futureQuoteId?:string;
 @IsUUID() tankId!:string;
 @Matches(/^[1-9][0-9]{0,8}(\.[0-9]{1,3})?$/) quantityLiters!:string;
 @IsIn(['7','14','30']) days!:'7'|'14'|'30';
 @Matches(/^(0|[1-9][0-9]{0,2})$/) safetyDays!:string;
}
export class SavePurchaseScenarioDto {
 @IsUUID() commandId!:string;
 @IsUUID() fuelProductId!:string;
 @IsUUID() quoteId!:string;
 @IsUUID() tankId!:string;
 @Matches(/^[1-9][0-9]{0,8}(\.[0-9]{1,3})?$/) quantityLiters!:string;
 @IsIn(['7','14','30']) days!:'7'|'14'|'30';
 @Matches(/^(0|[1-9][0-9]{0,2})$/) safetyDays!:string;
}
export class DecidePurchaseScenarioDto {
 @IsUUID() commandId!:string;
 @IsIn(['approved','rejected']) outcome!:string;
 @IsString() @Length(10,500) reason!:string;
}
