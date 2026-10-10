// Generates the idempotent SQL that adds the QA worker accounts (dispatcher, cashier, store clerk,
// second-country cashier) to the QA tenant, plus the matching local credentials file.
//
//   node scripts/generate-qa-workers.mjs            first run: new passwords + qa-workers.generated.sql
//   node scripts/generate-qa-workers.mjs --force    regenerate even if credentials already exist
//   node scripts/generate-qa-workers.mjs --rotate   new passwords + qa-workers-rotate.generated.sql
//
// Outputs (all git-ignored; the SQL contains argon2id hashes, the .txt contains plaintext):
//   server/.qa-workers-credentials.local.txt
//   server/scripts/sql/qa-workers.generated.sql | qa-workers-rotate.generated.sql
// Prerequisite on the target database: qa-setup.generated.sql already applied (org, GM user, QA-SV-01, QA-GT-01).
import { randomInt } from 'node:crypto';
import { existsSync } from 'node:fs';
import { copyFile, mkdir, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const serverDir = join(here, '..');
const sqlDir = join(here, 'sql');
const credentialsPath = join(serverDir, '.qa-workers-credentials.local.txt');
const argon2 = createRequire(join(serverDir, 'package.json'))('argon2');

const args = new Set(process.argv.slice(2));
const rotate = args.has('--rotate');
const force = args.has('--force');

const ORG_ID = '00000000-0000-4000-8000-0000000000a1';
const GM_EMAIL = 'qa.gerente.general@dlc-qa.example';
const SHIFT_DAYS = 120; // contiguous 24h blocks starting yesterday (UTC), computed when the SQL runs

// Least privilege. Nobody here approves anything: approvals stay with branch/general managers, and the
// creator of a refund request / stock count / price cannot be its approver.
// payment.resolve / payment.refund stay with the cashier on purpose: the database requires the same actor who created a
// payment attempt (or who owns the open cash session) to resolve it or pay the refund out; the approval itself is a manager's.
const ROLES = {
  dispatcher: {
    id: '00000000-0000-4000-8000-0000000000b3', name: 'Despachador',
    permissions: [
      'branch.read', 'fuel.read', 'price.read', 'infrastructure.read',
      'dispense.read', 'dispense.authorize',
      'incident.create', 'incident.read', 'staff.handover',
    ],
  },
  cashier: {
    id: '00000000-0000-4000-8000-0000000000b4', name: 'Cajero',
    permissions: [
      'branch.read', 'fuel.read', 'price.read', 'dispense.read',
      'sale.create', 'sale.read', 'promotion.read',
      'cash.read', 'cash.open', 'cash.move', 'cash.count', 'cash.close',
      'payment.collect', 'payment.read', 'payment.resolve', 'payment.refund', 'sale.refund.request',
      'pos.catalog.read', 'incident.create', 'incident.read', 'staff.handover',
    ],
  },
  store_clerk: {
    id: '00000000-0000-4000-8000-0000000000b5', name: 'Encargado de tienda',
    permissions: [
      'branch.read', 'price.read',
      'pos.catalog.read', 'pos.stock.receive', 'pos.stock.count', 'pos.stock.return', 'pos.stock.quarantine',
      'pos.stock.transfer.send', 'pos.stock.transfer.receive', 'pos.service.fulfill',
      'sale.create', 'sale.read', 'promotion.read',
      'cash.read', 'cash.open', 'cash.count', 'cash.close',
      'payment.collect', 'payment.read', 'payment.resolve', 'payment.refund', 'sale.refund.request',
      'incident.create', 'incident.read', 'staff.handover',
    ],
  },
};

const WORKERS = [
  { key: 'despachador', email: 'qa.despachador@dlc-qa.example', name: 'QA Despachador SV', role: 'dispatcher', branch: 'QA-SV-01', employeeCode: 'QA-DESP-01', title: 'Despachador', userId: '00000000-0000-4000-8000-0000000000c3', employeeId: '00000000-0000-4000-8000-0000000000f1', assignmentId: '00000000-0000-4000-8000-0000000000e3' },
  { key: 'cajero', email: 'qa.cajero@dlc-qa.example', name: 'QA Cajero SV', role: 'cashier', branch: 'QA-SV-01', employeeCode: 'QA-CAJA-01', title: 'Cajero', userId: '00000000-0000-4000-8000-0000000000c4', employeeId: '00000000-0000-4000-8000-0000000000f2', assignmentId: '00000000-0000-4000-8000-0000000000e4' },
  { key: 'tienda', email: 'qa.tienda@dlc-qa.example', name: 'QA Encargado Tienda SV', role: 'store_clerk', branch: 'QA-SV-01', employeeCode: 'QA-TIEN-01', title: 'Encargado de tienda', userId: '00000000-0000-4000-8000-0000000000c5', employeeId: '00000000-0000-4000-8000-0000000000f3', assignmentId: '00000000-0000-4000-8000-0000000000e5' },
  { key: 'cajero_gt', email: 'qa.cajero.gt@dlc-qa.example', name: 'QA Cajero GT', role: 'cashier', branch: 'QA-GT-01', employeeCode: 'QA-CAJA-GT-01', title: 'Cajero', userId: '00000000-0000-4000-8000-0000000000c6', employeeId: '00000000-0000-4000-8000-0000000000f4', assignmentId: '00000000-0000-4000-8000-0000000000e6' },
];

const q = value => `'${String(value).replaceAll("'", "''")}'`;

function newPassword() {
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  return Array.from({ length: 4 }, () => Array.from({ length: 6 }, () => alphabet[randomInt(alphabet.length)]).join('')).join('-');
}

async function hashed(password) {
  const hash = await argon2.hash(password, { type: argon2.argon2id });
  if (!hash.startsWith('$argon2id$') || !(await argon2.verify(hash, password))) throw new Error('argon2id self-check failed.');
  return hash;
}

for (const worker of WORKERS) {
  worker.password = newPassword();
  worker.hash = await hashed(worker.password);
}

if (existsSync(credentialsPath)) {
  if (!rotate && !force) {
    throw new Error('server/.qa-workers-credentials.local.txt already exists. Use --rotate to issue new passwords for existing users, or --force to regenerate the setup SQL.');
  }
  await copyFile(credentialsPath, `${credentialsPath}.bak`);
}
await mkdir(sqlDir, { recursive: true });

let sqlPath;
let sql;
if (rotate) {
  sqlPath = join(sqlDir, 'qa-workers-rotate.generated.sql');
  const emails = WORKERS.map(w => q(w.email)).join(', ');
  sql = `-- DLC QA workers password rotation (generated; contains argon2id hashes; do not commit).
-- Run as a database admin. Revokes the worker sessions.
BEGIN;
${WORKERS.map(w => `UPDATE users SET password_hash = ${q(w.hash)}, failed_login_count = 0, locked_until = NULL,
  permission_version = permission_version + 1, updated_at = now()
 WHERE organization_id = ${q(ORG_ID)} AND email_normalized = ${q(w.email)};`).join('\n')}
UPDATE auth_sessions SET revoked_at = now(), revoke_reason = 'credential_changed'
 WHERE revoked_at IS NULL AND user_id IN (SELECT id FROM users WHERE organization_id = ${q(ORG_ID)} AND email_normalized IN (${emails}));
DO $$ BEGIN
  IF (SELECT count(*) FROM users WHERE organization_id = ${q(ORG_ID)} AND email_normalized IN (${emails})) <> ${WORKERS.length} THEN
    RAISE EXCEPTION 'QA worker users not found; run qa-workers.generated.sql first';
  END IF;
END $$;
COMMIT;
`;
} else {
  sqlPath = join(sqlDir, 'qa-workers.generated.sql');
  const allCodes = [...new Set(Object.values(ROLES).flatMap(r => r.permissions))].sort();
  const roleValues = Object.entries(ROLES).map(([code, r]) => `  (${q(r.id)}, ${q(ORG_ID)}, ${q(code)}, ${q(r.name)}, true)`).join(',\n');
  const permValues = Object.entries(ROLES).flatMap(([code, r]) => r.permissions.map(p => `(${q(code)}, ${q(p)})`));
  const permRows = permValues.map(v => `    ${v}`).join(',\n');
  const employeeRows = WORKERS.map(w => `  (${q(w.employeeId)}, ${q(w.branch)}, ${q(w.employeeCode)}, ${q(w.name)}, ${q(w.title)})`).join(',\n');
  const userRows = WORKERS.map(w => `  (${q(w.userId)}, ${q(w.employeeCode)}, ${q(w.email)}, ${q(w.name)}, ${q(w.hash)})`).join(',\n');
  const assignRows = WORKERS.map(w => `  (${q(w.assignmentId)}, ${q(w.email)}, ${q(w.role)}, ${q(w.branch)})`).join(',\n');
  const codeList = allCodes.map(q).join(', ');
  sql = `-- DLC QA workers (generated by server/scripts/generate-qa-workers.mjs; contains argon2id hashes; do not commit).
-- Run as a database admin (Supabase SQL editor, role postgres) AFTER qa-setup.generated.sql. One transaction,
-- safe to re-run (existing users, roles and shifts are never overwritten; missing shift days and permissions are added).
-- Adds roles dispatcher / cashier / store_clerk (org ${ORG_ID}), employees + users + branch-scoped assignments:
${WORKERS.map(w => `--   ${w.email}  ${w.role}  ${w.branch}`).join('\n')}
-- Login requires an active scheduled work shift whenever users.employee_id is set (AuthService.hasActiveWorkShift,
-- checked on login, refresh and every request). Shifts are limited to 24h and cannot overlap, so ${SHIFT_DAYS} contiguous
-- 24h blocks (all week, around the clock) are created from yesterday 00:00 UTC. Re-run this file to extend the window.
-- Shift position is 'store' on purpose: 'cashier'/'forecourt' positions require a cash register/dispenser that does not
-- exist in draft branches, and nothing but login checks the position.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL timezone = 'UTC';

DO $$
DECLARE missing text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM organizations WHERE id = ${q(ORG_ID)}) THEN RAISE EXCEPTION 'Run qa-setup.generated.sql first (organization missing)'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE organization_id = ${q(ORG_ID)} AND email_normalized = ${q(GM_EMAIL)}) THEN RAISE EXCEPTION 'General manager user missing'; END IF;
  IF (SELECT count(*) FROM branches WHERE organization_id = ${q(ORG_ID)} AND code IN ('QA-SV-01', 'QA-GT-01')) <> 2 THEN RAISE EXCEPTION 'Branches QA-SV-01 / QA-GT-01 missing'; END IF;
  SELECT string_agg(c, ', ') INTO missing FROM unnest(ARRAY[${codeList}]) c WHERE c NOT IN (SELECT code FROM permissions);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'Unknown permission codes: %', missing; END IF;
END $$;

-- Roles (managed, per organization) and their permissions (never removes anything already granted).
INSERT INTO roles (id, organization_id, code, name, managed) VALUES
${roleValues}
ON CONFLICT DO NOTHING;

DO $$
DECLARE added integer;
BEGIN
  INSERT INTO role_permissions (organization_id, role_id, permission_code)
  SELECT r.organization_id, r.id, v.permission_code
    FROM (VALUES
${permRows.replaceAll('\n    ', '\n      ')}
    ) AS v(role_code, permission_code)
    JOIN roles r ON r.organization_id = ${q(ORG_ID)} AND r.code = v.role_code
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS added = ROW_COUNT;
  IF added > 0 THEN -- widened roles: force already-logged-in holders to refresh their permissions
    UPDATE users SET permission_version = permission_version + 1, updated_at = now()
     WHERE organization_id = ${q(ORG_ID)} AND id IN (
       SELECT a.user_id FROM user_role_assignments a JOIN roles r ON r.id = a.role_id
        WHERE a.organization_id = ${q(ORG_ID)} AND r.code IN ('dispatcher', 'cashier', 'store_clerk'));
  END IF;
END $$;

-- Employees (labour record, separate from the account).
INSERT INTO employees (id, organization_id, branch_id, employee_code, legal_name, status, position_title, hired_on)
SELECT v.id::uuid, ${q(ORG_ID)}, b.id, v.code, v.legal_name, 'active', v.title, current_date
  FROM (VALUES
${employeeRows}
  ) AS v(id, branch_code, code, legal_name, title)
  JOIN branches b ON b.organization_id = ${q(ORG_ID)} AND b.code = v.branch_code
ON CONFLICT DO NOTHING;

-- Users: argon2id hashes, linked to their employee. Existing accounts are never touched.
INSERT INTO users (id, organization_id, employee_id, email_normalized, display_name, password_hash, status, must_change_password)
SELECT v.id::uuid, ${q(ORG_ID)}, e.id, v.email, v.display_name, v.password_hash, 'active', false
  FROM (VALUES
${userRows}
  ) AS v(id, employee_code, email, display_name, password_hash)
  JOIN employees e ON e.organization_id = ${q(ORG_ID)} AND e.employee_code = v.employee_code
ON CONFLICT DO NOTHING;

-- Branch-scoped role assignments.
INSERT INTO user_role_assignments (id, organization_id, user_id, role_id, branch_id, assigned_by)
SELECT v.id::uuid, ${q(ORG_ID)}, u.id, r.id, b.id,
       (SELECT id FROM users WHERE organization_id = ${q(ORG_ID)} AND email_normalized = ${q(GM_EMAIL)})
  FROM (VALUES
${assignRows}
  ) AS v(id, email, role_code, branch_code)
  JOIN users u ON u.organization_id = ${q(ORG_ID)} AND u.email_normalized = v.email
  JOIN roles r ON r.organization_id = ${q(ORG_ID)} AND r.code = v.role_code
  JOIN branches b ON b.organization_id = ${q(ORG_ID)} AND b.code = v.branch_code
 WHERE NOT EXISTS (SELECT 1 FROM user_role_assignments a WHERE a.user_id = u.id AND a.role_id = r.id AND a.branch_id = b.id AND a.valid_until IS NULL)
ON CONFLICT DO NOTHING;

-- Around-the-clock shifts: ${SHIFT_DAYS} contiguous UTC-day blocks, deterministic command ids (skipped when already present).
INSERT INTO employee_work_shifts (organization_id, branch_id, employee_id, position, starts_at, ends_at, command_id, request_hash, scheduled_by, correlation_id)
SELECT e.organization_id, e.branch_id, e.id, 'store', d.day, d.day + interval '24 hours',
       md5('qa-worker-shift:' || e.employee_code || ':' || d.day::date)::uuid,
       encode(sha256(convert_to('qa-worker-shift:' || e.employee_code || ':' || d.day::date, 'UTF8')), 'hex'),
       (SELECT id FROM users WHERE organization_id = e.organization_id AND email_normalized = ${q(GM_EMAIL)}),
       gen_random_uuid()
  FROM employees e
 CROSS JOIN LATERAL (
   SELECT (date_trunc('day', now() AT TIME ZONE 'UTC') + make_interval(days => n)) AT TIME ZONE 'UTC' AS day
     FROM generate_series(-1, ${SHIFT_DAYS - 2}) AS n) d
 WHERE e.organization_id = ${q(ORG_ID)} AND e.employee_code IN (${WORKERS.map(w => q(w.employeeCode)).join(', ')}) AND e.status = 'active'
   AND NOT EXISTS (SELECT 1 FROM employee_work_shifts s WHERE s.organization_id = e.organization_id
                    AND s.command_id = md5('qa-worker-shift:' || e.employee_code || ':' || d.day::date)::uuid)
 ORDER BY e.employee_code, d.day;

-- Result summary (last statement; shown by the SQL editor). Expected: 3 roles, 4 workers, 4 assignments, 4 x ${SHIFT_DAYS} shifts.
SELECT (SELECT count(*) FROM roles WHERE organization_id = ${q(ORG_ID)} AND code IN ('dispatcher', 'cashier', 'store_clerk')) AS worker_roles,
       (SELECT count(*) FROM role_permissions rp JOIN roles r ON r.id = rp.role_id WHERE r.organization_id = ${q(ORG_ID)} AND r.code IN ('dispatcher', 'cashier', 'store_clerk')) AS worker_role_permission_rows,
       (SELECT count(*) FROM users WHERE organization_id = ${q(ORG_ID)} AND employee_id IS NOT NULL) AS worker_users,
       (SELECT count(*) FROM user_role_assignments a JOIN roles r ON r.id = a.role_id WHERE a.organization_id = ${q(ORG_ID)} AND r.code IN ('dispatcher', 'cashier', 'store_clerk')) AS worker_assignments,
       (SELECT count(*) FROM employee_work_shifts WHERE organization_id = ${q(ORG_ID)} AND status = 'scheduled' AND ends_at > now()) AS future_or_current_shifts,
       (SELECT max(ends_at) FROM employee_work_shifts WHERE organization_id = ${q(ORG_ID)}) AS shifts_valid_until;

COMMIT;
`;
}

const shiftEnd = new Date(Date.now() + (SHIFT_DAYS - 2) * 86400000).toISOString().slice(0, 10);
await writeFile(sqlPath, sql, 'utf8');
const block = w => `${ROLES[w.role].name} (${w.role}; branch ${w.branch})
  email:    ${w.email}
  password: ${w.password}
  can:      ${ROLES[w.role].permissions.length} permissions (see generate-qa-workers.mjs)
`;
await writeFile(credentialsPath, `DLC QA worker credentials (local only; never commit or share in chat)
Generated: ${new Date().toISOString()}
Organization / CUSTOMER_ORGANIZATION_ID: ${ORG_ID}
These accounts are linked to an employee: login only works while a scheduled work shift is active. The SQL creates
around-the-clock shifts until about ${shiftEnd}; re-run qa-workers.generated.sql to extend them.

${WORKERS.map(block).join('\n')}
${rotate ? 'Status: ROTATED. Run qa-workers-rotate.generated.sql as admin for these passwords to take effect.\n' : 'Status: run qa-workers.generated.sql as admin (after qa-setup.generated.sql); these passwords exist only after it is applied.\n'}`, { encoding: 'utf8', mode: 0o600 });
process.stdout.write(`Wrote ${sqlPath}\nWrote ${credentialsPath} (plaintext passwords; not printed)\n`);
