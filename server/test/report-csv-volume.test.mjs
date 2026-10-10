import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const cellSource = await readFile(new URL('../src/reports/csv-cell.ts', import.meta.url), 'utf8');
const reportSource = await readFile(new URL('../src/reports/csv-report.ts', import.meta.url), 'utf8');
const cellModule = await import(`data:text/javascript;charset=utf-8,${encodeURIComponent(stripTypeScriptTypes(cellSource))}`);
const reportModuleSource = stripTypeScriptTypes(reportSource).replace("'./csv-cell.js'", `"data:text/javascript;charset=utf-8,${encodeURIComponent(stripTypeScriptTypes(cellSource))}"`);
const { serializeReportCsv } = await import(`data:text/javascript;charset=utf-8,${encodeURIComponent(reportModuleSource)}`);

test('CSV serializa el máximo de 10 000 filas del snapshot sin truncar ni desordenar', async () => {
  const rows = Array.from({ length: 10_000 }, (_, index) => ({ id: `R-${index + 1}`, value: index + 1 }));
  const csv = await serializeReportCsv(['id', 'value'], rows);
  const lines = csv.slice(1).split('\r\n');
  assert.equal(lines.length, 10_002); // cabecera, 10 000 filas y terminador
  assert.equal(lines[1], '"R-1","1"');
  assert.equal(lines[10_000], '"R-10000","10000"');
  assert.equal(lines.at(-1), '');
  assert.ok(csv.startsWith('\uFEFF"id","value"\r\n'));
});

test('CSV escapa Unicode, saltos de línea, comillas y neutraliza fórmula en 10 000 filas', async () => {
  const rows = Array.from({ length: 10_000 }, (_, index) => ({
    name: index === 9_999 ? 'Combustible Súper, "DLC"\nOriente' : `Sucursal ${index + 1}`,
    note: index === 9_998 ? '\t=HYPERLINK("https://example.invalid")' : null,
  }));
  const csv = await serializeReportCsv(['name', 'note'], rows);
  assert.ok(csv.includes('"Combustible Súper, ""DLC""\nOriente"'));
  assert.ok(csv.includes('"\'\t=HYPERLINK(""https://example.invalid"")"'));
  assert.equal(csv.match(/\r\n/g).length, 10_001);
  assert.equal(typeof cellModule.csvCell, 'function');
});

test('CSV notifica avance en bloques y termina exactamente en el total', async () => {
  const rows = Array.from({ length: 501 }, (_, index) => ({ id: String(index) }));
  const progress = [];
  await serializeReportCsv(['id'], rows, async (completed, total) => progress.push([completed, total]));
  assert.deepEqual(progress, [[250, 501], [500, 501], [501, 501]]);
});
