import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration=await readFile(new URL('../../migrations/0084_combined_internal_receipts.sql',import.meta.url),'utf8');
const validationFix=await readFile(new URL('../../migrations/0085_combined_receipt_validation_lock.sql',import.meta.url),'utf8');

test('combined receipt ledger is tenant-scoped, immutable, and backend-only',()=>{
 assert.match(migration,/FOREIGN KEY\(fuel_sale_id,organization_id,branch_id\) REFERENCES sales/);
 assert.match(migration,/FOREIGN KEY\(pos_sale_id,organization_id,branch_id\) REFERENCES sales/);
 assert.match(migration,/UNIQUE\(fuel_sale_id\)[\s\S]*UNIQUE\(pos_sale_id\)/);
 assert.match(migration,/combined_internal_receipt_immutable[\s\S]*prevent_inventory_movement_mutation/);
 assert.match(migration,/ALTER TABLE combined_internal_receipts ENABLE ROW LEVEL SECURITY/);
 assert.match(migration,/GRANT SELECT,INSERT ON combined_internal_receipts TO dlc_api_runtime/);
});

test('receipt creation serializes against collections and rejects prior payment/advance activity',()=>{
 assert.match(validationFix,/sale-collection:'\|\|locked_sale_id::text/);
 assert.match(validationFix,/payment_attempts pa WHERE pa\.sale_id IN/);
 assert.match(validationFix,/prepayment_allocations allocation WHERE allocation\.sale_id=/);
 assert.match(validationFix,/prepayment_advances advance WHERE advance\.authorization_id=/);
 assert.match(migration,/FROM payment_attempts WHERE sale_id IN/);
 assert.match(migration,/FROM prepayment_allocations WHERE sale_id=NEW\.fuel_sale_id/);
 assert.match(migration,/FROM prepayment_advances WHERE authorization_id=fuel\.authorization_id/);
 assert.match(migration,/sale_collection_balances WHERE id IN[\s\S]*collection_status<>'pending_collection'/);
 assert.match(migration,/JOIN sale_lines l ON l\.id=r\.sale_line_id WHERE l\.sale_id=NEW\.pos_sale_id/);
 assert.match(migration,/fuel\.authorization_id IS NULL OR pos\.authorization_id IS NOT NULL/);
 assert.match(migration,/combined_receipt_credit_guard BEFORE INSERT ON commercial_credit_charges/);
 assert.match(migration,/combined_receipt_advance_guard BEFORE INSERT ON prepayment_advances/);
});
