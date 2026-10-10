import { IsOptional, IsString, IsUUID, Length, Matches } from 'class-validator';
export class ConfigureServiceDto {
 @IsString() @Length(5,300) workDescription!:string;
 @IsOptional() @IsString() @Length(2,40) taxCode?:string;
}
export class AddServiceMaterialDto {
 @IsUUID() catalogProductId!:string;
 @Matches(/^[1-9][0-9]{0,8}$/) unitsPerService!:string;
}
export class FulfillServiceDto {
 @IsUUID() commandId!:string;
 @IsString() @Length(5,200) workReference!:string;
}
