import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
const source=await readFile(new URL('../src/reports/csv-cell.ts',import.meta.url),'utf8');
const {csvCell}=await import('data:text/javascript;charset=utf-8,'+encodeURIComponent(stripTypeScriptTypes(source)));
test('CSV neutraliza fórmulas aunque haya espacios o salto de línea',()=>{
 for(const input of ['=HYPERLINK("evil")',' +1','\t@payload','\n-1'])
  assert.equal(csvCell(input).startsWith('"\''),true,input);
 assert.equal(csvCell('texto, "citado"'),'"texto, ""citado"""');
 assert.equal(csvCell(null),'""');
});
