import assert from 'node:assert/strict';
import { readdir, readFile, stat } from 'node:fs/promises';
import { join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(join(fileURLToPath(new URL('.', import.meta.url)), '..'));
const required = [
  'DLCGasolineras.xcodeproj/project.pbxproj',
  'DLCGasolineras/Assets.xcassets/LogoDLC.imageset/logo_dlc.png',
  'DLCGasolineras/Assets.xcassets/LogoLogin.imageset/logo_login.png',
  'contracts/openapi.json',
  'pnpm-lock.yaml',
  'pnpm-workspace.yaml',
  'server/.env.example',
  'server/migrations',
  'server/src/main.ts',
  'web/server.mjs',
  'web/public/index.html',
  'scripts/backup.mjs',
  'scripts/restore-check.mjs',
  'infra/compose.yaml',
  'docs/RELEASE_CHECKLIST.md',
  'docs/COMPILAR_DESDE_WINDOWS.md',
  'docs/plan/00_EMPEZAR_AQUI.md',
  'docs/plan/02_DOMINIO_Y_REGLAS.md',
  'docs/plan/03_API_SEGURIDAD_Y_TRANSACCIONES.md',
  'docs/plan/06_PRUEBAS_Y_ENTREGA.md',
  'docs/plan/07_TRAZABILIDAD.md',
  'docs/plan/ESTADO.json',
  'docs/evidence/E24.md',
];
const forbiddenDirectory = new Set(['.git', '.svn', '.hg', 'node_modules', 'dist', 'DerivedData', '.build', 'build', 'xcuserdata', 'artifacts', 'backups']);
const forbiddenFile = /^(?:\.env(?:\..*)?|.*\.(?:p12|pfx|mobileprovision|key|dump|dump\.enc|log)|\.DS_Store|.*\.xcuserstate)$/i;
const localWindowsCachePath = /^flutter\/apps\/[^/]+\/%SystemDrive%\/ProgramData\/Microsoft\/Windows\/Caches(?:\/|$)/i;
const findings = [];

for (const path of required) {
  try { await stat(join(root, path)); } catch { findings.push(`Falta el archivo o directorio requerido: ${path}`); }
}

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  for (const entry of entries) {
    const absolute = join(directory, entry.name);
    const name = relative(root, absolute).replaceAll('\\', '/');
    if (entry.isDirectory()) {
      if (localWindowsCachePath.test(`${name}/`)) continue;
      if (!forbiddenDirectory.has(entry.name)) await walk(absolute);
      continue;
    }
    if (!entry.isFile()) continue;
    if (localWindowsCachePath.test(name)) continue;
    if (forbiddenFile.test(entry.name) && !/^\.env\.(?:example|template)$/i.test(entry.name)) {
      findings.push(`Archivo local o sensible que no debe entregarse: ${name}`);
      continue;
    }
    if (/\.(?:pem|crt|cer)$/i.test(entry.name)) {
      const contents = await readFile(absolute, 'utf8').catch(() => '');
      if (/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(contents)) findings.push(`Clave privada detectada: ${name}`);
    }
  }
}
await walk(root);

const packageRoot = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
const serverPackage = JSON.parse(await readFile(join(root, 'server/package.json'), 'utf8'));
assert.equal(packageRoot.packageManager, 'pnpm@11.25.0', 'el gestor del paquete raíz debe estar fijado');
assert.equal(serverPackage.type, 'module', 'el backend debe conservar ESM');
assert.ok(serverPackage.scripts?.build && serverPackage.scripts?.['test:unit'] && serverPackage.scripts?.['test:contract'], 'faltan tareas reproducibles del servidor');

const migrations = (await readdir(join(root, 'server/migrations'))).filter(name => /^\d{4}_[a-z0-9_]+\.sql$/.test(name)).sort();
assert.ok(migrations.length >= 2, 'faltan migraciones iniciales');
assert.equal(new Set(migrations).size, migrations.length, 'hay nombres de migración duplicados');
for (let index = 0; index < migrations.length; index += 1) {
  const expected = String(index + 1).padStart(4, '0');
  if (!migrations[index]?.startsWith(`${expected}_`)) findings.push(`Secuencia de migración discontinua en ${expected}`);
}
const contract = JSON.parse(await readFile(join(root, 'contracts/openapi.json'), 'utf8'));
assert.equal(contract.openapi, '3.1.0', 'OpenAPI debe usar versión 3.1.0');
assert.ok(contract.servers.some(server => server.url === '/api/v1'), 'falta la URL base de API versionada');
assert.equal(serverPackage.engines.node, '>=24.15.0 <25', 'la versión de Node del servidor no coincide con el runtime fijado');

if (findings.length) {
  process.stderr.write(`Verificación de paquete fallida (${findings.length}):\n${findings.map(item => `- ${item}`).join('\n')}\n`);
  process.exitCode = 1;
} else {
  process.stdout.write(`Fuente lista para empaquetar: OpenAPI ${contract.openapi}, ${migrations.length} migraciones, estructura Xcode, backend/web, lockfile y ejemplos de entorno.\n`);
  process.stdout.write('Esta verificación no compila Xcode, no ejecuta PostgreSQL ni certifica integraciones físicas.\n');
}
