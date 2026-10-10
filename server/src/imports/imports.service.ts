import { createHash } from 'node:crypto';
import { BadRequestException, ConflictException, Inject, Injectable } from '@nestjs/common';
import { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { makeManifest, makePreview, parseSnapshot, deterministicId } from '../../scripts/legacy-bundle.mjs';
import type { LegacySnapshot } from '../../scripts/legacy-bundle.mjs';
import type { LegacyPreviewDto } from './imports.dto.js';

@Injectable()
export class ImportsService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly audit: AuditService) {}

  async preview(principal: AuthPrincipal, input: LegacyPreviewDto, correlationId: string) {
    const sourceBytes = Buffer.from(input.sourceText, 'utf8');
    if (sourceBytes.byteLength < 1 || sourceBytes.byteLength > 32 * 1024 * 1024) throw new BadRequestException('El origen debe medir entre 1 byte y 32 MiB.');
    const declared = input.manifest;
    if (declared.format !== 'dlc-legacy-bundle' || declared.formatVersion !== 1 || declared.schemaVersion !== 1) throw new BadRequestException('Formato de paquete legado desconocido.');
    if (typeof declared.sourceSha256 !== 'string' || !/^[0-9a-f]{64}$/.test(declared.sourceSha256)) throw new BadRequestException('sourceSha256 no es válido.');
    if (declared.sourceSha256 !== createHash('sha256').update(sourceBytes).digest('hex')) throw new ConflictException('El hash declarado no coincide con el JSON original.');
    if (typeof declared.sourceInstallationId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(declared.sourceInstallationId)) throw new BadRequestException('sourceInstallationId debe ser UUID.');
    if (declared.sourceBytes !== sourceBytes.byteLength) throw new ConflictException('El tamaño declarado no coincide con el archivo fuente.');
    let snapshot: ReturnType<typeof parseSnapshot>;
    try { snapshot = parseSnapshot(sourceBytes); }
    catch (error) { throw new BadRequestException(error instanceof Error ? error.message : 'El respaldo no se pudo validar.'); }
    const manifest = makeManifest(snapshot, sourceBytes, String(declared.sourceInstallationId), String(declared.exportedAt ?? new Date().toISOString()));
    if (declared.counts !== undefined && (!declared.counts || typeof declared.counts !== 'object' || Array.isArray(declared.counts) || Object.entries(manifest.counts).some(([key, value]) => (declared.counts as Record<string, unknown>)[key] !== value))) throw new ConflictException('Los conteos del manifiesto no coinciden con el JSON.');
    const preview = makePreview(snapshot, manifest, input.cutoverAt ?? null);
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const inserted = await client.query<{ id: string }>(
        `INSERT INTO legacy_import_batches
          (organization_id,source_installation_id,source_sha256,source_bytes,schema_version,status,cutover_at,manifest,preview,raw_snapshot,initiated_by)
         VALUES ($1,$2,$3,$4,1,$5,$6,$7::jsonb,$8::jsonb,$9::jsonb,$10)
         ON CONFLICT (organization_id,source_installation_id,source_sha256) DO NOTHING RETURNING id`,
        [principal.organizationId, manifest.sourceInstallationId, manifest.sourceSha256, sourceBytes.byteLength,
         preview.status === 'blocked' ? 'blocked' : 'review_required', preview.cutoverAt,
         JSON.stringify(manifest), JSON.stringify(preview), JSON.stringify(snapshot), principal.userId],
      );
      if (!inserted.rowCount) {
        const prior = await client.query<{ id: string; status: string; preview: unknown }>(
          `SELECT id,status,preview FROM legacy_import_batches
            WHERE organization_id=$1 AND source_installation_id=$2 AND source_sha256=$3`,
          [principal.organizationId, manifest.sourceInstallationId, manifest.sourceSha256],
        );
        await client.query('COMMIT');
        return { data: prior.rows[0], idempotent: true };
      }
      const batchId = inserted.rows[0]!.id;
      const rowBuffers = snapshotRows(snapshot, manifest.sourceInstallationId);
      for (const entry of rowBuffers) {
        await client.query(
          `INSERT INTO legacy_import_rows (batch_id,collection_name,row_index,legacy_id,proposed_id,quality,issue_codes,raw_record)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb)`,
          [batchId, entry.collection, entry.rowIndex, entry.legacyId, entry.proposedId, entry.quality, entry.issueCodes, JSON.stringify(entry.raw)],
        );
      }
      await this.audit.appendTransaction(client, { principal, correlationId, action: 'legacy_import.preview', entityType: 'legacy_import_batch', entityId: batchId, after: { sourceSha256: manifest.sourceSha256, status: preview.status, counts: manifest.counts } });
      await client.query('COMMIT');
      return { data: { id: batchId, status: preview.status, preview, idempotent: false } };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally { client.release(); }
  }

  async getPreview(batchId: string, principal: AuthPrincipal) {
    const result = await this.pool.query(
      `SELECT id,status,source_sha256 AS "sourceSha256",source_installation_id AS "sourceInstallationId",cutover_at AS "cutoverAt",preview,created_at AS "createdAt"
         FROM legacy_import_batches WHERE id=$1 AND organization_id=$2`, [batchId, principal.organizationId],
    );
    return result.rows[0] ?? null;
  }
}

function snapshotRows(snapshot: LegacySnapshot, sourceInstallationId: string) {
  const rows: Array<{ collection: string; rowIndex: number; legacyId: string | null; proposedId: string | null; quality: string; issueCodes: string[]; raw: unknown }> = [];
  const simpleCollections: Array<keyof Omit<LegacySnapshot, 'schemaVersion'>> = ['branches','users','cuts','products','suppliers','lots','stockMovements','storeSales','staff','shiftAssignments','equipment','maintenanceOrders'];
  for (const collection of simpleCollections) {
    const values = snapshot[collection] ?? [];
    for (const [rowIndex, raw] of values.entries()) {
      const item = raw as Record<string, unknown>;
      const legacyId = typeof item.id === 'string' ? item.id : null;
      const quality = collection === 'users' ? 'missing' : ['cuts','storeSales','stockMovements'].includes(collection) ? 'estimatedLegacy' : 'provisional';
      rows.push({ collection, rowIndex, legacyId, proposedId: legacyId ? deterministicId(sourceInstallationId, collection, legacyId) : null, quality, issueCodes: [], raw });
    }
  }
  let tankRowIndex = 0;
  for (const branchRaw of (snapshot.branches ?? [])) {
    const branch = branchRaw as Record<string, unknown>;
    const tanks = Array.isArray(branch.tanks) ? branch.tanks : [];
    for (const raw of tanks) {
      const item = raw as Record<string, unknown>;
      const legacyId = typeof item.id === 'string' ? item.id : null;
      rows.push({ collection: 'fuelTanks', rowIndex: tankRowIndex++, legacyId, proposedId: legacyId ? deterministicId(sourceInstallationId, 'fuelTanks', legacyId) : null, quality: 'missing', issueCodes: ['FUEL_COST_UNKNOWN'], raw: { branchId: branch.id, ...item } });
    }
  }
  return rows;
}
