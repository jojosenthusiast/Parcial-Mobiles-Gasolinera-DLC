import { deflateRawSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { mkdir, readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(join(fileURLToPath(new URL('.', import.meta.url)), '..'));
const outputArg = process.argv.indexOf('--output');
if (outputArg >= 0 && (!process.argv[outputArg + 1] || process.argv[outputArg + 1].startsWith('--'))) {
  throw new Error('Usa --output seguido de una ruta de archivo ZIP.');
}
const output = resolve(outputArg >= 0 ? process.argv[outputArg + 1] : join(root, 'artifacts', 'DLCGasolineras_Laboratorio22_source.zip'));
const checksumOutput = `${output}.sha256`;
const excludedDirectories = new Set(['.git', '.svn', '.hg', 'node_modules', '.dart_tool', '.gradle', 'dist', 'DerivedData', '.build', 'build', 'xcuserdata', 'artifacts', 'backups']);
const excludedFiles = /^(?:\.env(?:\..*)?|.*\.(?:p12|pfx|mobileprovision|key|dump|dump\.enc|log)|\.DS_Store|.*\.xcuserstate)$/i;
const localWindowsCachePath = /^(?:%SystemDrive%\/ProgramData\/Microsoft\/Windows\/Caches(?:\/|$)|flutter\/apps\/[^/]+\/%SystemDrive%\/ProgramData\/Microsoft\/Windows\/Caches(?:\/|$))/i;
const files = [];

await import('./verify-release.mjs');
if (process.exitCode) throw new Error('La verificación de fuente falló; no se generó el ZIP.');

async function walk(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    const relativePath = relative(root, path).replaceAll('\\', '/');
    if (resolve(path) === output || resolve(path) === checksumOutput) continue;
    if (entry.isDirectory()) {
      if (localWindowsCachePath.test(`${relativePath}/`)) continue;
      if (!excludedDirectories.has(entry.name)) await walk(path);
    } else if (entry.isFile() && !localWindowsCachePath.test(relativePath) && !excludedFiles.test(entry.name) && /^\.env\.(?:example|template)$/i.test(entry.name) === false) {
      files.push(path);
    } else if (entry.isFile() && excludedFiles.test(entry.name) && /^\.env\.(?:example|template)$/i.test(entry.name)) {
      files.push(path);
    }
  }
}
await walk(root);
files.sort((a, b) => relative(root, a).localeCompare(relative(root, b), 'en'));

const crcTable = new Uint32Array(256);
for (let n = 0; n < 256; n += 1) {
  let value = n;
  for (let bit = 0; bit < 8; bit += 1) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  crcTable[n] = value >>> 0;
}
function crc32(buffer) {
  let value = 0xffffffff;
  for (const byte of buffer) value = crcTable[(value ^ byte) & 0xff] ^ (value >>> 8);
  return (value ^ 0xffffffff) >>> 0;
}
function dosDateTime(date) {
  const year = Math.max(1980, date.getFullYear());
  return { date: ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate(), time: (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2) };
}
function zipEntry(name, body, modified) {
  const nameBytes = Buffer.from(name.replaceAll('\\', '/'), 'utf8');
  const compressed = deflateRawSync(body, { level: 9 });
  if (body.length > 0xffffffff || compressed.length > 0xffffffff) throw new Error(`El archivo excede el límite ZIP32: ${name}`);
  const checksum = crc32(body), { date, time } = dosDateTime(modified);
  const local = Buffer.alloc(30 + nameBytes.length);
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(0x0800, 6);
  local.writeUInt16LE(8, 8); local.writeUInt16LE(time, 10); local.writeUInt16LE(date, 12);
  local.writeUInt32LE(checksum, 14); local.writeUInt32LE(compressed.length, 18); local.writeUInt32LE(body.length, 22);
  local.writeUInt16LE(nameBytes.length, 26); local.writeUInt16LE(0, 28); nameBytes.copy(local, 30);
  const central = Buffer.alloc(46 + nameBytes.length);
  central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
  central.writeUInt16LE(0x0800, 8); central.writeUInt16LE(8, 10); central.writeUInt16LE(time, 12); central.writeUInt16LE(date, 14);
  central.writeUInt32LE(checksum, 16); central.writeUInt32LE(compressed.length, 20); central.writeUInt32LE(body.length, 24);
  central.writeUInt16LE(nameBytes.length, 28); central.writeUInt16LE(0, 30); central.writeUInt16LE(0, 32);
  central.writeUInt16LE(0, 34); central.writeUInt16LE(0, 36); central.writeUInt32LE(0, 38); nameBytes.copy(central, 46);
  return { local, compressed, central };
}

const chunks = [], directory = [];
let offset = 0;
for (const path of files) {
  const body = await readFile(path), modified = (await stat(path)).mtime;
  const entry = zipEntry(relative(root, path), body, modified);
  chunks.push(entry.local, entry.compressed);
  entry.central.writeUInt32LE(offset, 42);
  directory.push(entry.central);
  offset += entry.local.length + entry.compressed.length;
  if (offset > 0xffffffff) throw new Error('El paquete excede el límite ZIP32 de 4 GiB.');
}
const directorySize = directory.reduce((sum, item) => sum + item.length, 0);
const end = Buffer.alloc(22);
end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(0, 4); end.writeUInt16LE(0, 6);
end.writeUInt16LE(directory.length, 8); end.writeUInt16LE(directory.length, 10);
end.writeUInt32LE(directorySize, 12); end.writeUInt32LE(offset, 16); end.writeUInt16LE(0, 20);
chunks.push(...directory, end);

await mkdir(dirname(output), { recursive: true });
const archive = Buffer.concat(chunks);
await writeFile(output, archive, { mode: 0o600 });
const sha256 = createHash('sha256').update(archive).digest('hex');
await writeFile(checksumOutput, `${sha256}  ${basename(output)}\n`, { mode: 0o600 });
process.stdout.write(`ZIP fuente creado: ${output}\nArchivos incluidos: ${files.length}. Node modules, build outputs, .env, claves, respaldos y estado local quedan excluidos.\nLa verificación no certifica compilación Xcode/API ni restore PostgreSQL.\n`);
