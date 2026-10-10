export interface LegacySnapshot {
  schemaVersion: number;
  branches: Array<Record<string, any>>;
  users: Array<Record<string, any>>;
  cuts: Array<Record<string, any>>;
  products: Array<Record<string, any>>;
  suppliers: Array<Record<string, any>>;
  lots: Array<Record<string, any>>;
  stockMovements: Array<Record<string, any>>;
  storeSales: Array<Record<string, any>>;
  staff: Array<Record<string, any>>;
  shiftAssignments: Array<Record<string, any>>;
  equipment: Array<Record<string, any>>;
  maintenanceOrders: Array<Record<string, any>>;
}

export interface LegacyManifest {
  format: 'dlc-legacy-bundle';
  formatVersion: 1;
  schemaVersion: number;
  sourceInstallationId: string;
  exportedAt: string;
  sourceFile: string;
  sourceSha256: string;
  sourceBytes: number;
  counts: Record<string, number>;
  credentials: 'not-exported';
}

export function parseSnapshot(bytes: Buffer): LegacySnapshot;
export function hashBytes(bytes: Buffer): string;
export function makeManifest(snapshot: LegacySnapshot, sourceBytes: Buffer, sourceInstallationId: string, exportedAt?: string): LegacyManifest;
export function verifyBundle(manifest: LegacyManifest, sourceBytes: Buffer): LegacySnapshot;
export function makePreview(snapshot: LegacySnapshot, manifest: LegacyManifest, cutoverAt?: string | null, generatedAt?: string): Record<string, any>;
export function deterministicId(sourceInstallationId: string, collection: string, legacyId: string): string;
