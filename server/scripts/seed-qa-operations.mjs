#!/usr/bin/env node
// Idempotent QA operations seed. Uses ONLY the public HTTP API (as the QA General Manager) to bring the
// QA branches QA-SV-01 and QA-GT-01 from `draft` to `active` through the same onboarding flow the apps use.
//
//   node scripts/seed-qa-operations.mjs                          seed against http://127.0.0.1:4000/api/v1
//   node scripts/seed-qa-operations.mjs --api https://host/api/v1
//   node scripts/seed-qa-operations.mjs --dry-run                read state, print planned writes, change nothing
//   node scripts/seed-qa-operations.mjs --branch QA-SV-01        limit to one branch
//
// Credentials: server/.qa-credentials.local.txt (git-ignored). Passwords and tokens are never printed.
// Re-running reads the current state first and creates nothing that already exists (second run = no writes).
//
// What it creates per branch: fuel offers (Super/Regular/Diesel), 3 tanks, 6 dispensers x 3 nozzles
// (each nozzle connected to the tank of its fuel), nozzle totalizer baselines, tank opening balances at
// distinct levels, 3 employees + the staff review, effective prices per fuel and service mode,
// then activation, the 60/30 inventory alert policy and today's two daily cuts: morning 06:00-14:00 and evening
// 14:00-22:00 in the branch timezone (22:00-06:00 is not a cut; needs API migration 0110). A branch that already holds
// legacy cuts (morning 06-14 + evening 14:00-06:00 next day) keeps them and gets the correct pair from tomorrow.
import { createHash, randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const here = dirname(fileURLToPath(import.meta.url));
const DEFAULT_API = 'http://127.0.0.1:4000/api/v1';
const DEFAULT_CREDENTIALS = join(here, '..', '.qa-credentials.local.txt');

// ---------------------------------------------------------------- seed definition
const FUELS = [
  { family: 'super', sku: 'SUPER', name: 'Súper', short: 'SUP', tank: 'TK-SUPER', tankName: 'Tanque Súper', price: 4.19, unitCost: 0.62 },
  { family: 'regular', sku: 'REGULAR', name: 'Regular', short: 'REG', tank: 'TK-REGULAR', tankName: 'Tanque Regular', price: 3.89, unitCost: 0.58 },
  { family: 'diesel', sku: 'DIESEL', name: 'Diésel', short: 'DIE', tank: 'TK-DIESEL', tankName: 'Tanque Diésel', price: 3.69, unitCost: 0.60 },
];
const TANK = { nominal: 20000, safeFill: 19000, reserve: 500 };
const DISPENSER_COUNT = 6;
// Dispensers 1-3 sell full service, 4-6 self service (prices are per fuel + service mode).
const modeOf = index => (index <= 3 ? 'full_service' : 'self_service');
const MODES = ['full_service', 'self_service'];
const FULL_SERVICE_SURCHARGE = 0.15;
// Opening liters per tank (nominal 20,000 L): percentages straddle the 30% / 60% rubric thresholds.
const BRANCHES = [
  {
    code: 'QA-SV-01', name: 'QA Sucursal El Salvador', zone: 'occidental', timezone: 'America/El_Salvador', countryCode: 'SV',
    opening: { super: 15000, regular: 9000, diesel: 5000 }, // 75% optimal, 45% medium, 25% critical
    priceDelta: 0,
    staff: [['E01', 'Carlos Hernández', 'Gerente de estación'], ['E02', 'María López', 'Cajera'], ['E03', 'José Ramírez', 'Despachador']],
  },
  {
    code: 'QA-GT-01', name: 'QA Sucursal Guatemala', zone: 'other', timezone: 'America/Guatemala', countryCode: 'GT',
    opening: { super: 5400, regular: 17000, diesel: 10000 }, // 27% critical, 85% optimal, 50% medium
    priceDelta: 0.06,
    staff: [['E01', 'Luis Pérez', 'Gerente de estación'], ['E02', 'Andrea Morales', 'Cajera'], ['E03', 'Diego Castillo', 'Despachador']],
  },
];
const ALERT_POLICY = { warningPercent: '60', criticalPercent: '30' };
// academicLab22 rubric: morning cut 06:00-14:00 and evening cut 14:00-22:00 (branch-local time); 22:00-06:00 is NOT a cut
// (requires migration 0110). Sales/readings recorded in that period are reconciled in the next morning cut.
const CUT_SCHEDULE = { dayStart: '06:00', splitAt: '14:00', dayEnd: '22:00' };
const CUT_WINDOWS = [['06:00', '14:00'], ['14:00', '22:00']];
const levelLabel = percent => (percent <= 30 ? 'critical' : percent <= 60 ? 'medium' : 'optimal');

// ---------------------------------------------------------------- arguments
const { values: args } = parseArgs({
  options: {
    api: { type: 'string', default: DEFAULT_API },
    'dry-run': { type: 'boolean', default: false },
    branch: { type: 'string' },
    credentials: { type: 'string', default: DEFAULT_CREDENTIALS },
    'price-lead-seconds': { type: 'string', default: '60' },
    'allow-insecure-http': { type: 'boolean', default: false },
    help: { type: 'boolean', default: false },
  },
  strict: true,
});
if (args.help) {
  process.stdout.write('Usage: node scripts/seed-qa-operations.mjs [--api URL] [--dry-run] [--branch QA-SV-01|QA-GT-01] [--credentials FILE] [--price-lead-seconds N] [--allow-insecure-http]\n');
  process.exit(0);
}
const DRY = args['dry-run'];
const priceLeadSeconds = Number(args['price-lead-seconds']);
if (!Number.isFinite(priceLeadSeconds) || priceLeadSeconds < 20 || priceLeadSeconds > 900) fail('--price-lead-seconds debe estar entre 20 y 900.');
const selected = args.branch ? BRANCHES.filter(b => b.code === args.branch.toUpperCase()) : BRANCHES;
if (!selected.length) fail(`--branch debe ser uno de: ${BRANCHES.map(b => b.code).join(', ')}.`);
const apiBase = normalizeApi(args.api);

function fail(message) { process.stderr.write(`Error: ${message}\n`); process.exit(1); }
function normalizeApi(value) {
  let url;
  try { url = new URL(value); } catch { fail('--api no es una URL valida.'); }
  const local = ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
  if (url.protocol === 'http:' && !local && !args['allow-insecure-http']) fail('Las credenciales no se envian por http a un host remoto; usa https o --allow-insecure-http.');
  if (!['http:', 'https:'].includes(url.protocol)) fail('--api debe ser http(s).');
  let path = url.pathname.replace(/\/+$/, '');
  if (!/\/api\/v\d+$/.test(path)) path += '/api/v1';
  return `${url.origin}${path}`;
}

// ---------------------------------------------------------------- credentials (never printed)
function readCredentials(file) {
  if (!existsSync(file)) fail(`No existe ${file}. Genera las credenciales con generate-qa-bootstrap.mjs.`);
  const found = { gm: {}, bm: {} };
  let current = null;
  for (const line of readFileSync(file, 'utf8').split(/\r?\n/)) {
    if (/^General Manager/i.test(line)) current = 'gm';
    else if (/^Branch Manager/i.test(line)) current = 'bm';
    const email = /^\s*email:\s*(\S+)/i.exec(line);
    const password = /^\s*password:\s*(\S+)/i.exec(line);
    if (current && email) found[current].email = email[1];
    if (current && password) found[current].password = password[1];
  }
  if (!found.gm.email || !found.gm.password) fail('El archivo de credenciales no contiene el gerente general.');
  return found;
}

// ---------------------------------------------------------------- HTTP layer
class ApiError extends Error {
  constructor(status, code, message, method, path) {
    super(`${method} ${path} -> ${status} ${code}: ${message}`);
    this.status = status; this.code = code; this.detail = message;
  }
}
let serverSkewMs = 0; // server clock minus local clock (from the Date header)
const serverNow = () => Date.now() + serverSkewMs;
const sleep = ms => new Promise(done => setTimeout(done, ms));
const isPlanned = id => typeof id === 'string' && id.startsWith('planned-');
const unwrap = response => (response && typeof response === 'object' && 'data' in response ? response.data : response);

class Session {
  constructor(label, credentials) { this.label = label; this.credentials = credentials; this.token = null; }
  async login() {
    const body = await rawRequest('POST', '/auth/login', { body: { email: this.credentials.email, password: this.credentials.password, deviceLabel: 'qa-seed-script' } });
    const tokens = unwrap(body);
    if (!tokens?.accessToken) throw new Error(`Login de ${this.label} sin token.`);
    this.token = tokens.accessToken;
  }
  async req(method, path, options = {}) {
    if (!this.token) await this.login();
    try { return await rawRequest(method, path, { ...options, token: this.token }); }
    catch (error) {
      if (error instanceof ApiError && error.status === 401 && path !== '/auth/login') {
        await this.login();
        return rawRequest(method, path, { ...options, token: this.token });
      }
      throw error;
    }
  }
}

async function rawRequest(method, path, { query, body, token } = {}) {
  const url = new URL(apiBase + path);
  for (const [key, value] of Object.entries(query ?? {})) if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
  const headers = { accept: 'application/json', 'x-request-id': randomUUID() };
  if (token) headers.authorization = `Bearer ${token}`;
  if (body !== undefined) headers['content-type'] = 'application/json';
  const safeToRetry = method === 'GET';
  for (let attempt = 0; ; attempt += 1) {
    let response;
    try {
      response = await fetch(url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(30_000) });
    } catch (error) {
      if (safeToRetry && attempt < 2) { await sleep(500 * (attempt + 1)); continue; }
      throw new Error(`No pude conectar con ${url.origin} (${error?.cause?.code ?? error?.name ?? 'error de red'}).`);
    }
    const date = Date.parse(response.headers.get('date') ?? '');
    if (Number.isFinite(date)) serverSkewMs = date - Date.now();
    const text = await response.text();
    let parsed = null;
    if (text) { try { parsed = JSON.parse(text); } catch { parsed = null; } }
    if (response.ok) return parsed;
    if ((response.status === 429 || (safeToRetry && response.status >= 502)) && attempt < 3) {
      await sleep(1500 * (attempt + 1)); continue;
    }
    const detail = Array.isArray(parsed?.details) && parsed.details.length ? `${parsed.message} [${parsed.details.join('; ')}]` : (parsed?.message ?? 'sin detalle');
    throw new ApiError(response.status, parsed?.code ?? 'ERROR', detail, method, path);
  }
}

