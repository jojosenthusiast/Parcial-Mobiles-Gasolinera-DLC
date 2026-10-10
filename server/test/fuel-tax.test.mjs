import test from 'node:test';import assert from 'node:assert/strict';
import {calculateFuelTax,validateFuelTaxPolicy} from '../scripts/fuel-tax.mjs';
// Synthetic arithmetic fixtures. These rates are NOT configured Salvadoran taxes.
const p=(rate='0.10',base='net')=>({code:'TEST_PCT',label:'Test percentage',kind:'percentage',base,rate});
const f=(rate='0.10',kind='fixed_per_liter')=>({code:'TEST_FIXED',label:'Test fixed',kind,base:'observed_volume',rate});
const calc=(rules,grossUsd='11.00',quantityL='10')=>calculateFuelTax({grossUsd,quantityL,mode:'included',rules});
test('included percentage keeps exact cents and reconciles gross',()=>assert.deepEqual(calc([p()]),{status:'configured',netUsd:'10.00',taxUsd:'1.00',components:[{...p(),taxUsd:'1.00'}]}));
test('fixed volume and percentage use the documented base',()=>{
 assert.equal(calc([f(),p()],'12.00').netUsd,'10.00');assert.equal(calc([f(),p()],'12.00').taxUsd,'2.00');
 assert.equal(calc([f(),p('0.10','net_plus_fixed')],'12.10').netUsd,'10.00');
 assert.equal(calc([f(),p('0.10','net_plus_fixed')],'12.10').taxUsd,'2.10');
});
test('US gallons convert exactly; equivalent quantities produce equal tax',()=>{
 assert.equal(calc([f('0.25','fixed_per_us_gallon')],'10.00','3.785411784').taxUsd,'0.25');
 assert.equal(calc([f('0.25','fixed_per_us_gallon')],'10.00','7.570823568').taxUsd,'0.50');
});
test('unknown differs from documented exemption, including zero sale',()=>{
 assert.equal(calculateFuelTax({grossUsd:'0.00',quantityL:'1',mode:'unconfigured',rules:[]}).netUsd,null);
 assert.deepEqual(calculateFuelTax({grossUsd:'10.00',quantityL:'1',mode:'exempt',rules:[]}),{status:'configured',netUsd:'10.00',taxUsd:'0.00',components:[]});
});
test('round components half up, preserve all cents in the resulting net',()=>{
 const x=calc([f('0.005')],'1.00','1');assert.equal(x.taxUsd,'0.01');assert.equal(x.netUsd,'0.99');
 assert.equal(calc([p()],'999999999999.99','1').netUsd,'909090909090.90');
});
test('tax greater than gross, fractional money and invalid volume are rejected',()=>{
 for(const op of [()=>calc([f('2')],'1.00','1'),()=>calc([p()],'1.001','1'),()=>calc([p()],'1.00','0')])assert.throws(op);
});
test('invalid or ambiguous tax policies fail before calculating',()=>{
 for(const rules of [[p('0')],[p('1.01')],[p(),p()],[{...p(),base:'gross'}],[{...f(),base:'net'}],[{...p(),rate:0.1}],[{...p(),surprise:'ignored'}]])assert.throws(()=>calc(rules));
 assert.throws(()=>validateFuelTaxPolicy('included',[]));assert.throws(()=>validateFuelTaxPolicy('exempt',[p()]));
});
