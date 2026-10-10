import { ArrayMaxSize, ArrayMinSize, IsArray, IsDateString, IsEmail, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, MinLength, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { FuelInventoryCommandDto } from '../inventory/inventory.dto.js';

const pricePattern = /^(?=.*[1-9])(?:0|[1-9]\d{0,7})(?:\.\d{1,8})?$/;
const quantityPattern = /^(?=.*[1-9])(?:0|[1-9]\d{0,11})(?:\.\d{1,12})?$/;

export class SupplierFuelOfferDto {
  @IsUUID() fuelProductId!: string;
  @IsOptional() @IsString() @MaxLength(80) supplierProductCode?: string;
  @IsOptional() @IsString() @Matches(pricePattern) lastQuotedUnitPriceUsd?: string;
  @IsOptional() @IsIn(['liter','us_gallon']) lastQuotedUnit?: 'liter' | 'us_gallon';
  @IsOptional() @IsDateString() quoteValidUntil?: string;
}

export class SupplierCreateDto {
  @IsString() @MinLength(1) @MaxLength(180) legalName!: string;
  @IsOptional() @IsString() @MaxLength(180) displayName?: string;
  @IsOptional() @IsString() @MaxLength(40) taxId?: string;
  @IsOptional() @IsString() @MaxLength(160) contactName?: string;
  @IsOptional() @IsEmail() @MaxLength(254) contactEmail?: string;
  @IsOptional() @IsString() @MaxLength(40) contactPhone?: string;
  @IsOptional() @IsInt() @Min(0) @Max(365) paymentTermsDays?: number;
  @IsOptional() @IsString() @MaxLength(1000) notes?: string;
  @IsOptional() @IsArray() @ArrayMaxSize(100) @ValidateNested({ each: true }) @Type(() => SupplierFuelOfferDto) offers?: SupplierFuelOfferDto[];
}

export class PurchaseOrderLineDto {
  @IsUUID() fuelProductId!: string;
  @IsString() @Matches(quantityPattern) quantity!: string;
  @IsIn(['liter','us_gallon']) unit!: 'liter' | 'us_gallon';
  @IsString() @Matches(pricePattern) agreedUnitPriceUsd!: string;
  @IsOptional() @IsUUID() tankId?: string;
}

export class PurchaseOrderCreateDto {
  @IsUUID() supplierId!: string;
  @IsString() @MinLength(1) @MaxLength(40) orderNumber!: string;
  @IsOptional() @IsDateString() requestedDeliveryAt?: string;
  @IsOptional() @IsString() @MaxLength(1000) notes?: string;
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(50) @ValidateNested({ each: true }) @Type(() => PurchaseOrderLineDto) lines!: PurchaseOrderLineDto[];
}

export class PurchaseOrderDecisionDto {
  @IsInt() @Min(1) @Max(2147483647) expectedVersion!: number;
  @IsOptional() @IsString() @MaxLength(500) reason?: string;
}

export class PurchaseReceiptDto {
  @IsUUID() purchaseOrderLineId!: string;
  @IsUUID() tankId!: string;
  @IsString() @MinLength(1) @MaxLength(120) supplierDeliveryReference!: string;
  @IsOptional() @IsString() @MaxLength(80) compartmentReference?: string;
  @IsString() @MinLength(1) @MaxLength(120) documentReference!: string;
  @IsOptional() @IsString() @Matches(quantityPattern) billedQuantity?: string;
  @ValidateNested() @Type(() => FuelInventoryCommandDto) inventory!: FuelInventoryCommandDto;
}

export class SupplierInvoiceCreateDto {
  @IsString() @MinLength(1) @MaxLength(80) invoiceNumber!: string;
  @IsString() @Matches(/^(?:0|[1-9]\d{0,13})(?:\.\d{1,2})?$/) subtotalUsd!: string;
  @IsOptional() @IsString() @Matches(/^(?:0|[1-9]\d{0,13})(?:\.\d{1,2})?$/) taxUsd?: string;
  @IsString() @Matches(/^(?:0|[1-9]\d{0,13})(?:\.\d{1,2})?$/) totalUsd!: string;
  @IsOptional() @IsDateString() dueAt?: string;
}

export class SupplierPaymentDto {
  @IsUUID() commandId!: string;
  @IsString() @Matches(/^(?=.*[1-9])(?:0|[1-9]\d{0,11})(?:\.\d{1,2})?$/) amountUsd!: string;
  @IsDateString() paidAt!: string;
  @IsIn(['bank_transfer','check','cash','other']) paymentMethod!: 'bank_transfer' | 'check' | 'cash' | 'other';
  @IsOptional() @IsString() @MaxLength(120) externalReference?: string;
}
