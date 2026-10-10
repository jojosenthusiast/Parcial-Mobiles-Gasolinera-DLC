// Generates the one-shot QA tenant bootstrap SQL (to be run by a DB admin, e.g. the
// Supabase SQL editor as `postgres`) and the matching local credentials file.
//
//   node scripts/generate-qa-bootstrap.mjs            first run: new passwords + qa-setup.generated.sql
//   node scripts/generate-qa-bootstrap.mjs --force    regenerate even if credentials already exist
//   node scripts/generate-qa-bootstrap.mjs --rotate   new passwords + qa-rotate-passwords.generated.sql
//
// Outputs (all git-ignored; the SQL contains argon2id hashes, the .txt contains plaintext):
//   server/.qa-credentials.local.txt
//   server/scripts/sql/qa-setup.generated.sql | qa-rotate-passwords.generated.sql
import { createHash, randomInt } from 'node:crypto';
import { existsSync } from 'node:fs';
import { copyFile, mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const serverDir = join(here, '..');
const migrationsDir = join(serverDir, 'migrations');
const sqlDir = join(here, 'sql');
const credentialsPath = join(serverDir, '.qa-credentials.local.txt');
// Same library and options as AuthService / UserAdminService: argon2.hash(x, { type: argon2.argon2id }).
const argon2 = createRequire(join(serverDir, 'package.json'))('argon2');

const args = new Set(process.argv.slice(2));
const rotate = args.has('--rotate');
const force = args.has('--force');

const ORG_ID = '00000000-0000-4000-8000-0000000000a1'; // seed-demo uses ...0001
const ID = {
  gmRole: '00000000-0000-4000-8000-0000000000b1', bmRole: '00000000-0000-4000-8000-0000000000b2',
  gmUser: '00000000-0000-4000-8000-0000000000c1', bmUser: '00000000-0000-4000-8000-0000000000c2',
  svBranch: '00000000-0000-4000-8000-0000000000d1', gtBranch: '00000000-0000-4000-8000-0000000000d2',
  gmAssignment: '00000000-0000-4000-8000-0000000000e1', bmAssignment: '00000000-0000-4000-8000-0000000000e2',
};
const GM = { email: 'qa.gerente.general@dlc-qa.example', name: 'QA Gerente General' };
const BM = { email: 'qa.gerente.sucursal@dlc-qa.example', name: 'QA Gerente Sucursal SV' };
// Network/organization level capabilities a single-branch manager must not hold.
const BRANCH_MANAGER_EXCLUDED = [
  'branch.manage', 'branch.activate', 'user.manage', 'integration.manage', 'audit.read',
  'imports.preview', 'imports.review', 'tax.policy.propose', 'tax.policy.approve',
  'pos.catalog.global.manage', 'promotion.network.manage', 'promotion.network.approve',
  'loyalty.program.approve',
];

const q = value => `'${String(value).replaceAll("'", "''")}'`;

function newPassword() {
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  const groups = Array.from({ length: 4 }, () => Array.from({ length: 6 }, () => alphabet[randomInt(alphabet.length)]).join(''));
  return groups.join('-');
}

async function hashed(password) {
  const hash = await argon2.hash(password, { type: argon2.argon2id });
  if (!hash.startsWith('$argon2id$') || !(await argon2.verify(hash, password))) throw new Error('argon2id self-check failed.');
  return hash;
}

const gmPassword = newPassword();
const bmPassword = newPassword();
const gmHash = await hashed(gmPassword);
const bmHash = await hashed(bmPassword);

if (existsSync(credentialsPath)) {
  if (!rotate && !force) {
    throw new Error('server/.qa-credentials.local.txt already exists. Use --rotate to issue new passwords for existing users, or --force to regenerate the setup SQL.');
  }
  await copyFile(credentialsPath, `${credentialsPath}.bak`);
}
await mkdir(sqlDir, { recursive: true });

let sqlPath;
let sql;
if (rotate) {
  sqlPath = join(sqlDir, 'qa-rotate-passwords.generated.sql');
  const rotateUser = (email, hash) => `UPDATE users SET password_hash = ${q(hash)}, failed_login_count = 0, locked_until = NULL,
  permission_version = permission_version + 1, updated_at = now()
 WHERE organization_id = ${q(ORG_ID)} AND email_normalized = ${q(email)};
UPDATE auth_sessions SET revoked_at = now(), revoke_reason = 'credential_changed'
 WHERE revoked_at IS NULL AND user_id IN (SELECT id FROM users WHERE organization_id = ${q(ORG_ID)} AND email_normalized = ${q(email)});`;
  sql = `-- DLC QA password rotation (generated; contains argon2id hashes; do not commit).
-- Run as a database admin. Revokes the QA users' sessions.
BEGIN;
${rotateUser(GM.email, gmHash)}
${rotateUser(BM.email, bmHash)}
DO $$ BEGIN
  IF (SELECT count(*) FROM users WHERE organization_id = ${q(ORG_ID)} AND email_normalized IN (${q(GM.email)}, ${q(BM.email)})) <> 2 THEN
    RAISE EXCEPTION 'QA users not found; run qa-setup.generated.sql first';
  END IF;
END $$;
COMMIT;
`;
} else {
  sqlPath = join(sqlDir, 'qa-setup.generated.sql');
  const names = (await readdir(migrationsDir)).filter(name => /^\d{4}_[a-z0-9_]+\.sql$/.test(name)).sort();
  const migrationName = names.find(name => name.startsWith('0109_'));
  if (!migrationName) throw new Error('Migration 0109 not found.');
  const prerequisite = names.filter(name => name < migrationName).at(-1);
  // Byte-for-byte what scripts/migrate.mjs hashes: readFile(..., 'utf8') -> sha256 hex.
  const migrationSql = await readFile(join(migrationsDir, migrationName), 'utf8');
  const checksum = createHash('sha256').update(migrationSql).digest('hex');
  const body = migrationSql.replace(/^\s*(BEGIN|COMMIT)\s*;[ \t]*$/gim, '').trim();
  if (/^\s*(BEGIN|COMMIT|ROLLBACK|START\s+TRANSACTION)\b/im.test(body)) throw new Error('Migration 0109 contains transaction control beyond BEGIN/COMMIT; refusing to embed.');
  const bmExcluded = BRANCH_MANAGER_EXCLUDED.map(q).join(', ');
  const branchInsert = (id, code, name, zone, timezone, country) => `INSERT INTO branches (id, organization_id, code, name, zone, timezone, country_code, status, onboarding_data)
VALUES (${q(id)}, ${q(ORG_ID)}, ${q(code)}, ${q(name)}, ${q(zone)}, ${q(timezone)}, ${q(country)}, 'draft',
  jsonb_build_object('identity', jsonb_build_object('code', ${q(code)}, 'name', ${q(name)}, 'zone', ${q(zone)}, 'timezone', ${q(timezone)}, 'countryCode', ${q(country)}),
    'template', 'operational', 'expectedDispenserCount', 6))
ON CONFLICT DO NOTHING;`;
  sql = `-- DLC QA tenant bootstrap (generated by server/scripts/generate-qa-bootstrap.mjs; contains argon2id hashes; do not commit).
-- Run ONCE as a database admin (Supabase SQL editor, role postgres). One transaction, safe to re-run.
-- Applies migration ${migrationName}, records it in schema_migrations, then creates the QA tenant:
--   org ${ORG_ID} | users ${GM.email}, ${BM.email} | branches QA-SV-01, QA-GT-01 (draft)
BEGIN;
SET LOCAL lock_timeout = '15s';
SELECT pg_advisory_xact_lock(hashtext('dlc-schema-migrations'));

DO $$ BEGIN
  IF to_regclass('public.schema_migrations') IS NULL OR NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = ${q(prerequisite)}) THEN
    RAISE EXCEPTION 'Schema is not at ${prerequisite}; apply migrations up to it first.';
  END IF;
END $$;

-- ===== ${migrationName} (BEGIN/COMMIT removed; the whole file is one transaction) =====
${body}
-- ===== end ${migrationName} =====

INSERT INTO schema_migrations (version, checksum) VALUES (${q(migrationName)}, ${q(checksum)})
ON CONFLICT (version) DO NOTHING;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM schema_migrations WHERE version = ${q(migrationName)} AND checksum <> ${q(checksum)}) THEN
    RAISE WARNING '${migrationName} was already recorded with a different checksum; scripts/migrate.mjs will reject it until reconciled.';
  END IF;
END $$;

-- ===== QA tenant =====
INSERT INTO organizations (id, name) VALUES (${q(ORG_ID)}, 'DLC QA') ON CONFLICT DO NOTHING;

-- Roles and role_permissions are per-organization rows (no bypass for the general manager).
INSERT INTO roles (id, organization_id, code, name, managed) VALUES
  (${q(ID.gmRole)}, ${q(ORG_ID)}, 'general_manager', 'Gerente general', true),
  (${q(ID.bmRole)}, ${q(ORG_ID)}, 'branch_manager', 'Gerente de sucursal', true)
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (organization_id, role_id, permission_code)
SELECT r.organization_id, r.id, p.code FROM roles r CROSS JOIN permissions p
 WHERE r.organization_id = ${q(ORG_ID)} AND r.code = 'general_manager'
ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (organization_id, role_id, permission_code)
SELECT r.organization_id, r.id, p.code FROM roles r CROSS JOIN permissions p
 WHERE r.organization_id = ${q(ORG_ID)} AND r.code = 'branch_manager' AND p.code <> ALL (ARRAY[${bmExcluded}])
ON CONFLICT DO NOTHING;

-- Existing accounts are never touched (no password overwrite). employee_id stays NULL: linked
-- employees need an active scheduled work shift to log in (AuthService.hasActiveWorkShift).
INSERT INTO users (id, organization_id, email_normalized, display_name, password_hash, status, must_change_password) VALUES
  (${q(ID.gmUser)}, ${q(ORG_ID)}, ${q(GM.email)}, ${q(GM.name)}, ${q(gmHash)}, 'active', false),
  (${q(ID.bmUser)}, ${q(ORG_ID)}, ${q(BM.email)}, ${q(BM.name)}, ${q(bmHash)}, 'active', false)
ON CONFLICT DO NOTHING;

${branchInsert(ID.svBranch, 'QA-SV-01', 'QA Sucursal El Salvador', 'occidental', 'America/El_Salvador', 'SV')}
${branchInsert(ID.gtBranch, 'QA-GT-01', 'QA Sucursal Guatemala', 'other', 'America/Guatemala', 'GT')}
INSERT INTO branch_operating_profiles (branch_id, organization_id, profile, expected_dispenser_count, updated_by)
SELECT b.id, b.organization_id, 'operational', 6, (SELECT id FROM users WHERE organization_id = ${q(ORG_ID)} AND email_normalized = ${q(GM.email)})
  FROM branches b WHERE b.organization_id = ${q(ORG_ID)} AND b.code IN ('QA-SV-01', 'QA-GT-01')
ON CONFLICT DO NOTHING;

-- Network-wide scope = assignment with branch_id NULL; branch scope = that branch id.
INSERT INTO user_role_assignments (id, organization_id, user_id, role_id, branch_id)
SELECT ${q(ID.gmAssignment)}, u.organization_id, u.id, r.id, NULL
  FROM users u JOIN roles r ON r.organization_id = u.organization_id AND r.code = 'general_manager'
 WHERE u.organization_id = ${q(ORG_ID)} AND u.email_normalized = ${q(GM.email)}
   AND NOT EXISTS (SELECT 1 FROM user_role_assignments a WHERE a.user_id = u.id AND a.role_id = r.id AND a.branch_id IS NULL AND a.valid_until IS NULL)
ON CONFLICT DO NOTHING;
INSERT INTO user_role_assignments (id, organization_id, user_id, role_id, branch_id, assigned_by)
SELECT ${q(ID.bmAssignment)}, u.organization_id, u.id, r.id, b.id,
       (SELECT id FROM users WHERE organization_id = ${q(ORG_ID)} AND email_normalized = ${q(GM.email)})
  FROM users u JOIN roles r ON r.organization_id = u.organization_id AND r.code = 'branch_manager'
  JOIN branches b ON b.organization_id = u.organization_id AND b.code = 'QA-SV-01'
 WHERE u.organization_id = ${q(ORG_ID)} AND u.email_normalized = ${q(BM.email)}
   AND NOT EXISTS (SELECT 1 FROM user_role_assignments a WHERE a.user_id = u.id AND a.role_id = r.id AND a.branch_id = b.id AND a.valid_until IS NULL)
ON CONFLICT DO NOTHING;

-- Result summary (last statement; shown by the SQL editor)
SELECT (SELECT count(*) FROM organizations WHERE id = ${q(ORG_ID)}) AS organizations,
       (SELECT count(*) FROM roles WHERE organization_id = ${q(ORG_ID)}) AS roles,
       (SELECT count(*) FROM role_permissions WHERE organization_id = ${q(ORG_ID)}) AS role_permission_rows,
       (SELECT count(*) FROM users WHERE organization_id = ${q(ORG_ID)}) AS users,
       (SELECT count(*) FROM user_role_assignments WHERE organization_id = ${q(ORG_ID)}) AS assignments,
       (SELECT count(*) FROM branches WHERE organization_id = ${q(ORG_ID)}) AS branches,
       (SELECT count(*) FROM schema_migrations WHERE version = ${q(migrationName)}) AS ledger_0109;

COMMIT;
`;
}

await writeFile(sqlPath, sql, 'utf8');
await writeFile(credentialsPath, `DLC QA credentials (local only; never commit or share in chat)
Generated: ${new Date().toISOString()}
Organization / CUSTOMER_ORGANIZATION_ID: ${ORG_ID}

General Manager (network-wide, all permissions)
  email:    ${GM.email}
  password: ${gmPassword}

Branch Manager (branch QA-SV-01 only)
  email:    ${BM.email}
  password: ${bmPassword}
${rotate ? '\nStatus: ROTATED. Run qa-rotate-passwords.generated.sql as admin for these passwords to take effect.\n' : '\nStatus: run qa-setup.generated.sql as admin; these passwords exist only after it is applied.\n'}`, { encoding: 'utf8', mode: 0o600 });
process.stdout.write(`Wrote ${sqlPath}\nWrote ${credentialsPath} (plaintext passwords; not printed)\n`);