// ---------------------------------------------------------------- logging / dry-run plumbing
const stats = { writes: 0, planned: 0, existing: 0 };
const log = message => process.stdout.write(`${message}\n`);
async function write(label, action, fake) {
  if (DRY) { stats.planned += 1; log(`  [dry-run] ${label}`); return fake; }
  const result = await action();
  stats.writes += 1; log(`  + ${label}`);
  return result;
}
const ok = message => { stats.existing += 1; log(`  = ${message}`); };

function commandId(...parts) { // deterministic UUID so retries replay instead of duplicating
  const hash = createHash('sha256').update(`dlc-qa-seed:${parts.join(':')}`).digest();
  hash[6] = (hash[6] & 0x0f) | 0x40; hash[8] = (hash[8] & 0x3f) | 0x80;
  const hex = hash.subarray(0, 16).toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

async function listAll(session, path, query = {}) {
  const rows = [];
  let cursor;
  for (let page = 0; page < 50; page += 1) {
    const response = await session.req('GET', path, { query: { ...query, ...(cursor ? { cursor } : {}) } });
    rows.push(...(response?.data ?? []));
    cursor = response?.meta?.nextCursor;
    if (!cursor) break;
  }
  return rows;
}

// ---------------------------------------------------------------- steps
async function ensureFuelProducts(gm) {
  const existing = await listAll(gm, '/fuel-products', { limit: 200 });
  const products = {};
  for (const fuel of FUELS) {
    let row = existing.find(p => p.sku === fuel.sku) ?? existing.find(p => p.family === fuel.family && p.status === 'active');
    if (row && row.status !== 'active') fail(`El combustible ${row.sku} existe pero esta ${row.status}; reactivalo desde la app antes de sembrar.`);
    if (row) ok(`fuel product ${row.sku}`);
    else {
      row = unwrap(await write(`POST /fuel-products ${fuel.sku}`, () => gm.req('POST', '/fuel-products', { body: { sku: fuel.sku, displayName: fuel.name, family: fuel.family, brand: 'DLC' } }), { id: `planned-fuel-${fuel.family}`, sku: fuel.sku, family: fuel.family }));
    }
    products[fuel.family] = row;
  }
  return products;
}

async function ensureBranch(gm, def) {
  const rows = await listAll(gm, '/branches', { limit: 100, query: def.code });
  let row = rows.find(b => b.code === def.code);
  if (!row) {
    row = await write(`POST /branches ${def.code} (academicLab22)`, () => gm.req('POST', '/branches', {
      body: { code: def.code, name: def.name, zone: def.zone, timezone: def.timezone, countryCode: def.countryCode, profile: 'academicLab22' },
    }), { id: `planned-branch-${def.code}`, code: def.code, status: 'draft', countryCode: def.countryCode, timezone: def.timezone });
  } else ok(`branch ${def.code} (${row.status})`);
  if (!isPlanned(row.id) && row.status === 'draft' && row.countryCode !== def.countryCode) {
    const detail = await gm.req('GET', `/branches/${row.id}`);
    await write(`PATCH onboarding identity countryCode=${def.countryCode}`, () => gm.req('PATCH', `/branches/${row.id}/onboarding`, { body: { expectedVersion: detail.onboardingVersion, step: 'identity', data: { countryCode: def.countryCode } } }));
    row.countryCode = def.countryCode;
  }
  return { def, id: row.id, status: row.status, timezone: row.timezone ?? def.timezone, planned: isPlanned(row.id) };
}

async function ensureInfrastructure(gm, branch, products) {
  const { def, id } = branch;
  log(`\n== ${def.code}: infrastructure`);
  if (branch.planned) { log('  [dry-run] branch does not exist yet: would create profile, 3 offers, 3 tanks, 6 dispensers, 18 nozzles, connections, baselines, openings and staff'); return; }
  const config = unwrap(await gm.req('GET', `/branches/${id}/configuration`));

  if (config.profile !== 'academicLab22' || Number(config.expectedDispenserCount) !== DISPENSER_COUNT) {
    await write('PUT operating-profile academicLab22 (6 dispensers)', () => gm.req('PUT', `/branches/${id}/operating-profile`, { body: { profile: 'academicLab22', expectedDispenserCount: DISPENSER_COUNT, expectedVersion: Number(config.configurationVersion) } }));
  } else ok('operating profile academicLab22 / 6');

  for (const fuel of FUELS) {
    const product = products[fuel.family];
    const offer = (config.fuelOffers ?? []).find(o => o.fuelProductId === product.id);
    if (!offer || offer.status !== 'active') await write(`PUT fuel-offer ${fuel.sku}`, () => gm.req('PUT', `/branches/${id}/fuel-offers/${product.id}`));
    else ok(`fuel offer ${fuel.sku}`);
  }

  const tanks = {};
  for (const fuel of FUELS) {
    let tank = (config.tanks ?? []).find(t => t.code === fuel.tank);
    if (!tank) {
      tank = unwrap(await write(`POST tank ${fuel.tank} (${TANK.nominal} L)`, () => gm.req('POST', `/branches/${id}/tanks`, {
        body: { code: fuel.tank, name: fuel.tankName, fuelProductId: products[fuel.family].id, nominalCapacityL: String(TANK.nominal), safeFillLimitL: String(TANK.safeFill), unusableReserveL: String(TANK.reserve) },
      }), { id: `planned-tank-${fuel.tank}`, code: fuel.tank }));
    } else ok(`tank ${fuel.tank} (${tank.status})`);
    tanks[fuel.family] = tank;
  }

  const existingDispensers = new Map((config.dispensers ?? []).map(d => [d.code, d]));
  const nozzleRefs = [];
  for (let index = 1; index <= DISPENSER_COUNT; index += 1) {
    const code = `D0${index}`;
    let dispenser = existingDispensers.get(code);
    if (!dispenser) {
      dispenser = unwrap(await write(`POST dispenser ${code}`, () => gm.req('POST', `/branches/${id}/dispensers`, { body: { code, name: `Dispensador ${index}` } }), { id: `planned-disp-${code}`, code, nozzles: [] }));
      dispenser.nozzles ??= [];
    } else ok(`dispenser ${code} (${dispenser.physicalStatus})`);
    for (const fuel of FUELS) {
      const nozzleCode = `${code}-${fuel.short}`;
      let nozzle = (dispenser.nozzles ?? []).find(n => n.code === nozzleCode);
      if (!nozzle) {
        nozzle = unwrap(await write(`POST nozzle ${nozzleCode} (${modeOf(index)})`, () => gm.req('POST', `/branches/${id}/dispensers/${dispenser.id}/nozzles`, {
          body: { code: nozzleCode, productCode: fuel.sku, fuelProductId: products[fuel.family].id, serviceMode: modeOf(index), meterUnit: 'gallon_us', meterPrecision: 3 },
        }), { id: `planned-nozzle-${nozzleCode}`, code: nozzleCode, tankId: null }));
      }
      if (nozzle.tankId !== tanks[fuel.family].id) {
        await write(`PUT nozzle ${nozzleCode} -> ${fuel.tank}`, () => gm.req('PUT', `/branches/${id}/nozzles/${nozzle.id}/tank-connection`, { body: { tankId: tanks[fuel.family].id, reason: 'Alta QA: manguera conectada al tanque de su mismo combustible.' } }));
      }
      nozzleRefs.push({ dispenser, dispenserIndex: index, fuelIndex: FUELS.indexOf(fuel), nozzle });
    }
  }

  // Totalizer baselines (read the dispenser detail: meterVersion is null until a baseline exists).
  for (const dispenser of new Set(nozzleRefs.map(r => r.dispenser))) {
    if (isPlanned(dispenser.id)) { log(`  [dry-run] would capture meter baselines for ${dispenser.code}`); continue; }
    const detail = unwrap(await gm.req('GET', `/branches/${id}/dispensers/${dispenser.id}`));
    for (const nozzle of detail.nozzles ?? []) {
      if (nozzle.meterVersion !== null && nozzle.meterVersion !== undefined) continue;
      const ref = nozzleRefs.find(r => r.nozzle.code === nozzle.code && r.dispenser.code === dispenser.code);
      const value = (1000 + (ref?.dispenserIndex ?? 1) * 100 + (ref?.fuelIndex ?? 0) * 25).toFixed(3);
      await write(`POST meter baseline ${nozzle.code} = ${value} gal`, () => gm.req('POST', `/branches/${id}/nozzles/${nozzle.id}/meter-readings/baseline`, {
        body: { commandId: commandId('baseline', def.code, nozzle.code), value, meterSerial: `QA-${def.code}-${nozzle.code}`, source: 'manual', expectedVersion: 0, note: 'Linea base QA' },
      }));
    }
  }

  // Opening balances: the ledger must hold an `opening` movement per tank.
  for (const fuel of FUELS) {
    const tank = tanks[fuel.family];
    const liters = def.opening[fuel.family];
    if (!isPlanned(tank.id)) {
      const state = await gm.req('GET', `/branches/${id}/tanks/${tank.id}/inventory`);
      if (state.balanceKnown) { ok(`opening balance ${fuel.tank} (${state.balance.onHandL} L)`); continue; }
    }
    const pct = ((liters / TANK.nominal) * 100).toFixed(1);
    await write(`POST opening ${fuel.tank} = ${liters} L (${pct}% ${levelLabel(Number(pct))})`, () => gm.req('POST', `/branches/${id}/tanks/${tank.id}/inventory/opening`, {
      body: { commandId: commandId('opening', def.code, fuel.tank), quantity: String(liters), unit: 'liter', volumeBasis: 'observed', valuationQuality: 'known', totalCostUsd: (liters * fuel.unitCost).toFixed(2), documentReference: 'QA-SEED-OPENING' },
    }));
  }

  // Staff: at least one active employee is a readiness requirement.
  const employees = await listAll(gm, `/branches/${id}/staff/employees`);
  for (const [suffix, legalName, positionTitle] of def.staff) {
    const employeeCode = `${def.code}-${suffix}`;
    if (employees.some(e => (e.employeeCode ?? '').toUpperCase() === employeeCode)) { ok(`employee ${employeeCode}`); continue; }
    await write(`POST employee ${employeeCode}`, () => gm.req('POST', `/branches/${id}/staff/employees`, { body: { employeeCode, legalName, positionTitle, hiredOn: '2026-01-15' } }));
  }
}

// Prices need two people (proposer != approver), a future effective date, and an effective price before
// readiness passes. The QA branch manager is the second person; it is elevated to network scope only for
// the approval calls (the approve route carries no branchId) and restored to its branch afterwards.
async function ensurePrices(gm, creds, branches, svBranchId) {
  log('\n== prices');
  const work = [];
  for (const branch of branches) {
    if (branch.planned) { log(`  [dry-run] ${branch.def.code}: would propose, approve and schedule ${FUELS.length * MODES.length} prices`); continue; }
    const products = branch.products;
    const prices = await gm.req('GET', `/branches/${branch.id}/fuel-prices`);
    const proposals = unwrap(await gm.req('GET', `/branches/${branch.id}/fuel-price-proposals`)) ?? [];
    for (const fuel of FUELS) for (const mode of MODES) {
      const productId = products[fuel.family].id;
      const same = p => p.fuelProductId === productId && p.serviceMode === mode;
      if ((prices.current ?? []).some(same)) { ok(`price ${branch.def.code} ${fuel.sku} ${mode}`); continue; }
      if ((prices.upcoming ?? []).some(same)) { log(`  ~ price ${branch.def.code} ${fuel.sku} ${mode} already scheduled; waiting for its effective time`); branch.waitPrices = true; continue; }
      const reusable = proposals.find(p => same(p) && ['pending_approval', 'approved'].includes(p.status) && Date.parse(p.effectiveAt) > serverNow() + 25_000);
      work.push({ branch, fuel, mode, productId, proposal: reusable ? { id: reusable.id, status: reusable.status, version: reusable.version, effectiveAt: reusable.effectiveAt } : null });
    }
  }
  if (!work.length) {
    if (branches.some(b => b.waitPrices)) await waitForPrices(gm, branches, serverNow() + 90_000);
    return;
  }
  const effectiveAt = new Date(serverNow() + priceLeadSeconds * 1000).toISOString();
  for (const item of work.filter(w => !w.proposal)) {
    const price = (item.fuel.price + item.branch.def.priceDelta + (item.mode === 'full_service' ? FULL_SERVICE_SURCHARGE : 0)).toFixed(2);
    const proposed = await write(`POST price proposal ${item.branch.def.code} ${item.fuel.sku} ${item.mode} = ${price} USD/gal`, () => gm.req('POST', `/branches/${item.branch.id}/fuel-price-proposals`, {
      body: { fuelProductId: item.productId, serviceMode: item.mode, priceUsdPerUnit: price, unit: 'us_gallon', effectiveAt, reason: 'Precio inicial de alta QA.' },
    }), { id: 'planned-proposal', status: 'pending_approval', version: 1, effectiveAt });
    item.proposal = { id: proposed.id, status: proposed.status, version: proposed.version, effectiveAt: proposed.effectiveAt ?? effectiveAt };
  }
  const toApprove = work.filter(w => w.proposal?.status === 'pending_approval');
  if (toApprove.length) {
    const approver = await obtainApprover(gm, creds, svBranchId);
    try {
      for (const item of toApprove) {
        const decided = await write(`POST approve proposal ${item.branch.def.code} ${item.fuel.sku} ${item.mode}`, () => approver.session.req('POST', `/fuel-price-proposals/${item.proposal.id}/approve`, { body: { expectedVersion: item.proposal.version } }), { status: 'approved', version: item.proposal.version + 1 });
        item.proposal.status = decided.status; item.proposal.version = decided.version;
      }
    } finally {
      await approver.restore();
    }
  }
  for (const item of work.filter(w => w.proposal?.status === 'approved')) {
    if (!DRY && Date.parse(item.proposal.effectiveAt) - serverNow() < 2000) throw new Error('La vigencia de los precios vencio antes de programarlos; repite con --price-lead-seconds mayor.');
    await write(`POST schedule proposal ${item.branch.def.code} ${item.fuel.sku} ${item.mode}`, () => gm.req('POST', `/fuel-price-proposals/${item.proposal.id}/schedule`, { body: { expectedVersion: item.proposal.version } }));
  }
  if (!DRY) await waitForPrices(gm, branches, Math.max(...work.map(w => Date.parse(w.proposal.effectiveAt))) + 90_000);
}

async function waitForPrices(gm, branches, deadline) {
  const active = branches.filter(b => !b.planned);
  const pending = () => Promise.all(active.map(async branch => {
    const prices = await gm.req('GET', `/branches/${branch.id}/fuel-prices`);
    return FUELS.length * MODES.length - (prices.current ?? []).filter(p => FUELS.some(f => branch.products[f.family].id === p.fuelProductId)).length;
  })).then(counts => counts.reduce((a, b) => a + b, 0));
  let missing = await pending();
  if (missing > 0) log(`  ~ waiting for ${missing} price(s) to take effect...`);
  while (missing > 0 && serverNow() < deadline) { await sleep(2000); missing = await pending(); }
  if (missing > 0) throw new Error(`${missing} precio(s) no entraron en vigor a tiempo.`);
  log('  prices effective');
}

async function obtainApprover(gm, creds, svBranchId) {
  const none = { restore: async () => {} };
  if (DRY) { log('  [dry-run] would log in as the QA branch manager and, if needed, elevate it to network scope only for the approval calls (restored afterwards)'); return { ...none, session: gm }; }
  if (!creds.bm.email || !creds.bm.password) throw new Error('Se necesita un segundo usuario para aprobar precios (el proponente no puede aprobar) y falta el gerente de sucursal en las credenciales.');
  const bm = new Session('branch manager', creds.bm);
  await bm.login();
  const perms = unwrap(await bm.req('GET', '/auth/me/capabilities')).permissions ?? [];
  if (perms.includes('price.approve')) return { ...none, session: bm };
  const users = await listAll(gm, '/users', { query: creds.bm.email, limit: 20 });
  const user = users.find(u => String(u.email).toLowerCase() === creds.bm.email.toLowerCase());
  const role = user?.roles?.find(r => r.roleCode === 'branch_manager') ?? user?.roles?.[0];
  if (!user || !role) throw new Error('No encontre la asignacion del gerente de sucursal para elevarlo temporalmente.');
  const home = role.branchId ?? svBranchId;
  if (!home) throw new Error('No pude determinar la sucursal propia del gerente de sucursal para restaurarla.');
  await gm.req('POST', `/users/${user.id}/assignments`, { body: { roleId: role.roleId } });
  stats.writes += 1; log('  + QA branch manager elevated to network scope (temporary, for price approval)');
  let restored = false;
  const restore = async () => {
    if (restored) return; restored = true;
    await gm.req('POST', `/users/${user.id}/assignments`, { body: { roleId: role.roleId, branchId: home } });
    stats.writes += 1; log('  + QA branch manager scope restored to its branch');
  };
  try { await bm.login(); } catch (error) { await restore(); throw error; }
  return { session: bm, restore };
}

async function finalizeBranch(gm, branch) {
  const { def, id } = branch;
  log(`\n== ${def.code}: onboarding`);
  if (branch.planned) { log('  [dry-run] would confirm staff, check readiness, activate, set alert policy and generate cuts'); return; }
  let detail = await gm.req('GET', `/branches/${id}`);
  branch.status = detail.status;
  if (detail.status === 'draft') {
    let readiness = await gm.req('GET', `/branches/${id}/readiness`);
    const count = Number(readiness.activeEmployeeCount);
    const review = detail.onboardingData?.staff;
    if (count >= 1 && !(review?.status === 'confirmed' && review.employeeCount === count)) {
      await write(`PATCH onboarding staff confirmed (${count} active)`, () => gm.req('PATCH', `/branches/${id}/onboarding`, { body: { expectedVersion: detail.onboardingVersion, step: 'staff', data: { status: 'confirmed', employeeCount: count } } }).catch(error => {
        if (error instanceof ApiError && error.status === 500) {
          throw new Error('El servidor respondio 500 al guardar el paso de personal. Causa conocida: BranchesService.saveStep usa jsonb_build_object($3,$4::jsonb) sin tipo en $3 (PostgreSQL: "could not determine data type of parameter $3"); corrige a $3::text, vuelve a compilar/desplegar y repite este script (retoma donde quedo).');
        }
        throw error;
      }));
    } else if (count >= 1) ok('staff review confirmed');
    readiness = await gm.req('GET', `/branches/${id}/readiness`);
    if (DRY) { log(`  [dry-run] current readiness: ${readiness.canActivate ? 'ready' : `blocked (${readiness.blockers.map(b => b.code).join(', ')})`}; would activate when ready`); return; }
    if (!readiness.canActivate) throw new Error(`${def.code} sigue bloqueada: ${readiness.blockers.map(b => `${b.code} (${b.step})`).join(', ')}`);
    await write(`POST activate (version ${readiness.onboardingVersion})`, () => gm.req('POST', `/branches/${id}/activate`, { body: { expectedVersion: readiness.onboardingVersion } }));
    detail = await gm.req('GET', `/branches/${id}`);
    branch.status = detail.status;
  } else ok(`status ${detail.status}`);
  if (branch.status !== 'active') { log(`  skipped post-activation steps: status is ${branch.status}`); return; }

  const dashboard = unwrap(await gm.req('GET', `/metrics/branches/${id}/dashboard`));
  const tank = dashboard.inventory?.tanks?.[0];
  if (!tank || Number(tank.warningPercent) !== Number(ALERT_POLICY.warningPercent) || Number(tank.criticalPercent) !== Number(ALERT_POLICY.criticalPercent)) {
    await write(`PATCH inventory alert policy warning ${ALERT_POLICY.warningPercent}% / critical ${ALERT_POLICY.criticalPercent}%`, () => gm.req('PATCH', `/metrics/branches/${id}/inventory-alert-policy`, { body: ALERT_POLICY }));
  } else ok('inventory alert policy 60/30');

  const today = localDate(branch.timezone, serverNow());
  const state = await ensureCuts(gm, branch, today);
  if (state === 'legacy') {
    // Legacy QA data: today's pair is the old 06:00-14:00 / 14:00-06:00 (next day). One cut per slot per day and
    // contiguous windows mean it cannot be edited in place, and a cut with history must not be deleted from the API.
    // Safe path: leave today's legacy cuts untouched (they keep their data and simply end at 06:00 tomorrow) and
    // create the correct 06-14 / 14-22 pair from tomorrow, whose 06:00 start continues exactly where the legacy evening ends.
    const tomorrow = localDate(branch.timezone, serverNow() + 86_400_000);
    log(`  ! ${def.code}: legacy 14:00-06:00 evening cut found for ${today}; leaving it untouched and creating the 06-14 / 14-22 cuts for ${tomorrow}.`);
    log('    To correct today as well, an admin can run server/scripts/sql/qa-replace-legacy-cuts.sql (removes only never-opened legacy QA cuts) and re-run this script.');
    const next = await ensureCuts(gm, branch, tomorrow);
    if (next === 'legacy') throw new Error(`${def.code}: los cortes de ${tomorrow} siguen con ventanas antiguas; aplica la migración 0110 y repite.`);
  }
}

const localDate = (timeZone, millis) => new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(millis));
const localTime = (iso, timeZone) => new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(iso));
// A day is correct when it has both slots at the academic windows, whatever instant they map to in the branch timezone.
function cutsMatchSchedule(cuts, timeZone) {
  const bySlot = new Map(cuts.map(cut => [Number(cut.slot), cut]));
  return CUT_WINDOWS.every(([from, to], index) => {
    const cut = bySlot.get(index + 1);
    return cut && localTime(cut.startsAt, timeZone) === from && localTime(cut.endsAt, timeZone) === to
      && Date.parse(cut.endsAt) - Date.parse(cut.startsAt) === 8 * 3_600_000;
  });
}

