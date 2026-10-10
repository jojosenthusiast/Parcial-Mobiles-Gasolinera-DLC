export type FuelTaxRule={code:string;label:string;kind:'percentage'|'fixed_per_liter'|'fixed_per_us_gallon';base:'net'|'net_plus_fixed'|'observed_volume';rate:string};
export function validateFuelTaxPolicy(mode:'included'|'exempt'|'unconfigured',rules:FuelTaxRule[]):boolean;
export function calculateFuelTax(input:{grossUsd:string;quantityL:string;mode:'included'|'exempt'|'unconfigured';rules:FuelTaxRule[]}):{status:string;netUsd:string|null;taxUsd:string|null;components:Array<FuelTaxRule&{taxUsd:string}>};
