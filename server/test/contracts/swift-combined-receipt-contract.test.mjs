import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root=new URL('../../../DLCGasolineras/',import.meta.url);
const [api,viewModel,view,pumps]=await Promise.all([
 readFile(new URL('Services/RemoteAPIClient.swift',root),'utf8'),
 readFile(new URL('ViewModels/RemotePOSViewModel.swift',root),'utf8'),
 readFile(new URL('Views/BranchManager/RemotePOSViews.swift',root),'utf8'),
 readFile(new URL('Views/BranchManager/PumpsOverviewView.swift',root),'utf8')
]);

test('mobile can create and recover combined receipts without merging payment or tax state',()=>{
 assert.match(api,/sales\/combined-receipts/);
 assert.match(api,/sales\/\\\(saleId\.uuidString\.lowercased\(\)\)\/combined-receipt/);
 assert.match(viewModel,/resource: "combined-receipt-command"/);
 assert.ok(viewModel.indexOf('store.saveDraft(RemoteDraft(scope: scope, resource: "combined-receipt-command"') < viewModel.indexOf('return await execute(body)'));
 assert.match(viewModel,/body\.commandId == draft\.id/);
 assert.match(view,/No es comprobante fiscal/);
 assert.match(view,/Los cobros e impuestos se conservan por venta/);
 assert.match(pumps,/Ver desglose y estado por venta/);
});