// Returns 'ok' when the day holds the academic windows, 'legacy' when it already holds other windows.
async function ensureCuts(gm, branch, date) {
  const { def, id } = branch;
  const read = async () => unwrap(await gm.req('GET', `/branches/${id}/cuts`, { query: { date } }));
  let cuts = await read();
  if (cuts.length) {
    if (cutsMatchSchedule(cuts, branch.timezone)) { ok(`cuts for ${date} (06:00-14:00 and 14:00-22:00)`); return 'ok'; }
    return 'legacy';
  }
  const generate = () => write(`POST generate cuts ${date}`, () => gm.req('POST', `/branches/${id}/cuts/generate`, { body: { operationalDate: date } }));
  // Profile first, so a fresh day never materialises with an older schedule. 409 = a profile already exists from that date.
  try {
    await write(`POST cut profile ${CUT_SCHEDULE.dayStart}/${CUT_SCHEDULE.splitAt}/${CUT_SCHEDULE.dayEnd} from ${date}`, () => gm.req('POST', `/branches/${id}/cuts/profiles`, { body: { effectiveDate: date, ...CUT_SCHEDULE } }));
  } catch (error) {
    if (!(error instanceof ApiError && [400, 409].includes(error.status))) throw error;
    if (error.status === 400) throw new Error(`${def.code}: la API rechazó el perfil de cortes (${error.detail}); despliega la API con la migración 0110.`);
    log(`  = cut profile for ${date} already exists`);
  }
  try { await generate(); }
  catch (error) {
    if (error instanceof ApiError && error.status === 409) return 'legacy';
    throw error;
  }
  if (DRY) return 'ok';
  cuts = await read();
  return cutsMatchSchedule(cuts, branch.timezone) ? 'ok' : 'legacy';
}

