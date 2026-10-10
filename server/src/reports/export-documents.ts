type ReportRow = Record<string, unknown>;

export interface ReportDocument {
  title: string;
  period: string;
  asOf: Date | string;
  sourceWatermark: Date | string | null;
  timezone: string;
  rowCount: number;
  columns: readonly string[];
}

function display(value: unknown): string {
  if (value === null || value === undefined) return '';
  return typeof value === 'object' ? JSON.stringify(value) : String(value);
}

function xml(value: unknown): string {
  // XML 1.0 cannot represent these code points; replace them before serialization.
  // eslint-disable-next-line no-control-regex
  return display(value).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/g, '\uFFFD')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}

function columnName(index: number): string {
  let value = index + 1;
  let result = '';
  while (value > 0) {
    value -= 1;
    result = String.fromCharCode(65 + value % 26) + result;
    value = Math.floor(value / 26);
  }
  return result;
}

function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function zip(files: ReadonlyArray<readonly [string, string]>): Buffer {
  const local: Buffer[] = [];
  const central: Buffer[] = [];
  let offset = 0;
  for (const [path, content] of files) {
    const name = Buffer.from(path, 'utf8');
    const data = Buffer.from(content, 'utf8');
    const checksum = crc32(data);
    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50, 0); header.writeUInt16LE(20, 4); header.writeUInt16LE(0, 6);
    header.writeUInt16LE(0, 8); header.writeUInt16LE(0, 10); header.writeUInt16LE(0x21, 12);
    header.writeUInt32LE(checksum, 14); header.writeUInt32LE(data.length, 18); header.writeUInt32LE(data.length, 22);
    header.writeUInt16LE(name.length, 26); header.writeUInt16LE(0, 28);
    local.push(header, name, data);
    const directory = Buffer.alloc(46);
    directory.writeUInt32LE(0x02014b50, 0); directory.writeUInt16LE(20, 4); directory.writeUInt16LE(20, 6);
    directory.writeUInt16LE(0, 8); directory.writeUInt16LE(0, 10); directory.writeUInt16LE(0, 12);
    directory.writeUInt16LE(0x21, 14); directory.writeUInt32LE(checksum, 16);
    directory.writeUInt32LE(data.length, 20); directory.writeUInt32LE(data.length, 24);
    directory.writeUInt16LE(name.length, 28); directory.writeUInt16LE(0, 30); directory.writeUInt16LE(0, 32);
    directory.writeUInt16LE(0, 34); directory.writeUInt16LE(0, 36); directory.writeUInt32LE(0, 38);
    directory.writeUInt32LE(offset, 42);
    central.push(directory, name);
    offset += header.length + name.length + data.length;
  }
  const directorySize = central.reduce((sum, item) => sum + item.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(0, 4); end.writeUInt16LE(0, 6);
  end.writeUInt16LE(files.length, 8); end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(directorySize, 12); end.writeUInt32LE(offset, 16); end.writeUInt16LE(0, 20);
  return Buffer.concat([...local, ...central, end]);
}

