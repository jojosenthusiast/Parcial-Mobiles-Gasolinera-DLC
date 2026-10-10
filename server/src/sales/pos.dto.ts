import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, MaxLength, Min, ValidateNested } from 'class-validator';
export class PublishPosOfferDto {
 @IsUUID() commandId!: string;
 @IsOptional() @IsUUID() productId?: string;
 @IsOptional() @IsUUID() expectedOfferVersionId?: string;
 @IsString() @MaxLength(40) sku!: string;
 @IsIn(['store','service']) kind!: 'store'|'service';
 @IsBoolean() expiryRequired!: boolean;
 @IsString() @MaxLength(120) description!: string;
 @IsOptional() @IsString() @MaxLength(80) category?: string;
 @IsBoolean() active!: boolean;
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,4})?$/) priceUsd!: string;
 @IsOptional() @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,8})?$/) serviceUnitCostUsd?: string|null;
}
export class ReceivePosLotDto {
 @IsUUID() commandId!: string;
 @IsUUID() productId!: string;
 @IsString() @MaxLength(80) lotCode!: string;
 @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) expiresOn?: string|null;
 @Matches(/^[1-9][0-9]{0,8}$/) quantity!: string;
 @IsOptional() @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,8})?$/) unitCostUsd?: string|null;
 @IsString() @MaxLength(300) sourceReference!: string;
}
export class PosSaleItemDto {
 @IsUUID() productId!: string;
 @IsUUID() offerVersionId!: string;
 @Matches(/^(0|[1-9][0-9]{0,8})(\.[0-9]{1,3})?$/) quantity!: string;
}
export class CreatePosSaleDto {
 @IsUUID() commandId!: string;
 @IsArray() @ArrayMinSize(1) @ArrayMaxSize(50) @ValidateNested({each:true}) @Type(()=>PosSaleItemDto) items!: PosSaleItemDto[];
}
export class ChangeLotConditionDto {
 @IsUUID() commandId!:string;
 @IsIn(['sellable','quarantine']) condition!:'sellable'|'quarantine';
 @IsString() @MaxLength(500) reason!:string;
}
export class DispatchStoreTransferDto {
 @IsUUID() commandId!:string;
 @IsUUID() destinationBranchId!:string;
 @IsUUID() sourceLotId!:string;
 @IsUUID() destinationProductId!:string;
 @Matches(/^[1-9][0-9]{0,8}$/) quantity!:string;
 @IsString() @MaxLength(160) document!:string;
}
export class ReceiveStoreTransferDto {
 @IsUUID() commandId!:string;
 @Matches(/^[1-9][0-9]{0,8}$/) quantity!:string;
 @IsString() @MaxLength(160) document!:string;
}
export class CloseStoreTransferDto {
 @IsUUID() commandId!:string;
 @IsString() @MaxLength(500) reason!:string;
}
export class CaptureStoreCountDto {
 @IsUUID() commandId!:string;
 @IsUUID() lotId!:string;
 @Matches(/^(0|[1-9][0-9]{0,8})$/) observedUnits!:string;
 @IsString() @MaxLength(500) reason!:string;
}
export class ApproveStoreCountDto {
 @IsUUID() commandId!:string;
}
export class AcceptStoreReturnDto {
 @IsUUID() commandId!:string;
 @IsUUID() saleLineId!:string;
 @IsUUID() sourceLotId!:string;
 @Matches(/^[1-9][0-9]{0,8}$/) quantity!:string;
 @IsIn(['sellable','quarantine']) disposition!:'sellable'|'quarantine';
 @IsString() @MaxLength(500) reason!:string;
}
export class UpdateGlobalCatalogDto {
 @IsInt() @Min(1) expectedVersion!:number;
 @IsOptional() @Matches(/^[0-9]{8,14}$/) barcode?:string|null;
 @IsIn(['store','lubricant','part']) kind!:'store'|'lubricant'|'part';
 @IsString() @MaxLength(80) category!:string;
 @IsString() @MaxLength(120) presentation!:string;
 @IsIn(['unit','bottle','liter','case','pack','kg']) unit!:'unit'|'bottle'|'liter'|'case'|'pack'|'kg';
 @IsOptional() @IsString() @MaxLength(40) taxCode?:string|null;
 @IsOptional() @IsUUID() defaultSupplierId?:string|null;
 @IsBoolean() active!:boolean;
}
export class UpdateAssortmentDto {
 @IsBoolean() active!:boolean;
 @IsInt() @Min(0) minStockUnits!:number;
}
export class ClassifyStoreLossDto {
 @IsUUID() commandId!:string;
 @IsIn(['damage','expired','suspected_theft','unexplained']) cause!:'damage'|'expired'|'suspected_theft'|'unexplained';
 @IsString() @MaxLength(500) reason!:string;
}
