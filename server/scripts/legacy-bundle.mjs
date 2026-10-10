import { createHash } from 'node:crypto';

export const SNAPSHOT_COLLECTIONS = [
  'branches','users','cuts','products','suppliers','lots','stockMovements',
  'storeSales','staff','shiftAssignments','equipment','maintenanceOrders',
];

export function parseSnapshot(bytes) {
  if (bytes.byteLength > 32 * 1024 * 1024) throw new Error('El respaldo supera el límite de 32 MiB.');
  const text = bytes.toString('utf8');
  const snapshot = JSON.parse(text);
  if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) throw new Error('El respaldo debe ser un objeto JSON.');
  if (snapshot.schemaVersion !== 1) throw new Error('Solo se admite el esquema local v1.');
  for (const name of SNAPSHOT_COLLECTIONS) {
    if (!Array.isArray(snapshot[name])) throw new Error(`Falta la colección ${name}.`);
    if (snapshot[name].some(row => !row || typeof row !== 'object' || Array.isArray(row))) throw new Error(`La colección ${name} contiene una fila no válida.`);
  }
  assertNoCredentials(snapshot);
  return snapshot;
}

export function hashBytes(bytes) { return createHash('sha256').update(bytes).digest('hex'); }

export function makeManifest(snapshot, sourceBytes, sourceInstallationId, exportedAt = new Date().toISOString()) {
  if (!isUuid(sourceInstallationId)) throw new Error('sourceInstallationId debe ser UUID.');
  return {
    format: 'dlc-legacy-bundle',
    formatVersion: 1,
    schemaVersion: snapshot.schemaVersion,
    sourceInstallationId: sourceInstallationId.toLowerCase(),
    exportedAt,
    sourceFile: 'source.json',
    sourceSha256: hashBytes(sourceBytes),
    sourceBytes: sourceBytes.byteLength,
    counts: Object.fromEntries(SNAPSHOT_COLLECTIONS.map(name => [name, snapshot[name].length])),
    credentials: 'not-exported',
  };
}

export function verifyBundle(manifest, sourceBytes) {
  if (manifest?.format !== 'dlc-legacy-bundle' || manifest.formatVersion !== 1) throw new Error('Formato de paquete legado desconocido.');
  if (!isUuid(manifest.sourceInstallationId)) throw new Error('El paquete no contiene un sourceInstallationId válido.');
  if (manifest.sourceBytes !== sourceBytes.byteLength || manifest.sourceSha256 !== hashBytes(sourceBytes)) throw new Error('El hash del respaldo no coincide con su manifiesto.');
  return parseSnapshot(sourceBytes);
}

