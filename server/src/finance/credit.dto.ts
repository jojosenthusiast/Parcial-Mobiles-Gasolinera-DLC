import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, Length, Matches } from 'class-validator';
export class CreateCommercialCustomerDto {
 @Matches(/^[A-Z0-9_-]{2,30}$/) code!:string;
 @IsString() @Length(3,160) legalName!:string;
 @IsOptional() @IsString() @Length(2,80) taxReference?:string;
 @Matches(/^[1-9][0-9]{0,8}(\.[0-9]{1,2})?$/) creditLimitUsd!:string;
 @Matches(/^(?:[1-9]|[1-9][0-9]|1[01][0-9]|120)$/) termsDays!:string;
}
export class CommercialCustomerEventDto {
 @IsUUID() commandId!:string;
 @IsIn(['activate','suspend','limit','terms']) kind!:string;
 @IsOptional() @Matches(/^[1-9][0-9]{0,8}(\.[0-9]{1,2})?$/) newLimitUsd?:string;
 @IsOptional() @Matches(/^(?:[1-9]|[1-9][0-9]|1[01][0-9]|120)$/) newTermsDays?:string;
 @IsString() @Length(10,500) reason!:string;
}
export class AddCommercialBuyerDto {
 @Matches(/^[A-Z0-9_-]{2,30}$/) buyerCode!:string;
 @IsString() @Length(3,160) fullName!:string;
}
export class ChargeCommercialSaleDto {
 @IsUUID() commandId!:string;
 @IsUUID() customerId!:string;
 @IsUUID() buyerId!:string;
 @IsString() @Length(5,200) buyerEvidence!:string;
}
export class ReceiveCommercialCreditDto {
 @IsUUID() commandId!:string;
 @Matches(/^[1-9][0-9]{0,8}(\.[0-9]{1,2})?$/) amountUsd!:string;
 @IsIn(['cash','bank_reported']) method!:string;
 @IsOptional() @IsUUID() cashSessionId?:string;
 @IsString() @Length(5,200) evidenceReference!:string;
}
export class VerifyCommercialBankDto {
 @IsUUID() commandId!:string;
 @IsIn(['confirmed','rejected']) outcome!:string;
 @IsString() @Length(10,500) reason!:string;
}
export class ChangeCommercialBuyerDto {
 @IsUUID() commandId!:string;
 @IsBoolean() active!:boolean;
 @IsString() @Length(10,500) reason!:string;
}
