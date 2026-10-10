// Exact rational arithmetic; decimal strings enter/leave the API, never binary money.
const MODES=['included','exempt','unconfigured'];
const DECIMAL=/^(?:0|[1-9]\d{0,15})(?:\.\d{1,12})?$/;
function fraction(value){
 if(typeof value!=='string'||!DECIMAL.test(value))throw new Error('Importe o tasa decimal no válida.');
 const [whole,tail='']=value.split('.');return [BigInt(whole+tail),10n**BigInt(tail.length)];
}
const add=(a,b)=>[a[0]*b[1]+b[0]*a[1],a[1]*b[1]];
const sub=(a,b)=>[a[0]*b[1]-b[0]*a[1],a[1]*b[1]];
const mul=(a,b)=>[a[0]*b[0],a[1]*b[1]];
const div=(a,b)=>[a[0]*b[1],a[1]*b[0]];
function cents(a){if(a[0]<0n||a[1]<=0n)throw new Error('La regla fiscal produce un importe negativo.');return (a[0]*100n*2n+a[1])/(a[1]*2n);}
const money=n=>`${n/100n}.${String(n%100n).padStart(2,'0')}`;
export function validateFuelTaxPolicy(mode,rules){
 if(!MODES.includes(mode)||!Array.isArray(rules)||rules.length>8)throw new Error('Política fiscal no válida.');
 if((mode==='included')!==(rules.length>0))throw new Error('Incluido requiere componentes; exento o pendiente no admite componentes.');
 const codes=new Set();
 for(const r of rules){
  if(!r||typeof r!=='object'||Array.isArray(r)||Object.keys(r).sort().join(',')!=='base,code,kind,label,rate')throw new Error('Componente fiscal no válido.');
  if(typeof r.code!=='string'||! /^[A-Z][A-Z0-9_]{0,23}$/.test(r.code)||codes.has(r.code))throw new Error('Código fiscal duplicado o no válido.');
  codes.add(r.code);
  if(typeof r.label!=='string'||!r.label.trim()||r.label.length>120)throw new Error('Indica el nombre del componente fiscal.');
  if(typeof r.rate!=='string'||!/^(?:0|[1-9]\d{0,11})(?:\.\d{1,12})?$/.test(r.rate))throw new Error('Tasa fiscal no válida.');
  const rate=fraction(r.rate);if(rate[0]<=0n)throw new Error('La tasa debe ser positiva.');
  if(r.kind==='percentage'){
   if(!['net','net_plus_fixed'].includes(r.base)||rate[0]>rate[1])throw new Error('Porcentaje o base no válidos.');
  }else if(!['fixed_per_liter','fixed_per_us_gallon'].includes(r.kind)||r.base!=='observed_volume')throw new Error('Tipo o base de componente no válidos.');
 }
 return true;
}
export function calculateFuelTax({grossUsd,quantityL,mode,rules}){
 validateFuelTaxPolicy(mode,rules);const gross=fraction(grossUsd),liters=fraction(quantityL);
 if(liters[0]<=0n||gross[0]*100n%gross[1]!==0n)throw new Error('Volumen positivo e importe en centavos son obligatorios.');
 if(mode==='unconfigured')return {status:'unconfigured',netUsd:null,taxUsd:null,components:[]};
 if(mode==='exempt')return {status:'configured',netUsd:money(cents(gross)),taxUsd:'0.00',components:[]};
 let fixed=[0n,1n],allRates=[0n,1n],fixedRates=[0n,1n];
 for(const r of rules){const rate=fraction(r.rate);
  if(r.kind==='percentage'){allRates=add(allRates,rate);if(r.base==='net_plus_fixed')fixedRates=add(fixedRates,rate);}
  else fixed=add(fixed,mul(r.kind==='fixed_per_liter'?liters:div(liters,fraction('3.785411784')),rate));
 }
 const net=div(sub(gross,mul(fixed,add([1n,1n],fixedRates))),add([1n,1n],allRates));
 if(net[0]<0n)throw new Error('Los componentes fijos superan el importe vendido.');
 let taxCents=0n;
 const components=rules.map(r=>{
  const base=r.kind==='percentage'?(r.base==='net_plus_fixed'?add(net,fixed):net):r.kind==='fixed_per_liter'?liters:div(liters,fraction('3.785411784'));
  const amount=cents(mul(base,fraction(r.rate)));taxCents+=amount;return {...r,taxUsd:money(amount)};
 });
 const netCents=cents(gross)-taxCents;if(netCents<0n)throw new Error('El redondeo fiscal supera el importe vendido.');
 return {status:'configured',netUsd:money(netCents),taxUsd:money(taxCents),components};
}
