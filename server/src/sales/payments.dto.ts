import { IsIn, IsOptional, IsString, IsUUID, Matches, MaxLength } from 'class-validator';
export class OpenCashDto {
 @IsUUID() commandId!:string;
 @IsUUID() registerId!:string;
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) openingUsd!:string;
}
export class CreateRegisterDto {
 @IsUUID() commandId!:string;
 @Matches(/^[A-Z0-9_-]{1,30}$/) code!:string;
}
export class CollectPaymentDto {
 @IsUUID() commandId!:string;
 @IsUUID() saleId!:string;
 @IsUUID() cashSessionId!:string;
 @IsIn(['cash','card']) method!:'cash'|'card';
 @IsIn(['manual','simulated']) mode!:'manual'|'simulated';
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) amountUsd!:string;
 @IsIn(['confirmed','declined','unknown']) outcome!:'confirmed'|'declined'|'unknown';
 @IsOptional() @IsString() @MaxLength(200) evidenceReference?:string;
}
export class ResolvePaymentDto {
 @IsUUID() commandId!:string;
 @IsIn(['confirmed','declined']) outcome!:'confirmed'|'declined';
 @IsString() @MaxLength(200) evidenceReference!:string;
}
export class RequestRefundDto {
 @IsUUID() commandId!:string;
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) amountUsd!:string;
 @IsString() @MaxLength(300) reason!:string;
}
export class RequestAdvanceRefundDto {
 @IsUUID() commandId!:string;
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) amountUsd!:string;
 @IsString() @MaxLength(300) reason!:string;
}
export class RefundPaymentDto {
 @IsUUID() approvalId!:string;
 @IsUUID() commandId!:string;
 @IsUUID() cashSessionId!:string;
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) amountUsd!:string;
 @IsString() @MaxLength(300) reason!:string;
 @IsOptional() @IsString() @MaxLength(200) evidenceReference?:string;
 @IsOptional() @IsUUID() storeReturnId?:string;
}
export class CashMovementDto {
 @IsUUID() commandId!:string;
 @IsIn(['cash_in','withdrawal','deposit']) kind!:'cash_in'|'withdrawal'|'deposit';
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) amountUsd!:string;
 @IsString() @MaxLength(300) reason!:string;
}
export class CloseCashDto {
 @IsUUID() commandId!:string;
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) countedCashUsd!:string;
 @Matches(/^-?(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) settledCardUsd!:string;
 @IsOptional() @IsString() @MaxLength(300) reason?:string;
}