export function makePreview(snapshot, manifest, cutoverAt = null, generatedAt = new Date().toISOString()) {
  const blockers = [];
  const warnings = [];
  const mappings = [];
  const seen = new Map();
  const idMap = new Map();
  for (const collection of SNAPSHOT_COLLECTIONS) {
    for (const [index, row] of snapshot[collection].entries()) {
      const legacyId = row?.id;
      if (typeof legacyId !== 'string' || !isUuid(legacyId)) {
        blockers.push({ code: 'LEGACY_ID_INVALID', collection, row: index });
        continue;
      }
      const key = `${collection}:${legacyId.toLowerCase()}`;
      if (seen.has(key)) blockers.push({ code: 'LEGACY_ID_DUPLICATE', collection, legacyId, rows: [seen.get(key), index] });
      else seen.set(key, index);
      idMap.set(`${collection}:${legacyId}`, deterministicId(manifest.sourceInstallationId, collection, legacyId));
      mappings.push({ collection, legacyId, proposedId: deterministicId(manifest.sourceInstallationId, collection, legacyId), status: 'proposed' });
    }
  }

  for (const branch of snapshot.branches) {
    for (const [tankIndex, tank] of (branch?.tanks ?? []).entries()) {
      if (!tank || !isUuid(tank.id)) {
        blockers.push({ code: 'LEGACY_TANK_ID_INVALID', branchId: branch?.id ?? null, row: tankIndex });
        continue;
      }
      const key = `fuelTanks:${tank.id.toLowerCase()}`;
      if (seen.has(key)) blockers.push({ code: 'LEGACY_ID_DUPLICATE', collection: 'fuelTanks', legacyId: tank.id, rows: [seen.get(key), tankIndex] });
      else seen.set(key, tankIndex);
      const proposedId = deterministicId(manifest.sourceInstallationId, 'fuelTanks', tank.id);
      idMap.set(`fuelTanks:${tank.id}`, proposedId);
      mappings.push({ collection: 'fuelTanks', legacyId: tank.id, proposedId, branchLegacyId: branch?.id ?? null, status: 'proposed' });
    }
  }

  const branchIds = new Set(snapshot.branches.map(row => row?.id).filter(Boolean));
  const productIds = new Set(snapshot.products.map(row => row?.id).filter(Boolean));
  const employeeIds = new Set(snapshot.staff.map(row => row?.id).filter(Boolean));
  const lotIds = new Set(snapshot.lots.map(row => row?.id).filter(Boolean));
  for (const [index, branch] of snapshot.branches.entries()) {
    if (!branch.code || !branch.name) blockers.push({ code: 'BRANCH_REQUIRED_FIELDS_MISSING', row: index, legacyId: branch.id });
    const tankKeys = new Set();
    for (const tank of branch.tanks ?? []) {
      const key = String(tank.type ?? 'unknown');
      if (tankKeys.has(key)) blockers.push({ code: 'TANK_PRODUCT_DUPLICATE', branchId: branch.id, fuel: key });
      tankKeys.add(key);
      const current = Number(tank.currentLiters), capacity = Number(tank.capacityLiters);
      if (!Number.isFinite(current) || !Number.isFinite(capacity) || current < 0 || capacity <= 0 || current > capacity) {
        blockers.push({ code: 'TANK_OPENING_OUT_OF_RANGE', branchId: branch.id, tankId: tank.id, currentLiters: tank.currentLiters, capacityLiters: tank.capacityLiters });
      }
    }
  }
  for (const [index, cut] of snapshot.cuts.entries()) {
    if (!branchIds.has(cut.branchID)) blockers.push({ code: 'CUT_BRANCH_MISSING', row: index, branchId: cut.branchID });
    if (!cut.isClosed || !cut.inventoryApplied) warnings.push({ code: 'CUT_OPEN_OR_UNAPPLIED_REQUIRES_REVIEW', legacyId: cut.id, branchId: cut.branchID, closed: Boolean(cut.isClosed), inventoryApplied: Boolean(cut.inventoryApplied) });
    warnings.push({ code: 'CUT_HISTORICAL_NOT_POSTED', legacyId: cut.id, source: 'legacy' });
  }
  for (const [index, lot] of snapshot.lots.entries()) {
    if (!branchIds.has(lot.branchID)) blockers.push({ code: 'LOT_BRANCH_MISSING', row: index, legacyId: lot.id });
    if (!productIds.has(lot.productID)) blockers.push({ code: 'LOT_PRODUCT_MISSING', row: index, legacyId: lot.id });
    if (!Number.isInteger(lot.remainingQuantity) || lot.remainingQuantity < 0 || !Number.isInteger(lot.receivedQuantity) || lot.remainingQuantity > lot.receivedQuantity) blockers.push({ code: 'LOT_QUANTITY_INVALID', row: index, legacyId: lot.id });
  }
  for (const [index, sale] of snapshot.storeSales.entries()) {
    if (!branchIds.has(sale.branchID)) blockers.push({ code: 'SALE_BRANCH_MISSING', row: index, legacyId: sale.id });
    if (!employeeIds.has(sale.cashierID) && !snapshot.users.some(user => user.id === sale.cashierID)) warnings.push({ code: 'SALE_CASHIER_UNMATCHED', row: index, legacyId: sale.id });
  }
  for (const [index, movement] of snapshot.stockMovements.entries()) {
    if (!branchIds.has(movement.branchID) || !productIds.has(movement.productID)) blockers.push({ code: 'STOCK_MOVEMENT_REFERENCE_MISSING', row: index, legacyId: movement.id });
    if (movement.lotID && !lotIds.has(movement.lotID)) blockers.push({ code: 'STOCK_MOVEMENT_LOT_MISSING', row: index, legacyId: movement.id });
  }
  for (const user of snapshot.users) {
    if (!user.username || !user.name) warnings.push({ code: 'USER_REQUIRES_ACTIVATION', legacyId: user.id, role: user.role, status: user.isActive ? 'active' : 'inactive' });
    else warnings.push({ code: 'USER_CREDENTIALS_NOT_IMPORTED', legacyId: user.id, username: user.username, branchId: user.branchID ?? null });
  }
  const openings = snapshot.branches.flatMap(branch => (branch.tanks ?? []).map(tank => ({
    branchLegacyId: branch.id,
    branchProposedId: idMap.get(`branches:${branch.id}`) ?? null,
    tankLegacyId: tank.id ?? null,
    tankProposedId: idMap.get(`fuelTanks:${tank.id}`) ?? null,
    fuelLegacyType: tank.type ?? null,
    quantityLiters: String(tank.currentLiters),
    capacityLiters: String(tank.capacityLiters),
    disposition: 'review_as_opening_only',
    cost: null,
    quality: 'missing',
    source: 'legacy.currentLiters',
  })));
  const storeOpenings = snapshot.lots.map(lot => ({
    branchLegacyId: lot.branchID,
    productLegacyId: lot.productID,
    lotLegacyId: lot.id,
    remainingQuantity: String(lot.remainingQuantity),
    unitCostCents: Number.isInteger(lot.unitCostCents) ? String(lot.unitCostCents) : null,
    disposition: 'review_as_lot_opening_only',
    source: 'legacy.remainingQuantity',
  }));
  const cutover = cutoverAt ? new Date(cutoverAt) : null;
  if (cutoverAt && (!cutover || Number.isNaN(cutover.valueOf()))) blockers.push({ code: 'CUTOVER_DATE_INVALID' });
  return {
    format: 'dlc-legacy-preview',
    version: 1,
    sourceInstallationId: manifest.sourceInstallationId,
    sourceSha256: manifest.sourceSha256,
    generatedAt,
    cutoverAt: cutover ? cutover.toISOString() : null,
    status: blockers.length ? 'blocked' : 'review_required',
    canPublish: false,
    blockers,
    warnings,
    counts: manifest.counts,
    mappings,
    fuelOpeningCandidates: openings,
    storeLotOpeningCandidates: storeOpenings,
    historicalCuts: snapshot.cuts.map(cut => ({ legacyId: cut.id, branchLegacyId: cut.branchID, date: cut.date, type: cut.type, closed: Boolean(cut.isClosed), inventoryApplied: Boolean(cut.inventoryApplied), disposition: 'archive_only_never_post_ledger' })),
    historicalSales: snapshot.storeSales.map(sale => ({ legacyId: sale.id, branchLegacyId: sale.branchID, soldAt: sale.soldAt, status: sale.status, disposition: 'archive_only_never_post_stock' })),
    policy: {
      noInventoryPosted: true,
      noHistoricalCutReplayed: true,
      noCredentialsImported: true,
      unknownFuelCostRemainsNull: true,
      openCutsRequirePerMovementReview: true,
      includedOpeningDocumentsMustNotBeReplayed: true,
    },
  };
}

export function deterministicId(sourceInstallationId, collection, legacyId) {
  const digest = createHash('sha256').update(`${sourceInstallationId.toLowerCase()}:${collection}:${legacyId.toLowerCase()}`).digest();
  const bytes = Buffer.from(digest.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}

function assertNoCredentials(value, path = '$') {
  if (Array.isArray(value)) return value.forEach((entry, index) => assertNoCredentials(entry, `${path}[${index}]`));
  if (value && typeof value === 'object') {
    for (const [key, entry] of Object.entries(value)) {
      if (/(password|credential|secret|access.?token|refresh.?token|session.?token)/i.test(key)) throw new Error(`El respaldo contiene un campo sensible (${path}.${key}); no se exportó.`);
      assertNoCredentials(entry, `${path}.${key}`);
    }
  }
}

function isUuid(value) { return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