// ---------------------------------------------------------------- summary
async function summarize(gm, branches) {
  const rows = [];
  for (const branch of branches) {
    if (branch.planned) { rows.push({ branch: branch.def.code, country: branch.def.countryCode, status: 'planned', tanks: '-', hw: '-', ready: '-' }); continue; }
    const detail = await gm.req('GET', `/branches/${branch.id}`);
    const config = unwrap(await gm.req('GET', `/branches/${branch.id}/configuration`));
    const tanks = [];
    for (const tank of config.tanks ?? []) {
      const inventory = await gm.req('GET', `/branches/${branch.id}/tanks/${tank.id}/inventory`);
      const percent = inventory.balance ? (Number(inventory.balance.onHandL) / Number(tank.nominalCapacityL)) * 100 : null;
      tanks.push(`${String(tank.fuelName).replace(/^Gasolina /, '')} ${percent === null ? 'n/a' : `${percent.toFixed(1)}% ${levelLabel(percent)}`}`);
    }
    const nozzles = (config.dispensers ?? []).reduce((n, d) => n + (d.nozzles?.length ?? 0), 0);
    let ready = 'n/a (active)';
    if (detail.status === 'draft') {
      const readiness = await gm.req('GET', `/branches/${branch.id}/readiness`);
      ready = readiness.canActivate ? 'ready' : `blocked: ${readiness.blockers.map(b => b.code).join(', ')}`;
    } else if (detail.status === 'active') ready = 'ready (active)';
    rows.push({ branch: branch.def.code, country: detail.countryCode, status: detail.status, tanks: tanks.join(' | '), hw: `${(config.dispensers ?? []).length} disp / ${nozzles} noz`, ready });
  }
  log('\nSummary');
  for (const row of rows) log(`  ${row.branch.padEnd(9)} ${String(row.country).padEnd(3)} ${row.status.padEnd(7)} ${row.hw.padEnd(16)} ${row.ready}\n            tanks: ${row.tanks}`);
  if (!DRY) {
    const network = unwrap(await gm.req('GET', '/metrics/network/dashboard'));
    log(`  network: activeBranches=${network.activeBranchCount} countries=${(network.countries ?? []).map(c => `${c.countryCode}:${c.branchCount}`).join(',') || '-'}`);
    for (const b of network.branches ?? []) log(`           ${b.code} ${b.countryCode} inventoryRisk=${b.inventoryRisk}`);
  }
  log(`  writes=${stats.writes}${DRY ? ` planned=${stats.planned}` : ''}`);
}

