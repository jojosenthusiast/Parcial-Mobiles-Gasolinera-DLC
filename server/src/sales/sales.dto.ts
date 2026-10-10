import { IsUUID } from 'class-validator';
export class CreateFuelSaleDto {
 @IsUUID() commandId!: string;
 @IsUUID() authorizationId!: string;
}

export class CreateCombinedReceiptDto {
 @IsUUID() commandId!: string;
 @IsUUID() fuelSaleId!: string;
 @IsUUID() posSaleId!: string;
}
