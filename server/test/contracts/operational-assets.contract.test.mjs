import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
const root=resolve(import.meta.dirname,'../../..');
const read=path=>readFile(resolve(root,path),'utf8');
const reportTypeMigration = await read('server/migrations/0111_report_run_finalize_operational_assets.sql');
test('operational asset inventory stays connected through API, reports, web and Operations app',async()=>{
 const spec=JSON.parse(await read('contracts/openapi.json'));
 const paths=Object.keys(spec.paths).filter(path=>path.includes('/operational-assets'));
 assert.deepEqual(paths.sort(),['/branches/{branchId}/operational-assets','/branches/{branchId}/operational-assets/summary','/branches/{branchId}/operational-assets/{assetId}','/branches/{branchId}/operational-assets/{assetId}/assignment','/branches/{branchId}/operational-assets/{assetId}/profile','/branches/{branchId}/operational-assets/{assetId}/status','/branches/{branchId}/operational-assets/{assetId}/transfer'].sort());
 assert.ok(spec.components.schemas.CreateOperationalAssetRequest);
 const [web,css,ops,api,service]=await Promise.all([read('web/public/app.js'),read('web/public/styles.css'),read('flutter/apps/dlc_operations/lib/operational_assets_screen.dart'),read('flutter/packages/dlc_api/lib/src/employee_session.dart'),read('server/src/reports/reports.service.ts')]);
 assert.match(web,/operationalAssetsPage/);assert.match(web,/operational_assets/);assert.match(css,/asset-month-chart/);assert.match(ops,/OperationalAssetsScreen/);assert.match(ops,/MediaQuery.disableAnimationsOf/);assert.match(api,/operationalAssetsSummary/);assert.match(service,/operational_assets/);
});

test('operational asset reports remain valid for runs and saved filters', () => {
 assert.match(reportTypeMigration, /report_runs_report_type_check[\s\S]*operational_assets/i);
 assert.match(reportTypeMigration, /saved_report_filters_report_type_check[\s\S]*operational_assets/i);
});