// ---------------------------------------------------------------- main
async function main() {
  const creds = readCredentials(resolve(args.credentials));
  log(`DLC QA operations seed -> ${apiBase}${DRY ? ' (dry-run: no domain writes; login still creates a session)' : ''}`);
  const gm = new Session('general manager', creds.gm);
  await gm.login();
  const products = await ensureFuelProducts(gm);
  const branches = [];
  for (const def of selected) {
    const branch = await ensureBranch(gm, def);
    branch.products = products;
    branches.push(branch);
  }
  // The BM restore target needs QA-SV-01 even when --branch limits the run.
  if (!branches.some(b => b.def.code === 'QA-SV-01')) {
    const rows = await listAll(gm, '/branches', { limit: 100, query: 'QA-SV-01' });
    const sv = rows.find(b => b.code === 'QA-SV-01');
    if (sv) branches.push({ def: BRANCHES[0], id: sv.id, planned: false, hidden: true, products });
  }
  const working = branches.filter(b => !b.hidden);
  for (const branch of working) {
    if (branch.status !== 'draft' && branch.status !== 'active' && !branch.planned) { log(`\n== ${branch.def.code}: status ${branch.status} cannot be seeded; skipped`); branch.skip = true; }
  }
  const targets = working.filter(b => !b.skip);
  for (const branch of targets) await ensureInfrastructure(gm, branch, products);
  await ensurePrices(gm, creds, targets, branches.find(b => b.def.code === 'QA-SV-01')?.id);
  for (const branch of targets) await finalizeBranch(gm, branch);
  await summarize(gm, working);
}

try { await main(); }
catch (error) {
  process.stderr.write(`\nFALLO: ${error.message}\n`);
  process.exit(1);
}
