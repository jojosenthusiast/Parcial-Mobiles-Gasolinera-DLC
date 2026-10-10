import { IsIn, IsOptional, IsString, IsUUID, Length, Matches } from 'class-validator';
export class CreateReportRunDto {
 @IsIn(['closed_cuts','fuel_sales','tank_movements','incidents','purchase_orders','fuel_prices','expenses','cash_closures','store_stock','maintenance_orders','staff_shifts','operational_assets']) type!:'closed_cuts'|'fuel_sales'|'tank_movements'|'incidents'|'purchase_orders'|'fuel_prices'|'expenses'|'cash_closures'|'store_stock'|'maintenance_orders'|'staff_shifts'|'operational_assets';
 @Matches(/^\d{4}-\d{2}-\d{2}$/) from!:string;
 @Matches(/^\d{4}-\d{2}-\d{2}$/) to!:string;
 @IsOptional() @IsUUID() productId?:string;
 @IsOptional() @IsUUID() dispenserId?:string;
 @IsOptional() @IsIn(['full_service','self_service']) serviceMode?:'full_service'|'self_service';
 @IsOptional() @IsIn(['day','fuel','dispenser','service_mode']) groupBy?:'day'|'fuel'|'dispenser'|'service_mode';
 @IsOptional() @Matches(/^[a-z_]{2,40}$/) status?:string;
 @IsUUID() commandId!:string;
}
export class SaveReportFilterDto {
 @IsString() @Length(2,80) name!:string;
 @IsIn(['closed_cuts','fuel_sales','tank_movements','incidents','purchase_orders','fuel_prices','expenses','cash_closures','store_stock','maintenance_orders','staff_shifts','operational_assets']) type!:'closed_cuts'|'fuel_sales'|'tank_movements'|'incidents'|'purchase_orders'|'fuel_prices'|'expenses'|'cash_closures'|'store_stock'|'maintenance_orders'|'staff_shifts'|'operational_assets';
 @Matches(/^\d{4}-\d{2}-\d{2}$/) from!:string;
 @Matches(/^\d{4}-\d{2}-\d{2}$/) to!:string;
 @IsOptional() @IsUUID() productId?:string;
 @IsOptional() @IsUUID() dispenserId?:string;
 @IsOptional() @IsIn(['full_service','self_service']) serviceMode?:'full_service'|'self_service';
 @IsOptional() @IsIn(['day','fuel','dispenser','service_mode']) groupBy?:'day'|'fuel'|'dispenser'|'service_mode';
 @IsOptional() @Matches(/^[a-z_]{2,40}$/) status?:string;
}
export class CreateReportExportDto {
 @IsIn(['csv','xlsx','pdf']) format!: 'csv'|'xlsx'|'pdf';
 @IsUUID() commandId!: string;
}
