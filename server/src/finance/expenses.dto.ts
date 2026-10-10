import { IsIn, IsOptional, IsString, IsUUID, Length, Matches } from 'class-validator';
export class CreateExpenseCategoryDto {
 @Matches(/^[A-Z0-9_]{2,30}$/) code!:string;
 @IsString() @Length(2,100) name!:string;
 @IsIn(['operating','capital','financial']) class!:string;
}
export class CreateExpenseDto {
 @IsUUID() commandId!:string;
 @IsUUID() categoryId!:string;
 @IsString() @Length(2,80) costCenter!:string;
 @IsOptional() @IsUUID() supplierId?:string;
 @IsString() @Length(3,120) invoiceReference!:string;
 @Matches(/^[1-9][0-9]{0,8}(\.[0-9]{1,2})?$/) amountUsd!:string;
 @IsOptional() @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$/) taxUsd?:string;
 @Matches(/^\d{4}-\d{2}-\d{2}$/) incurredOn!:string;
 @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) dueOn?:string;
 @IsIn(['other','maintenance','incident','purchase_fee']) sourceKind!:string;
 @IsOptional() @IsUUID() sourceId?:string;
 @IsString() @Length(10,500) description!:string;
 @IsString() @Length(3,300) evidenceReference!:string;
}
export class DecideExpenseDto {
 @IsUUID() commandId!:string;
 @IsIn(['approved','rejected']) outcome!:string;
 @IsString() @Length(10,500) reason!:string;
}
export class PayExpenseDto {
 @IsUUID() commandId!:string;
 @Matches(/^[1-9][0-9]{0,8}(\.[0-9]{1,2})?$/) amountUsd!:string;
 @IsIn(['cash','bank_reported']) method!:string;
 @IsOptional() @IsUUID() cashSessionId?:string;
 @IsOptional() @IsString() @Length(3,200) evidenceReference?:string;
}
