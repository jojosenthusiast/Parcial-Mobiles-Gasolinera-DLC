import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { makePreview, verifyBundle } from './legacy-bundle.mjs';

const [bundleDir, cutoverAt, outputPath] = process.argv.slice(2);
if (!bundleDir) {
  process.stderr.write('Uso: node scripts/preview-legacy.mjs <carpeta-paquete> [cutoverAt-ISO] [reporte.json]\n');
  process.exitCode = 2;
} else {
  const directory = resolve(bundleDir);
  const manifest = JSON.parse(await readFile(join(directory, 'manifest.json'), 'utf8'));
  const source = await readFile(join(directory, 'source.json'));
  const snapshot = verifyBundle(manifest, source);
  const preview = makePreview(snapshot, manifest, cutoverAt ?? null);
  const output = `${JSON.stringify(preview, null, 2)}\n`;
  if (outputPath) await writeFile(resolve(outputPath), output, { mode: 0o600, flag: 'wx' });
  else process.stdout.write(output);
}
