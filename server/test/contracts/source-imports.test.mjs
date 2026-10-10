import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, access } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../src');
async function files(directory) {
  const result = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const target = join(directory, entry.name);
    if (entry.isDirectory()) result.push(...await files(target));
    else if (entry.name.endsWith('.ts')) result.push(target);
  }
  return result;
}

test('servidor ESM tiene extensiones y destinos locales presentes', async () => {
  const sources = await files(root);
  const errors = [];
  for (const source of sources) {
    const content = await (await import('node:fs/promises')).readFile(source, 'utf8');
    for (const match of content.matchAll(/from\s+['"](\.{1,2}\/[^'"]+)['"]/g)) {
      const specifier = match[1];
      if (specifier.endsWith('.mjs')) {
        try {
          await access(resolve(dirname(source), specifier));
          await access(resolve(dirname(source), `${specifier.slice(0, -4)}.d.mts`));
        }
        catch { errors.push(`${source}: falta implementación o declaración para ${specifier}`); }
      } else if (!specifier.endsWith('.js')) errors.push(`${source}: falta extensión .js en ${specifier}`);
      else {
        try { await access(resolve(dirname(source), `${specifier.slice(0, -3)}.ts`)); }
        catch { errors.push(`${source}: no existe destino ${specifier}`); }
      }
    }
  }
  assert.deepEqual(errors, []);
});
