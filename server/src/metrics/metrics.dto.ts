import { Matches } from 'class-validator';
export class InventoryAlertPolicyDto {
 @Matches(/^(?:[1-9]\d?|0)(?:\.\d{1,2})?$/) warningPercent!:string;
 @Matches(/^(?:[1-9]\d?|0)(?:\.\d{1,2})?$/) criticalPercent!:string;
}
