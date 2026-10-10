import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(join(fileURLToPath(new URL('.', import.meta.url)), '..'));
const traceability = await readFile(join(root, 'docs/plan/07_TRAZABILIDAD.md'), 'utf8');
const testPlan = await readFile(join(root, 'docs/plan/06_PRUEBAS_Y_ENTREGA.md'), 'utf8');
const tCases = [...traceability.matchAll(/^\|\s*(T\d{2})\s*\|/gm)].map(match => match[1]);
assert.deepEqual(tCases, Array.from({ length: 40 }, (_, index) => `T${String(index + 1).padStart(2, '0')}`), 'la matriz T01–T40 debe estar completa y ordenada');

for (let number = 41; number <= 50; number += 1) {
  assert.match(traceability, new RegExp(`\\bQA${number}\\b`), `falta el caso QA${number}`);
}
for (let number = 1; number <= 12; number += 1) {
  const id = `V${String(number).padStart(2, '0')}`;
  assert.match(testPlan, new RegExp(`^${id}:`, 'm'), `falta el vector ${id}`);
}

for (const stage of ['E21', 'E22', 'E23', 'E24']) {
  await access(join(root, `docs/evidence/${stage}.md`));
  await access(join(root, `docs/plan/etapas/${stage}.md`));
}

process.stdout.write('Matriz estructural completa: T01–T40, QA41–QA50, V01–V12 y evidencia E21–E24 presentes.\n');
process.stdout.write('Este chequeo verifica trazabilidad, no ejecuta los escenarios ni sustituye QA de UI, PostgreSQL o Xcode.\n');
