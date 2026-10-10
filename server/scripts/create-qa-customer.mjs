// Creates ONE email-confirmed end customer for the Clientes app in Supabase Auth (idempotent).
//
//   cd server && node scripts/create-qa-customer.mjs                  create (or report that it already exists)
//   cd server && node scripts/create-qa-customer.mjs --reset-password  existing user: set a new random password
//
// Reads SUPABASE_URL and SUPABASE_SECRET_KEY from server/.env (never printed, never sent anywhere but the
// Supabase Auth Admin API at SUPABASE_URL). Writes the random password to server/.qa-customer-credentials.local.txt
// (git-ignored). The customer profile row (organization link, QR, points) is created by the app itself on first
// login via POST /customer/me/profile; the API must run with CUSTOMER_ORGANIZATION_ID set.
import { randomInt } from 'node:crypto';
import { existsSync } from 'node:fs';
import { copyFile, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const serverDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const envPath = join(serverDir, '.env');
const credentialsPath = join(serverDir, '.qa-customer-credentials.local.txt');
const EMAIL = 'qa.cliente@dlc-qa.example';
const ORG_ID = '00000000-0000-4000-8000-0000000000a1';
const resetPassword = process.argv.includes('--reset-password');

function parseEnv(text) {
  const values = {};
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const index = line.indexOf('=');
    if (index < 1) continue;
    let value = line.slice(index + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
    values[line.slice(0, index).trim()] = value;
  }
  return values;
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

if (!existsSync(envPath)) fail('server/.env not found.');
const env = parseEnv(await readFile(envPath, 'utf8'));
const baseUrl = String(env.SUPABASE_URL ?? '').trim().replace(/\/+$/, '');
const secret = String(env.SUPABASE_SECRET_KEY ?? '').trim();
if (!baseUrl || !secret) fail('SUPABASE_URL and SUPABASE_SECRET_KEY must be set in server/.env.');
let parsed;
try { parsed = new URL(baseUrl); } catch { fail('SUPABASE_URL is not a valid URL.'); }
if (parsed.protocol !== 'https:' && parsed.hostname !== 'localhost' && parsed.hostname !== '127.0.0.1') fail('SUPABASE_URL must use HTTPS.');

function newPassword() {
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  return Array.from({ length: 4 }, () => Array.from({ length: 6 }, () => alphabet[randomInt(alphabet.length)]).join('')).join('-');
}

// Only the status and Supabase's error code are ever surfaced; bodies can contain tokens or user data.
async function admin(method, path, body) {
  const response = await fetch(`${baseUrl}/auth/v1/admin${path}`, {
    method,
    headers: { apikey: secret, Authorization: `Bearer ${secret}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(20000),
  }).catch(() => fail('Could not reach SUPABASE_URL (network error or timeout).'));
  let json = null;
  try { json = await response.json(); } catch { /* empty body */ }
  return { status: response.status, json };
}

async function writeCredentials(password, status) {
  if (existsSync(credentialsPath)) await copyFile(credentialsPath, `${credentialsPath}.bak`);
  await writeFile(credentialsPath, `DLC QA customer credentials for the Clientes app (local only; never commit or share in chat)
Generated: ${new Date().toISOString()}
Supabase Auth user (email confirmed): ${status}
Organization / CUSTOMER_ORGANIZATION_ID: ${ORG_ID}

Customer
  email:    ${EMAIL}
  password: ${password}

On first login the app accepts the terms and creates the customer profile (POST /customer/me/profile).
The API must have CUSTOMER_ORGANIZATION_ID set to the organization above.
`, { encoding: 'utf8', mode: 0o600 });
}

const password = newPassword();
const created = await admin('POST', '/users', {
  email: EMAIL, password, email_confirm: true, user_metadata: { full_name: 'QA Cliente', qa: true },
});

if (created.status === 200 || created.status === 201) {
  await writeCredentials(password, 'created');
  process.stdout.write(`Customer ${EMAIL} created. Password written to server/.qa-customer-credentials.local.txt (not printed).\n`);
} else if (created.status === 422 || created.json?.error_code === 'email_exists') {
  if (existsSync(credentialsPath) && !resetPassword) {
    process.stdout.write(`Customer ${EMAIL} already exists; credentials are in server/.qa-customer-credentials.local.txt (unchanged).\n`);
  } else {
    // Existing user whose password is unknown (or an explicit reset): find it and set a new password.
    let id = null;
    for (let page = 1; page <= 20 && !id; page += 1) {
      const listed = await admin('GET', `/users?page=${page}&per_page=200`);
      if (listed.status !== 200) fail(`Could not list users (HTTP ${listed.status}${listed.json?.error_code ? `, ${listed.json.error_code}` : ''}).`);
      const users = listed.json?.users ?? [];
      id = users.find(user => String(user.email ?? '').toLowerCase() === EMAIL)?.id ?? null;
      if (users.length < 200) break;
    }
    if (!id) fail(`Customer ${EMAIL} reported as existing but was not found.`);
    const updated = await admin('PUT', `/users/${id}`, { password, email_confirm: true });
    if (updated.status !== 200) fail(`Could not reset the password (HTTP ${updated.status}${updated.json?.error_code ? `, ${updated.json.error_code}` : ''}).`);
    await writeCredentials(password, 'existing user; password reset');
    process.stdout.write(`Customer ${EMAIL} already existed; new password written to server/.qa-customer-credentials.local.txt (not printed).\n`);
  }
} else {
  fail(`Supabase refused the request (HTTP ${created.status}${created.json?.error_code ? `, ${created.json.error_code}` : ''}). Check SUPABASE_SECRET_KEY.`);
}
