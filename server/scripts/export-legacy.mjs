import { mkdir, readFile, writeFile, copyFile, chmod } from 'node:fs/promises';
import { resolve, basename, join } from 'node:path';
import { makeManifest, parseSnapshot } from './legacy-bundle.mjs';

const [inputPath, outputPath, sourceInstallationId] = process.argv.slice(2);
if (!inputPath || !outputPath || !sourceInstallationId) {
  process.stderr.write('Uso: node scripts/export-legacy.mjs <snapshot-v1.json> <carpeta-destino-nueva> <sourceInstallationId-uuid>\n');
  process.exitCode = 2;
} else {
  const source = resolve(inputPath);
  const output = resolve(outputPath);
  const sourceBytes = await readFile(source);
  const snapshot = parseSnapshot(sourceBytes);
  const manifest = makeManifest(snapshot, sourceBytes, sourceInstallationId);
  await mkdir(output, { recursive: false, mode: 0o700 });
  await chmod(output, 0o700);
  await copyFile(source, join(output, 'source.json'));
  await writeFile(join(output, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  await chmod(join(output, 'source.json'), 0o600);
  process.stdout.write(`Paquete creado desde ${basename(source)}; hash ${manifest.sourceSha256}; no se modificó el origen.\n`);
}
