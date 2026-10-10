import { csvCell } from './csv-cell.js';

export async function serializeReportCsv(
  columns: readonly string[],
  rows: readonly Record<string, unknown>[],
  onProgress?: (completed: number, total: number) => Promise<void>,
): Promise<string> {
  const lines = [columns.map(csvCell).join(',')];
  for (let index = 0; index < rows.length; index += 1) {
    const row = rows[index]!;
    lines.push(columns.map((column) => csvCell(row[column])).join(','));
    if (onProgress && ((index + 1) % 250 === 0 || index === rows.length - 1)) {
      await onProgress(index + 1, rows.length);
      await new Promise<void>((resolve) => setImmediate(resolve));
    }
  }
  if (onProgress && rows.length === 0) await onProgress(0, 0);
  return '\uFEFF' + lines.join('\r\n') + '\r\n';
}
