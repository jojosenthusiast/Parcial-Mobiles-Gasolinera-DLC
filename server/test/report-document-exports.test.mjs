import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

function stripTypeScriptTypes(value) {
  return value
    .replace(/^type ReportRow =.*\r?\n/gm, '')
    .replace(/^export interface ReportDocument \{[\s\S]*?^}\r?\n/gm, '')
    .replace(/onProgress\?: \(completed: number, total: number\) => Promise<void>/g, 'onProgress')
    .replace(/: (?:ReadonlyArray<readonly \[string, string\]>|readonly ReportRow\[\]|readonly unknown\[\]|readonly string\[\]|string\[\]\[\]|string\[\]|Buffer\[\]|Promise<Buffer>|ReportDocument|unknown|string|number|Uint8Array|Buffer)\s*(?=[,)=;{])/g, '')
    .replace(/Promise<void>/g, 'Promise')
    .replace(/(?<=\])!/g, '');
}

const source = await readFile(new URL('../src/reports/export-documents.ts', import.meta.url), 'utf8');
const module = await import(`data:text/javascript;charset=utf-8,${encodeURIComponent(stripTypeScriptTypes(source))}`);
const document = { title: 'Ventas de combustible', period: '2026-10-01 a 2026-10-07', asOf: '2026-10-07T16:00:00Z',
  sourceWatermark: null, timezone: 'America/El_Salvador', rowCount: 1, columns: ['id', 'fuelName', 'amount'] };
const rows = [{ id: 'S-1', fuelName: 'Súper & Regular <especial>', amount: '=HYPERLINK("x")' }];

function readStoredZipEntries(zip) {
  const files = new Map();
  let offset = 0;
  while (zip.readUInt32LE(offset) === 0x04034b50) {
    const method = zip.readUInt16LE(offset + 8);
    const size = zip.readUInt32LE(offset + 18);
    const nameLength = zip.readUInt16LE(offset + 26);
    const extraLength = zip.readUInt16LE(offset + 28);
    const nameStart = offset + 30;
    const name = zip.subarray(nameStart, nameStart + nameLength).toString('utf8');
    const dataStart = nameStart + nameLength + extraLength;
    assert.equal(method, 0, 'XLSX parts are stored uncompressed');
    files.set(name, zip.subarray(dataStart, dataStart + size).toString('utf8'));
    offset = dataStart + size;
  }
  assert.equal(zip.readUInt32LE(offset), 0x02014b50, 'central directory signature');
  assert.equal(zip.readUInt32LE(zip.length - 22), 0x06054b50, 'end of central directory signature');
  return files;
}

test('XLSX es un paquete OpenXML válido y exporta contenido como texto, sin fórmulas', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'dlc-xlsx-'));
  try {
    const path = join(dir, 'report.xlsx');
    const bytes = await module.serializeReportXlsx(document, rows);
    await writeFile(path, bytes);
    const files = readStoredZipEntries(bytes);
    assert.equal(files.size, 5);
    const worksheet = files.get('xl/worksheets/sheet1.xml');
    assert.ok(worksheet);
    assert.match(worksheet, /Súper &amp; Regular &lt;especial&gt;/);
    assert.match(worksheet, /<c r="C9" t="inlineStr">/);
    assert.match(worksheet, /=HYPERLINK\(&quot;x&quot;\)/);
    assert.doesNotMatch(worksheet, /<f>/);
    assert.match(worksheet, /autoFilter ref="A8:C9"/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('XLSX serializa números como celdas numéricas y PDF conserva diacríticos', async () => {
  const numericRows = [{ ...rows[0], amount: 12.25 }];
  const workbook = await module.serializeReportXlsx(document, numericRows);
  const worksheet = readStoredZipEntries(workbook).get('xl/worksheets/sheet1.xml');
  assert.ok(worksheet);
  assert.match(worksheet, /<c r="C9"><v>12\.25<\/v><\/c>/);
  assert.doesNotMatch(worksheet, /<c r="C9" t="inlineStr">/);

  const pdf = await module.serializeReportPdf(document, numericRows);
  assert.match(pdf.toString('latin1'), /Súper & Regular <especial> \| 12\.25/);
});

test('PDF divide un reporte largo en varias páginas', async () => {
  const manyRows = Array.from({ length: 120 }, (_, index) => ({ id: `S-${index + 1}`, fuelName: 'Regular', amount: '1.00' }));
  const pdf = (await module.serializeReportPdf({ ...document, rowCount: manyRows.length }, manyRows)).toString('ascii');
  assert.equal((pdf.match(/\/Type \/Page \/Parent/g) ?? []).length, 3);
});

test('XLSX y PDF conservan el total de 10 000 filas de un reporte', async () => {
  const manyRows = Array.from({ length: 10_000 }, (_, index) => ({ id: `R-${index + 1}`, fuelName: 'Diésel', amount: '12.25' }));
  const bigDocument = { ...document, rowCount: manyRows.length };
  const workbook = await module.serializeReportXlsx(bigDocument, manyRows);
  const sheet = readStoredZipEntries(workbook).get('xl/worksheets/sheet1.xml');
  assert.ok(sheet);
  assert.match(sheet, /r="A10008" t="inlineStr"><is><t xml:space="preserve">R-10000/);
  assert.equal((sheet.match(/<row r=/g) ?? []).length, 10_007);
  const pdf = (await module.serializeReportPdf(bigDocument, manyRows)).toString('ascii');
  assert.match(pdf, /R-10000/);
  assert.equal((pdf.match(/\/Type \/Page \/Parent/g) ?? []).length, 186);
});

test('PDF se puede leer y declara páginas y texto del reporte', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'dlc-pdf-'));
  try {
    const path = join(dir, 'report.pdf');
    const pdf = await module.serializeReportPdf(document, rows);
    await writeFile(path, pdf);
    assert.equal(pdf.subarray(0, 8).toString('ascii'), '%PDF-1.4');
    assert.match(pdf.toString('ascii'), /%%EOF\n$/);
    const source = pdf.toString('ascii');
    const xref = source.slice(source.indexOf('xref\n'));
    const offsets = xref.match(/\n\d{10} 00000 n /g);
    assert.equal(offsets?.length, (source.match(/\d+ 0 obj/g) ?? []).length);
    assert.match(source, /\/MediaBox \[0 0 612 792\]/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('XLSX y PDF informan progreso por filas y completan la instantánea', async () => {
  const manyRows = Array.from({ length: 501 }, (_, index) => ({ id: `R-${index + 1}`, fuelName: 'Regular', amount: '1' }));
  const progress = [];
  await module.serializeReportXlsx({ ...document, rowCount: manyRows.length }, manyRows,
    async (completed, total) => progress.push([completed, total]));
  assert.deepEqual(progress, [[250, 501], [500, 501], [501, 501]]);
  progress.length = 0;
  await module.serializeReportPdf({ ...document, rowCount: manyRows.length }, manyRows,
    async (completed, total) => progress.push([completed, total]));
  assert.deepEqual(progress, [[250, 501], [500, 501], [501, 501]]);
});