export async function serializeReportXlsx(
  document: ReportDocument,
  rows: readonly ReportRow[],
  onProgress?: (completed: number, total: number) => Promise<void>,
): Promise<Buffer> {
  const sheetRows: string[] = [];
  const addRow = (rowNumber: number, values: readonly unknown[]) => {
    const cells = values.map((value, index) => {
      const reference = `${columnName(index)}${rowNumber}`;
      if (typeof value === 'number' && Number.isFinite(value)) return `<c r="${reference}"><v>${value}</v></c>`;
      return `<c r="${reference}" t="inlineStr"><is><t xml:space="preserve">${xml(value)}</t></is></c>`;
    }).join('');
    sheetRows.push(`<row r="${rowNumber}">${cells}</row>`);
  };
  addRow(1, ['Reporte', document.title]);
  addRow(2, ['Periodo', document.period]);
  addRow(3, ['Generado', document.asOf]);
  addRow(4, ['Zona horaria', document.timezone]);
  addRow(5, ['Último dato fuente', document.sourceWatermark ?? 'Sin registros']);
  addRow(6, ['Registros', document.rowCount]);
  addRow(8, document.columns);
  for (let index = 0; index < rows.length; index += 1) {
    const row = rows[index]!;
    addRow(index + 9, document.columns.map((column) => row[column]));
    if (onProgress && ((index + 1) % 250 === 0 || index === rows.length - 1)) {
      await onProgress(index + 1, rows.length);
      await new Promise<void>((resolve) => setImmediate(resolve));
    }
  }
  const sheet = `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="8" topLeftCell="A9" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetData>${sheetRows.join('')}</sheetData><autoFilter ref="A8:${columnName(Math.max(0, document.columns.length - 1))}${Math.max(8, rows.length + 8)}"/></worksheet>`;
  const workbook = zip([
    ['[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'],
    ['_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'],
    ['xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Reporte" sheetId="1" r:id="rId1"/></sheets></workbook>'],
    ['xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'],
    ['xl/worksheets/sheet1.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>${sheet}`],
  ]);
  if (onProgress && rows.length === 0) await onProgress(0, 0);
  return workbook;
}

const pdfWinAnsiExtras = new Map([
  ['€', '\x80'], ['‚', '\x82'], ['ƒ', '\x83'], ['„', '\x84'], ['…', '\x85'], ['†', '\x86'], ['‡', '\x87'],
  ['ˆ', '\x88'], ['‰', '\x89'], ['Š', '\x8A'], ['‹', '\x8B'], ['Œ', '\x8C'], ['Ž', '\x8E'], ['‘', '\x91'],
  ['’', '\x92'], ['“', '\x93'], ['”', '\x94'], ['•', '\x95'], ['–', '\x96'], ['—', '\x97'], ['˜', '\x98'],
  ['™', '\x99'], ['š', '\x9A'], ['›', '\x9B'], ['œ', '\x9C'], ['ž', '\x9E'], ['Ÿ', '\x9F'],
]);

function pdfWinAnsi(value: unknown): string {
  return display(value).normalize('NFC').replace(/[€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]/g, (character) => pdfWinAnsiExtras.get(character) ?? '?')
    .replace(/[^\x20-\xFF]/g, '?');
}

function pdfEscape(value: string): string { return value.replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)'); }

export async function serializeReportPdf(
  document: ReportDocument,
  rows: readonly ReportRow[],
  onProgress?: (completed: number, total: number) => Promise<void>,
): Promise<Buffer> {
  const textLines = [pdfWinAnsi(document.title), `Periodo: ${pdfWinAnsi(document.period)}`, `Generado: ${pdfWinAnsi(document.asOf)} (${pdfWinAnsi(document.timezone)})`,
    `Ultimo dato fuente: ${document.sourceWatermark ? pdfWinAnsi(document.sourceWatermark) : 'Sin registros'}`,
    `Registros: ${document.rowCount}`, '', document.columns.map((column) => pdfWinAnsi(column)).join(' | ')];
  for (let index = 0; index < rows.length; index += 1) {
    const row = rows[index]!;
    const line = document.columns.map((column) => pdfWinAnsi(row[column])).join(' | ');
    for (let start = 0; start < Math.max(1, line.length); start += 100) textLines.push(line.slice(start, start + 100));
    if (onProgress && ((index + 1) % 250 === 0 || index === rows.length - 1)) {
      await onProgress(index + 1, rows.length);
      await new Promise<void>((resolve) => setImmediate(resolve));
    }
  }
  const pages: string[][] = [];
  for (let index = 0; index < textLines.length; index += 54) pages.push(textLines.slice(index, index + 54));
  const objects: string[] = [];
  const pageIDs = pages.map((_, index) => 4 + index * 2);
  objects.push('<< /Type /Catalog /Pages 2 0 R >>');
  objects.push(`<< /Type /Pages /Kids [${pageIDs.map((id) => `${id} 0 R`).join(' ')}] /Count ${pages.length} >>`);
  objects.push('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  pages.forEach((lines, index) => {
    const pageID = 4 + index * 2;
    const contentID = pageID + 1;
    const content = ['BT', '/F1 9 Tf', '42 750 Td', '12 TL', ...lines.flatMap((line) => [`(${pdfEscape(line)}) Tj`, 'T*']), 'ET'].join('\n');
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${contentID} 0 R >>`);
    objects.push(`<< /Length ${Buffer.byteLength(content, 'latin1')} >>\nstream\n${content}\nendstream`);
  });
  let pdf = '%PDF-1.4\n%DLCR\n';
  const offsets = [0];
  objects.forEach((object, index) => { offsets.push(Buffer.byteLength(pdf, 'latin1')); pdf += `${index + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = Buffer.byteLength(pdf, 'latin1');
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets.slice(1)) pdf += `${String(offset).padStart(10, '0')} 00000 n \n`;
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  if (onProgress && rows.length === 0) await onProgress(0, 0);
  return Buffer.from(pdf, 'latin1');
}

export async function serializeReceiptPdf(lines: readonly string[]): Promise<Buffer> {
  const textLines = lines.flatMap((line) => {
    const value = pdfWinAnsi(line);
    return Array.from({ length: Math.max(1, Math.ceil(value.length / 42)) }, (_, index) => value.slice(index * 42, (index + 1) * 42));
  });
  const pages: string[][] = [];
  for (let index = 0; index < textLines.length; index += 48) pages.push(textLines.slice(index, index + 48));
  const objects: string[] = [];
  const pageIDs = pages.map((_, index) => 4 + index * 2);
  objects.push('<< /Type /Catalog /Pages 2 0 R >>');
  objects.push(`<< /Type /Pages /Kids [${pageIDs.map((id) => `${id} 0 R`).join(' ')}] /Count ${pages.length} >>`);
  objects.push('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  pages.forEach((page, index) => {
    const pageID = 4 + index * 2;
    const contentID = pageID + 1;
    const content = ['BT', '/F1 9 Tf', '18 770 Td', '12 TL', ...page.flatMap((line) => [`(${pdfEscape(line)}) Tj`, 'T*']), 'ET'].join('\n');
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 800] /Resources << /Font << /F1 3 0 R >> >> /Contents ${contentID} 0 R >>`);
    objects.push(`<< /Length ${Buffer.byteLength(content, 'latin1')} >>\nstream\n${content}\nendstream`);
  });
  let pdf = '%PDF-1.4\n%DLCR\n';
  const offsets = [0];
  objects.forEach((object, index) => { offsets.push(Buffer.byteLength(pdf, 'latin1')); pdf += `${index + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = Buffer.byteLength(pdf, 'latin1');
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets.slice(1)) pdf += `${String(offset).padStart(10, '0')} 00000 n \n`;
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(pdf, 'latin1');
}
