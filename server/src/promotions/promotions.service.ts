import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, Logger, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { ConfigService } from '@nestjs/config';
import { Pool, type PoolClient } from 'pg';
import type { AuthPrincipal } from '../auth/auth.types.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import { PG_POOL } from '../database/database.module.js';
import { isPromotionActiveAt, normalizePromotionBoundary, previewPromotionOccurrences, validatePromotionDefinition, type PromotionDefinition, type PromotionRecurrence } from './promotion-rules.js';
import type { CashbackPartnerStatusDto, CreateCashbackPartnerDto, CreatePromotionDto, PausePromotionDto, PromotionCommandDto, PromotionDecisionDto, UploadPromotionImageDto } from './promotion.dto.js';

@Injectable()
export class PromotionsService {
  private readonly logger = new Logger(PromotionsService.name);
  constructor(@Inject(PG_POOL) private readonly pool: Pool, private readonly auth: AuthService, private readonly audit: AuditService, private readonly config: ConfigService) {}

  async create(principal: AuthPrincipal, input: CreatePromotionDto, correlationId: string) {
    const definition = await this.resolveTargeting(principal, this.definition(input));
    await this.requireManager(principal, definition);
    await this.requireBankPartner(principal.organizationId, definition);
    await this.requireRegisteredImage(principal.organizationId, definition);
    const normalized = stableJson(definition);
    const requestHash = hash(normalized);
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`promotion-command:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
      const replay = await client.query<{ id: string; create_request_hash: string; created_by: string }>(
        'SELECT id,create_request_hash,created_by FROM customer_promotions WHERE organization_id=$1 AND create_command_id=$2',
        [principal.organizationId, input.commandId],
      );
      if (replay.rows[0]) {
        if (replay.rows[0].create_request_hash !== requestHash || replay.rows[0].created_by !== principal.userId) throw new ConflictException('El comando ya se utilizó para otra promoción.');
        await client.query('COMMIT');
        return { id: replay.rows[0].id, version: 1, status: 'draft', idempotentReplay: true };
      }
      const created = await client.query<{ id: string }>(
        `INSERT INTO customer_promotions(organization_id,branch_id,scope,current_version,create_command_id,create_request_hash,status,created_by)
         VALUES($1,$2,$3,1,$4,$5,'draft',$6) RETURNING id`,
        [principal.organizationId, definition.branchId ?? null, definition.scope, input.commandId, requestHash, principal.userId],
      );
      const promotionId = created.rows[0]!.id;
      await client.query(
        `INSERT INTO customer_promotion_versions(organization_id,promotion_id,version,status,definition,created_by)
         VALUES($1,$2,1,'draft',$3::jsonb,$4)`,
        [principal.organizationId, promotionId, JSON.stringify(definition), principal.userId],
      );
      await client.query(
        `INSERT INTO customer_promotion_events(organization_id,promotion_id,version,command_id,event_type,actor_id,payload)
         VALUES($1,$2,1,$3,'created',$4,$5::jsonb)`,
        [principal.organizationId, promotionId, input.commandId, principal.userId, JSON.stringify({ requestHash })],
      );
      await this.audit.appendTransaction(client, { principal, branchId: definition.branchId ?? null, correlationId, action: 'promotion.created', entityType: 'customer_promotion', entityId: promotionId, after: { version: 1, kind: definition.kind, scope: definition.scope, targetBranchIds: definition.targetBranchIds ?? null, targetZones: definition.targetZones ?? null, targetMetric: definition.targetMetric ?? null } });
      await client.query('COMMIT');
      return { id: promotionId, version: 1, status: 'draft', idempotentReplay: false };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if ((error as { code?: string }).code === '23505') throw new ConflictException('El comando de creación ya fue registrado.');
      throw error;
    } finally { client.release(); }
  }

  async createVersion(id: string, principal: AuthPrincipal, input: CreatePromotionDto, correlationId: string) {
    if (!uuid(id) || !uuid(input.commandId)) throw new BadRequestException('Promoción o comando no válido.');
    const definition = await this.resolveTargeting(principal, this.definition(input));
    await this.requireManager(principal, definition);
    await this.requireBankPartner(principal.organizationId, definition);
    await this.requireRegisteredImage(principal.organizationId, definition);
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`promotion:${principal.organizationId}:${id.toLowerCase()}`]);
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`promotion-command:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
      const replay = await client.query<{ promotion_id: string; event_type: string; actor_id: string; payload: Record<string, unknown> }>(
        'SELECT promotion_id,event_type,actor_id,payload FROM customer_promotion_events WHERE organization_id=$1 AND command_id=$2', [principal.organizationId, input.commandId]);
      const requestHash = hash(stableJson(definition));
      if (replay.rows[0]) {
        if (replay.rows[0].promotion_id !== id || replay.rows[0].event_type !== 'version_created' || replay.rows[0].actor_id !== principal.userId || stableJson(replay.rows[0].payload) !== stableJson({ requestHash })) throw new ConflictException('El comando ya se usó para otra acción.');
        await client.query('COMMIT');
        return { id, idempotentReplay: true };
      }
      const found = await client.query<PromotionRow>(`SELECT id,organization_id,branch_id,scope,status,current_version,active_version,scheduled_version,created_by,approved_by FROM customer_promotions WHERE id=$1 AND organization_id=$2 FOR UPDATE`, [id, principal.organizationId]);
      const promotion = found.rows[0];
      if (!promotion) throw new NotFoundException('La promoción no existe.');
      if (promotion.scope !== definition.scope || promotion.branch_id !== (definition.branchId ?? null)) throw new BadRequestException('La versión debe conservar el alcance y la sucursal de la promoción original.');
      if (promotion.status === 'pending_approval' || promotion.status === 'cancelled') throw new ConflictException('Resuelve la versión pendiente o crea una promoción nueva antes de editar.');
      const version = promotion.current_version + 1;
      await client.query(`INSERT INTO customer_promotion_versions(organization_id,promotion_id,version,status,definition,created_by) VALUES($1,$2,$3,'draft',$4::jsonb,$5)`, [principal.organizationId, id, version, JSON.stringify(definition), principal.userId]);
      await client.query(`UPDATE customer_promotions SET current_version=$2,updated_at=now() WHERE id=$1`, [id, version]);
      await client.query(`INSERT INTO customer_promotion_events(organization_id,promotion_id,version,command_id,event_type,actor_id,payload) VALUES($1,$2,$3,$4,'version_created',$5,$6::jsonb)`, [principal.organizationId, id, version, input.commandId, principal.userId, JSON.stringify({ requestHash })]);
      await this.audit.appendTransaction(client, { principal, branchId: promotion.branch_id, correlationId, action: 'promotion.version_created', entityType: 'customer_promotion', entityId: id, after: { version, requestHash, targetBranchIds: definition.targetBranchIds ?? null, targetZones: definition.targetZones ?? null, targetMetric: definition.targetMetric ?? null } });
      await client.query('COMMIT');
      return { id, version, status: 'draft', idempotentReplay: false };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if ((error as { code?: string }).code === '23505') throw new ConflictException('El comando de versión ya fue registrado.');
      throw error;
    } finally { client.release(); }
  }

  async submit(id: string, principal: AuthPrincipal, input: PromotionCommandDto, correlationId: string) {
    return this.transition(id, principal, input.commandId, 'submitted', correlationId, async (client, promotion, version) => {
      await this.requireManager(principal, promotion.definition);
      if (version.status !== 'draft') throw new ConflictException('Solo se puede enviar a aprobación una versión en borrador.');
      await client.query(`UPDATE customer_promotion_versions SET status='pending_approval',submitted_by=$3,submitted_at=now() WHERE promotion_id=$1 AND version=$2`, [id, promotion.current_version, principal.userId]);
      if (!promotion.active_version && !promotion.scheduled_version) await client.query(`UPDATE customer_promotions SET status='pending_approval',updated_at=now() WHERE id=$1`, [id]);
      return { status: 'pending_approval' };
    });
  }

  async decide(id: string, principal: AuthPrincipal, input: PromotionDecisionDto, correlationId: string) {
    const reason = input.reason.trim().normalize('NFKC');
    if (reason.length < 10) throw new BadRequestException('Explica la decisión en al menos diez caracteres.');
    const eventType = input.decision === 'approve' ? 'approved' : 'rejected';
    return this.transition(id, principal, input.commandId, eventType, correlationId, async (client, promotion, version) => {
      // All activation decisions belong to General Admin, including branch proposals.
      await this.requirePermission(principal, 'promotion.network.approve');
      if (version.status !== 'pending_approval') throw new ConflictException('La versión ya no está pendiente de aprobación.');
      if (version.created_by === principal.userId || version.submitted_by === principal.userId) throw new ConflictException('La aprobación requiere a otra persona distinta de quien creó o envió la promoción.');
      await this.requireBankPartner(principal.organizationId, promotion.definition, client);
      const nextVersionStatus = input.decision === 'approve' ? 'approved' : 'rejected';
      await client.query(`UPDATE customer_promotion_versions SET status=$3,approved_by=$4,approved_at=now(),decision_reason=$5 WHERE promotion_id=$1 AND version=$2`, [id, promotion.current_version, nextVersionStatus, principal.userId, reason]);
      if (input.decision === 'approve') {
        if (promotion.definition.kind !== 'announcement') throw new ConflictException('Este beneficio aún no está conectado al motor transaccional de ventas/lealtad y no se puede publicar. Aprueba por ahora solo anuncios informativos.');
        const start = Date.parse(promotion.definition.startsAt);
        const scheduled = start > Date.now();
        const status = scheduled ? (promotion.active_version ? 'active' : 'scheduled') : 'active';
        await client.query(`UPDATE customer_promotions SET active_version=CASE WHEN $2 THEN active_version ELSE current_version END,scheduled_version=CASE WHEN $2 THEN current_version ELSE NULL END,status=$3,approved_by=$4,approved_at=now(),updated_at=now() WHERE id=$1`, [id, scheduled, status, principal.userId]);
        await this.notifyEligibleCustomers(client, principal.organizationId, id, promotion.definition);
        return { status, scheduled, version: promotion.current_version };
      }
      if (!promotion.active_version && !promotion.scheduled_version) await client.query(`UPDATE customer_promotions SET status='rejected',updated_at=now() WHERE id=$1`, [id]);
      return { status: promotion.active_version ? promotion.status : 'rejected', version: promotion.current_version };
    }, { reason, decision: input.decision });
  }

  async pause(id: string, principal: AuthPrincipal, input: PausePromotionDto, correlationId: string) {
    const reason = input.reason.trim().normalize('NFKC');
    if (reason.length < 10) throw new BadRequestException('Explica por qué se suspende la promoción.');
    return this.transition(id, principal, input.commandId, 'paused', correlationId, async (client, promotion) => {
      await this.requirePermission(principal, 'promotion.network.approve');
      if ((!promotion.active_version && !promotion.scheduled_version) || !['active', 'scheduled'].includes(promotion.status)) throw new ConflictException('Solo se puede suspender una promoción aprobada y vigente o programada.');
      await client.query(`UPDATE customer_promotions SET status='paused',paused_by=$2,paused_at=now(),pause_reason=$3,updated_at=now() WHERE id=$1`, [id, principal.userId, reason]);
      return { status: 'paused' };
    }, { reason });
  }

  async resume(id: string, principal: AuthPrincipal, input: PromotionCommandDto, correlationId: string) {
    return this.transition(id, principal, input.commandId, 'resumed', correlationId, async (client, promotion) => {
      await this.requirePermission(principal, 'promotion.network.approve');
      if (promotion.status !== 'paused' || (!promotion.active_version && !promotion.scheduled_version)) throw new ConflictException('La promoción no está suspendida.');
      const versionToResume = promotion.scheduled_version ?? promotion.active_version;
      if (!versionToResume) throw new ConflictException('La promoción no tiene una versión aprobada para reanudar.');
      const definition = await this.pool.query<{ definition: PromotionDefinition; version: number }>('SELECT definition,version FROM customer_promotion_versions WHERE promotion_id=$1 AND organization_id=$2 AND version=$3 AND status=\'approved\'', [id, principal.organizationId, versionToResume]);
      const active = definition.rows[0];
      if (!active) throw new ConflictException('La promoción aprobada no tiene una versión recuperable.');
      const now = Date.now();
      const starts = Date.parse(active.definition.startsAt), ends = Date.parse(active.definition.endsAt);
      const status = ends <= now ? 'ended' : starts > now ? 'scheduled' : 'active';
      if (status === 'ended') throw new ConflictException('La vigencia terminó; crea y aprueba una nueva versión.');
      await client.query(`UPDATE customer_promotions SET status=$2,active_version=CASE WHEN $3='active' THEN $4 ELSE active_version END,scheduled_version=CASE WHEN $3='scheduled' THEN $4 ELSE NULL END,paused_by=NULL,paused_at=NULL,pause_reason=NULL,updated_at=now() WHERE id=$1`, [id, status, status, active.version]);
      return { status, version: active.version };
    });
  }

  async list(principal: AuthPrincipal, branchId?: string) {
    const permission = await this.auth.capabilities(principal, branchId);
    if (!permission.includes('promotion.read')) throw new ForbiddenException('No tienes permiso para consultar promociones.');
    const result = await this.pool.query(
      `SELECT p.id,p.branch_id AS "branchId",p.scope,p.status,p.current_version AS "currentVersion",p.active_version AS "activeVersion",p.scheduled_version AS "scheduledVersion",
              p.created_by AS "createdBy",p.approved_by AS "approvedBy",p.created_at AS "createdAt",v.definition,v.status AS "versionStatus"
         FROM customer_promotions p JOIN customer_promotion_versions v ON v.promotion_id=p.id AND v.organization_id=p.organization_id AND v.version=p.current_version
        WHERE p.organization_id=$1 AND ($2::uuid IS NULL OR p.branch_id=$2 OR p.scope='network') ORDER BY p.updated_at DESC,p.id`,
      [principal.organizationId, branchId ?? null],
    );
    return { data: result.rows };
  }

  async cashbackPartners(principal: AuthPrincipal) {
    await this.requirePermission(principal, 'promotion.read');
    const result = await this.pool.query(`SELECT code,"display_name" AS "displayName",status FROM customer_cashback_partners WHERE organization_id=$1 ORDER BY display_name,code`, [principal.organizationId]);
    return { data: result.rows };
  }

  async createCashbackPartner(principal: AuthPrincipal, input: CreateCashbackPartnerDto, correlationId: string) {
    await this.requirePermission(principal, 'promotion.network.manage');
    const code = input.code.trim().toUpperCase(), displayName = input.displayName.trim().normalize('NFKC');
    if (!/^[A-Z0-9_-]{2,40}$/.test(code) || displayName.length < 2 || displayName.length > 120) throw new BadRequestException('El código o nombre del banco no es válido.');
    const requestHash = hash(stableJson({ code, displayName }));
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`cashback-partner-command:${principal.organizationId}:${input.commandId}`]);
      const old = await client.query<{ code: string; request_hash: string; created_by: string }>('SELECT code,request_hash,created_by FROM customer_cashback_partners WHERE organization_id=$1 AND command_id=$2', [principal.organizationId, input.commandId]);
      if (old.rows[0]) {
        if (old.rows[0].request_hash !== requestHash || old.rows[0].created_by !== principal.userId) throw new ConflictException('El comando ya fue usado para otro banco.');
        await client.query('COMMIT'); return { code: old.rows[0].code, idempotentReplay: true };
      }
      const result = await client.query<{ code: string }>(`INSERT INTO customer_cashback_partners(organization_id,code,display_name,command_id,request_hash,created_by) VALUES($1,$2,$3,$4,$5,$6) RETURNING code`, [principal.organizationId, code, displayName, input.commandId, requestHash, principal.userId]);
      await this.audit.appendTransaction(client, { principal, correlationId, action: 'promotion.cashback_partner.created', entityType: 'cashback_partner', entityId: code, after: { code, displayName } });
      await client.query('COMMIT'); return { code: result.rows[0]!.code, idempotentReplay: false };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if ((error as { code?: string }).code === '23505') throw new ConflictException('Ese código de banco ya existe; usa el registro disponible.');
      throw error;
    } finally { client.release(); }
  }

  async cashbackPartnerStatus(codeValue: string, principal: AuthPrincipal, input: CashbackPartnerStatusDto, correlationId: string) {
    await this.requirePermission(principal, 'promotion.network.manage');
    const code = codeValue.trim().toUpperCase();
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`cashback-partner-command:${principal.organizationId}:${input.commandId}`]);
      const requestHash = hash(stableJson({ code, status: input.status }));
      const replay = await client.query<{ partner_code: string; status: string; actor_id: string; request_hash: string }>('SELECT partner_code,status,actor_id,request_hash FROM customer_cashback_partner_events WHERE organization_id=$1 AND command_id=$2', [principal.organizationId, input.commandId]);
      if (replay.rows[0]) {
        if (replay.rows[0].partner_code !== code || replay.rows[0].status !== input.status || replay.rows[0].actor_id !== principal.userId || replay.rows[0].request_hash !== requestHash) throw new ConflictException('El comando ya fue usado para otra acción.');
        await client.query('COMMIT'); return { code, status: input.status, idempotentReplay: true };
      }
      const result = await client.query(`UPDATE customer_cashback_partners SET status=$3 WHERE organization_id=$1 AND code=$2 RETURNING code,status`, [principal.organizationId, code, input.status]);
      if (!result.rows[0]) throw new NotFoundException('El banco participante no existe.');
      await client.query(`INSERT INTO customer_cashback_partner_events(organization_id,partner_code,command_id,actor_id,event_type,status,request_hash) VALUES($1,$2,$3,$4,'status_changed',$5,$6)`, [principal.organizationId, code, input.commandId, principal.userId, input.status, requestHash]);
      await this.audit.appendTransaction(client, { principal, correlationId, action: 'promotion.cashback_partner.status', entityType: 'cashback_partner', entityId: code, after: { status: input.status } });
      await client.query('COMMIT'); return { code: result.rows[0].code, status: result.rows[0].status, idempotentReplay: false };
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw error; }
    finally { client.release(); }
  }

  async publicFeed(branchId?: string) {
    const organizationId = this.organizationId();
    const result = await this.pool.query<{ id: string; branch_id: string | null; scope: string; status: string; version: number; definition: PromotionDefinition; branch_name: string | null; bank_name: string | null }>(
      `SELECT p.id,p.branch_id,p.scope,p.status,v.version,v.definition,b.name AS branch_name,bank.display_name AS bank_name
         FROM customer_promotions p LEFT JOIN branches b ON b.id=p.branch_id AND b.organization_id=p.organization_id
         JOIN LATERAL (SELECT pv.version,pv.definition FROM customer_promotion_versions pv
           WHERE pv.promotion_id=p.id AND pv.organization_id=p.organization_id AND pv.status='approved'
             AND (pv.definition->>'startsAt')::timestamptz<=now() AND (pv.definition->>'endsAt')::timestamptz>now()
             AND pv.definition->>'kind'='announcement'
           ORDER BY pv.version DESC LIMIT 1) v ON true
         LEFT JOIN customer_cashback_partners bank ON bank.organization_id=p.organization_id AND bank.code=v.definition->>'bankCode'
        WHERE p.organization_id=$1 AND p.status IN ('active','scheduled') AND
          (p.branch_id IS NOT NULL AND b.status='active' AND ($2::uuid IS NULL OR p.branch_id=$2::uuid)
           OR p.branch_id IS NULL AND ($2::uuid IS NULL OR v.definition->'targetBranchIds' IS NULL OR v.definition->'targetBranchIds' @> jsonb_build_array($2::text)))
          AND (v.definition->>'kind'<>'cashback' OR bank.status='active')
        ORDER BY (p.scope='branch') DESC,p.updated_at DESC,p.id`, [organizationId, branchId ?? null],
    );
    const now = new Date();
    return result.rows.filter(row => isPromotionActiveAt(row.definition, now)).map(row => ({ ...row.definition, id: row.id, version: row.version, branchName: row.branch_name, bankName: row.bank_name }));
  }

  async preview(input: CreatePromotionDto, principal?: AuthPrincipal, from = new Date()) {
    let definition = this.definition(input);
    if (principal) definition = await this.resolveTargeting(principal, definition);
    return { valid: true, occurrences: previewPromotionOccurrences(definition, from),
      targeting: definition.scope === 'network' ? { branchIds: definition.targetBranchIds ?? [], zones: definition.targetZones ?? [], metric: definition.targetMetric ?? null } : null,
      warnings: definition.recurrence.kind === 'monthly' ? ['Si el día no existe en un mes, esa ocurrencia se omite.'] : [] };
  }

  async uploadImage(principal: AuthPrincipal, input: UploadPromotionImageDto, correlationId: string) {
    if (!uuid(input.commandId)) throw new BadRequestException('El comando de carga no es válido.');
    if (input.scope === 'network') await this.requirePermission(principal, 'promotion.network.manage');
    else {
      if (!input.branchId || !uuid(input.branchId)) throw new BadRequestException('Selecciona una sucursal válida.');
      await this.requirePermission(principal, 'promotion.manage', input.branchId);
      const branch = await this.pool.query('SELECT 1 FROM branches WHERE id=$1 AND organization_id=$2 AND status IN (\'active\',\'configured\',\'draft\')', [input.branchId, principal.organizationId]);
      if (!branch.rowCount) throw new NotFoundException('La sucursal no existe o no permite cargar imágenes.');
    }
    if ((input.scope === 'network' && input.branchId) || (input.scope === 'branch' && !input.branchId)) throw new BadRequestException('El alcance de la imagen no coincide con la sucursal.');
    const bytes = Buffer.from(input.dataBase64, 'base64');
    if (bytes.length < 32 || bytes.length > 1_048_576 || bytes.toString('base64') !== input.dataBase64 || !matchesImageSignature(bytes, input.mimeType)) throw new BadRequestException('La imagen debe ser JPG, PNG o WebP válida de 1 MB o menos.');
    const supabaseUrl = this.config.get<string>('SUPABASE_URL')?.trim();
    const secretKey = this.config.get<string>('SUPABASE_SECRET_KEY')?.trim();
    const bucket = this.config.get<string>('PROMOTION_IMAGE_BUCKET')?.trim() || 'dlc-promotion-images';
    if (!supabaseUrl || !secretKey || !/^[a-z0-9][a-z0-9_-]{2,62}$/.test(bucket)) throw new ServiceUnavailableException('La carga de imágenes promocionales no está configurada.');
    const bytesHash = hash(bytes.toString('base64'));
    const requestHash = hash(stableJson({ bytesHash, mimeType: input.mimeType, scope: input.scope, branchId: input.branchId ?? null }));
    const extension = input.mimeType === 'image/jpeg' ? 'jpg' : input.mimeType === 'image/png' ? 'png' : 'webp';
    const objectPath = `${principal.organizationId}/${input.commandId.toLowerCase()}-${bytesHash}.${extension}`;
    const endpoint = new URL(`/storage/v1/object/${bucket}/${objectPath}`, supabaseUrl);
    const imageUrl = new URL(`/storage/v1/object/public/${bucket}/${objectPath}`, supabaseUrl).toString();
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`promotion-image-command:${principal.organizationId}:${input.commandId.toLowerCase()}`]);
      const prior = await client.query<{ request_hash: string; created_by: string; image_url: string; mime_type: string; byte_size: number }>(
        'SELECT request_hash,created_by,image_url,mime_type,byte_size FROM customer_promotion_images WHERE organization_id=$1 AND command_id=$2',
        [principal.organizationId,input.commandId]);
      if (prior.rows[0]) {
        const saved = prior.rows[0];
        if (saved.request_hash !== requestHash || saved.created_by !== principal.userId) throw new ConflictException('El comando de carga ya se usó con otra imagen o por otra persona.');
        await client.query('COMMIT');
        return { imageUrl: saved.image_url, mimeType: saved.mime_type, bytes: saved.byte_size, idempotentReplay: true };
      }
      let response: Response;
      try {
        response = await fetch(endpoint, { method: 'POST', headers: { apikey: secretKey, 'Content-Type': input.mimeType, 'Cache-Control': 'public, max-age=31536000, immutable', 'x-upsert': 'true' }, body: new Uint8Array(bytes), signal: AbortSignal.timeout(15_000) });
      } catch (error) {
        this.logger.warn(JSON.stringify({ event: 'promotion.image_storage_upload_failed', correlationId, reason: error instanceof Error ? error.name : 'unknown' }));
        throw new ServiceUnavailableException('No se pudo guardar la imagen promocional.');
      }
      if (!response.ok) {
        this.logger.warn(JSON.stringify({ event: 'promotion.image_storage_rejected', correlationId, status: response.status }));
        throw new ServiceUnavailableException('El almacenamiento de imágenes rechazó la carga. Verifica el bucket público de promociones.');
      }
      await client.query(`INSERT INTO customer_promotion_images(organization_id,command_id,request_hash,object_path,image_url,mime_type,byte_size,scope,branch_id,created_by)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, [principal.organizationId,input.commandId,requestHash,objectPath,imageUrl,input.mimeType,bytes.length,input.scope,input.branchId ?? null,principal.userId]);
      await this.audit.appendTransaction(client, { principal, branchId: input.branchId ?? null, correlationId, action: 'promotion.image.uploaded', entityType: 'promotion_image', entityId: objectPath, after: { mimeType: input.mimeType, bytes: bytes.length, scope: input.scope, branchId: input.branchId ?? null } });
      await client.query('COMMIT');
      return { imageUrl, mimeType: input.mimeType, bytes: bytes.length, idempotentReplay: false };
    } catch (error) { await client.query('ROLLBACK').catch(() => undefined); throw error; }
    finally { client.release(); }
  }

  private async transition<T extends { status: string }>(id: string, principal: AuthPrincipal, commandId: string, eventType: string, correlationId: string,
    work: (client: import('pg').PoolClient, promotion: PromotionRow, version: VersionRow) => Promise<T>, payload: Record<string, unknown> = {}) {
    if (!uuid(id) || !uuid(commandId)) throw new BadRequestException('Promoción o comando no válido.');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`promotion:${principal.organizationId}:${id.toLowerCase()}`]);
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`promotion-command:${principal.organizationId}:${commandId.toLowerCase()}`]);
      const replay = await client.query<{ promotion_id: string; event_type: string; actor_id: string; payload: Record<string, unknown> }>(
        'SELECT promotion_id,event_type,actor_id,payload FROM customer_promotion_events WHERE organization_id=$1 AND command_id=$2', [principal.organizationId, commandId]);
      if (replay.rows[0]) {
        if (replay.rows[0].promotion_id !== id || replay.rows[0].event_type !== eventType || replay.rows[0].actor_id !== principal.userId || stableJson(replay.rows[0].payload) !== stableJson(payload)) throw new ConflictException('El comando ya se usó para otra acción.');
        await client.query('COMMIT');
        return { id, status: eventType, idempotentReplay: true } as unknown as T;
      }
      const found = await client.query<PromotionRow>(
        `SELECT id,organization_id,branch_id,scope,status,current_version,active_version,scheduled_version,created_by,approved_by
           FROM customer_promotions WHERE id=$1 AND organization_id=$2 FOR UPDATE`, [id, principal.organizationId]);
      const promotion = found.rows[0];
      if (!promotion) throw new NotFoundException('La promoción no existe.');
      const versionResult = await client.query<VersionRow>(
        `SELECT promotion_id,version,status,definition,created_by,submitted_by FROM customer_promotion_versions
          WHERE promotion_id=$1 AND organization_id=$2 AND version=$3 FOR UPDATE`, [id, principal.organizationId, promotion.current_version]);
      const version = versionResult.rows[0];
      if (!version) throw new ConflictException('La promoción no tiene una versión válida.');
      const output = await work(client, { ...promotion, definition: version.definition }, version);
      await client.query(
        `INSERT INTO customer_promotion_events(organization_id,promotion_id,version,command_id,event_type,actor_id,payload)
         VALUES($1,$2,$3,$4,$5,$6,$7::jsonb)`, [principal.organizationId, id, promotion.current_version, commandId, eventType, principal.userId, JSON.stringify(payload)]);
      await this.audit.appendTransaction(client, { principal, branchId: promotion.branch_id, correlationId, action: `promotion.${eventType}`, entityType: 'customer_promotion', entityId: id, after: { version: promotion.current_version, ...payload } });
      await client.query('COMMIT');
      return { id, ...output, idempotentReplay: false };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      if ((error as { code?: string }).code === '23505') throw new ConflictException('El comando de promoción ya fue registrado.');
      throw error;
    } finally { client.release(); }
  }

  private async requireManager(principal: AuthPrincipal, definition: PromotionDefinition) {
    const permission = definition.scope === 'network' ? 'promotion.network.manage' : 'promotion.manage';
    await this.requirePermission(principal, permission, definition.branchId);
    if (definition.scope === 'branch') {
      const branch = await this.pool.query<{ timezone: string }>('SELECT timezone FROM branches WHERE id=$1 AND organization_id=$2 AND status IN (\'active\',\'configured\',\'draft\')', [definition.branchId, principal.organizationId]);
      if (!branch.rows[0]) throw new NotFoundException('La sucursal no existe o no permite configurar promociones.');
      if (branch.rows[0].timezone !== definition.timeZone) throw new BadRequestException(`La promoción debe usar la zona horaria de la sucursal (${branch.rows[0].timezone}).`);
    } else if (definition.recurrence.kind !== 'once') {
      const timeZones = await this.pool.query<{ time_zone_count: string; time_zone: string | null }>(`SELECT count(DISTINCT timezone)::text AS time_zone_count,min(timezone) AS time_zone FROM branches WHERE organization_id=$1 AND status='active' AND ($2::uuid[] IS NULL OR id=ANY($2::uuid[]))`, [principal.organizationId, definition.targetBranchIds ?? null]);
      if (Number(timeZones.rows[0]?.time_zone_count) > 1 || timeZones.rows[0]?.time_zone !== definition.timeZone) throw new BadRequestException('Una promoción recurrente para toda la red requiere que todas las sucursales activas compartan la zona horaria indicada.');
    }
  }

  private async resolveTargeting(principal: AuthPrincipal, definition: PromotionDefinition): Promise<PromotionDefinition> {
    if (definition.scope !== 'network') return definition;
    await this.requirePermission(principal, 'promotion.network.manage');
    const branchIds = definition.targetBranchIds ?? [];
    const zones = definition.targetZones ?? [];
    const result = await this.pool.query<{ id: string; timezone: string }>(
      `SELECT id,timezone FROM branches WHERE organization_id=$1 AND status='active'
        AND (($2::uuid[] IS NULL AND $3::text[] IS NULL) OR id=ANY($2::uuid[]) OR zone=ANY($3::text[]))
       ORDER BY id`,
      [principal.organizationId, branchIds.length ? branchIds : null, zones.length ? zones : null],
    );
    const candidates = result.rows;
    if (branchIds.some(id => !candidates.some(row => row.id === id))) throw new BadRequestException('Una o más sucursales seleccionadas no pertenecen a la organización activa.');
    let resolvedRows = candidates;
    let targetMetric = definition.targetMetric;
    if (targetMetric) {
      const asOf = new Date();
      const stats = await this.pool.query<{ branch_id: string; observed_value: string; eligible: boolean }>(
        `WITH sales30 AS (
           SELECT s.branch_id,sum(s.total_usd) AS sales_usd
             FROM sales s JOIN sale_collection_balances cb ON cb.id=s.id AND cb.organization_id=s.organization_id AND cb.branch_id=s.branch_id
            WHERE s.organization_id=$1 AND s.occurred_at >= $3::timestamptz - interval '30 days' AND s.occurred_at <= $3::timestamptz AND cb.collection_status='paid'
            GROUP BY s.branch_id
         ), fuel30 AS (
           SELECT s.branch_id,sum(sl.quantity_l) AS liters
             FROM sales s JOIN sale_collection_balances cb ON cb.id=s.id AND cb.organization_id=s.organization_id AND cb.branch_id=s.branch_id
             JOIN sale_lines sl ON sl.sale_id=s.id AND sl.organization_id=s.organization_id AND sl.branch_id=s.branch_id AND sl.kind='fuel'
            WHERE s.organization_id=$1 AND s.occurred_at >= $3::timestamptz - interval '30 days' AND s.occurred_at <= $3::timestamptz AND cb.collection_status='paid'
            GROUP BY s.branch_id
         )
         SELECT b.id AS branch_id,
           CASE WHEN $4='sales_usd_30d' THEN coalesce(s.sales_usd,0) ELSE coalesce(f.liters,0) END::text AS observed_value,
           CASE WHEN $4='sales_usd_30d' THEN coalesce(s.sales_usd,0) >= $2::numeric ELSE coalesce(f.liters,0) >= $2::numeric END AS eligible
          FROM branches b LEFT JOIN sales30 s ON s.branch_id=b.id LEFT JOIN fuel30 f ON f.branch_id=b.id
         WHERE b.organization_id=$1 AND b.status='active'`,
        [principal.organizationId, targetMetric.threshold, asOf.toISOString(), targetMetric.metric],
      );
      const candidateIds = new Set(candidates.map(row => row.id));
      resolvedRows = stats.rows.filter(row => row.eligible && candidateIds.has(row.branch_id))
        .map(row => candidates.find(candidate => candidate.id === row.branch_id)!);
      targetMetric = { ...targetMetric, windowDays: 30, asOf: asOf.toISOString(),
        includedBranches: stats.rows.filter(row => row.eligible && candidateIds.has(row.branch_id))
          .map(row => ({ branchId: row.branch_id, observedValue: row.observed_value })) };
    }
    const resolved = resolvedRows.map(row => row.id);
    if (resolved.length === 0) throw new BadRequestException(targetMetric ? 'Ninguna sucursal cumple el umbral estadístico dentro de la audiencia elegida.' : 'La audiencia no contiene sucursales activas.');
    if (new Set(resolvedRows.map(row => row.timezone)).size !== 1 || resolvedRows[0]!.timezone !== definition.timeZone)
      throw new BadRequestException('Las sucursales objetivo deben compartir la zona horaria configurada en la campaña.');
    return { ...definition, targetBranchIds: resolved, ...(targetMetric ? { targetMetric } : {}) };
  }

  private async requirePermission(principal: AuthPrincipal, permission: string, branchId?: string) {
    const capabilities = await this.auth.capabilities(principal, branchId);
    if (!capabilities.includes(permission)) throw new ForbiddenException('No tienes permiso para esta acción en el ámbito de la promoción.');
  }

  private async requireBankPartner(organizationId: string, definition: PromotionDefinition, queryable: Pick<Pool | PoolClient, 'query'> = this.pool) {
    if (definition.kind !== 'cashback') return;
    const result = await queryable.query(`SELECT 1 FROM customer_cashback_partners WHERE organization_id=$1 AND code=$2 AND status='active'${queryable !== this.pool ? ' FOR SHARE' : ''}`, [organizationId, definition.bankCode]);
    if (!result.rowCount) throw new BadRequestException('Selecciona un banco participante activo configurado por la organización.');
  }

  private organizationId(): string {
    const value = this.config.get<string>('CUSTOMER_ORGANIZATION_ID')?.trim();
    if (!value || !uuid(value)) throw new ServiceUnavailableException('El dominio de promociones no está configurado.');
    return value;
  }

  private definition(input: CreatePromotionDto): PromotionDefinition {
    try {
      return validatePromotionDefinition({
        title: input.title, motive: input.motive, kind: input.kind, scope: input.scope,
      ...(input.branchId ? { branchId: input.branchId.toLowerCase() } : {}),
        ...(input.targetBranchIds ? { targetBranchIds: [...input.targetBranchIds].map(id => id.toLowerCase()).sort() } : {}),
        ...(input.targetZones ? { targetZones: [...input.targetZones].sort() } : {}),
        ...(input.targetMetric ? { targetMetric: { metric: input.targetMetric.metric, threshold: input.targetMetric.threshold } } : {}),
        startsAt: normalizePromotionBoundary(input.startsAt, input.timeZone, 'start'), endsAt: normalizePromotionBoundary(input.endsAt, input.timeZone, 'end'),
        timeZone: input.timeZone, recurrence: normalizeRecurrence(input.recurrence),
        ...(input.productIds ? { productIds: input.productIds.map(id => id.toLowerCase()) } : {}),
        ...(input.serviceModes ? { serviceModes: input.serviceModes } : {}),
        ...(input.value === undefined ? {} : { value: input.value }), ...(input.valueUnit === undefined ? {} : { valueUnit: input.valueUnit }), ...(input.bankCode === undefined ? {} : { bankCode: input.bankCode }),
        ...(input.minimumSpendUsd === undefined ? {} : { minimumSpendUsd: input.minimumSpendUsd }), ...(input.benefitCapUsd === undefined ? {} : { benefitCapUsd: input.benefitCapUsd }),
        ...(input.totalBudgetUsd === undefined ? {} : { totalBudgetUsd: input.totalBudgetUsd }), ...(input.maxUsesPerCustomer === undefined ? {} : { maxUsesPerCustomer: input.maxUsesPerCustomer }),
        priority: input.priority, stacking: input.stacking, terms: input.terms,
        ...(input.imageUrl === undefined ? {} : { imageUrl: input.imageUrl }), ...(input.imageAlt === undefined ? {} : { imageAlt: input.imageAlt }),
      });
    } catch (error) { throw new BadRequestException(error instanceof Error ? error.message : 'La definición de promoción no es válida.'); }
  }

  private async requireRegisteredImage(organizationId: string, definition: PromotionDefinition) {
    if (!definition.imageUrl) return;
    const result = await this.pool.query<{ scope: string; branch_id: string | null }>(
      'SELECT scope,branch_id FROM customer_promotion_images WHERE organization_id=$1 AND image_url=$2', [organizationId, definition.imageUrl]);
    const image = result.rows[0];
    if (!image || image.scope !== definition.scope || image.branch_id !== (definition.branchId ?? null)) {
      throw new BadRequestException('La imagen debe cargarse desde este sistema y pertenecer al mismo alcance/sucursal de la promoción.');
    }
  }

  private async notifyEligibleCustomers(client: import('pg').PoolClient, organizationId: string, promotionId: string, definition: PromotionDefinition) {
    if (definition.scope === 'branch') return; // Customer accounts do not yet have a branch preference to target safely.
    if (definition.targetBranchIds?.length) {
      const active = await client.query<{ count: string }>(`SELECT count(*)::text AS count FROM branches WHERE organization_id=$1 AND status='active'`, [organizationId]);
      if (Number(active.rows[0]?.count) !== definition.targetBranchIds.length) return; // Never notify customers outside a targeted audience.
    }
    await client.query(
      `INSERT INTO customer_notification_inbox(organization_id,customer_id,event_type,title,body,image_url,target_type,target_id,dedupe_key)
       SELECT c.organization_id,c.id,'promotion_published',$2,$3,$4,'promotion',$5,'promotion:'||$5::text||':published:'||c.id::text
         FROM customer_accounts c
        WHERE c.organization_id=$1 AND c.status='active' AND c.communications_consent=true AND $6::uuid IS NULL
       ON CONFLICT (organization_id,customer_id,dedupe_key) DO NOTHING`,
      [organizationId, `Nueva promoción: ${definition.title}`, definition.motive.slice(0, 500), definition.imageUrl ?? null, promotionId, definition.branchId ?? null],
    );
  }
}

interface PromotionRow { id: string; organization_id: string; branch_id: string | null; scope: string; status: string; current_version: number; active_version: number | null; scheduled_version: number | null; created_by: string; approved_by: string | null; definition: PromotionDefinition; }
interface VersionRow { promotion_id: string; version: number; status: string; definition: PromotionDefinition; created_by: string; submitted_by: string | null; }
function uuid(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function hash(value: string): string { return createHash('sha256').update(value).digest('hex'); }
function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value !== null && typeof value === 'object') return `{${Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([key, item]) => `${JSON.stringify(key)}:${stableJson(item)}`).join(',')}}`;
  return JSON.stringify(value);
}
function matchesImageSignature(bytes: Buffer, mimeType: string): boolean {
  let width = 0, height = 0;
  if (mimeType === 'image/png') {
    if (bytes.length < 24 || !bytes.subarray(0,8).equals(Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])) || bytes.toString('ascii',12,16) !== 'IHDR') return false;
    width = bytes.readUInt32BE(16); height = bytes.readUInt32BE(20);
  } else if (mimeType === 'image/jpeg') {
    if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return false;
    let offset = 2;
    while (offset + 4 < bytes.length) {
      if (bytes[offset] !== 0xff) return false;
      while (bytes[offset] === 0xff) offset++;
      const marker = bytes[offset++]!;
      if ([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(marker)) {
        if (offset + 7 >= bytes.length) return false;
        height = bytes.readUInt16BE(offset + 3); width = bytes.readUInt16BE(offset + 5); break;
      }
      if (marker === 0xd9 || marker === 0xda || offset + 2 > bytes.length) return false;
      const segmentLength = bytes.readUInt16BE(offset);
      if (segmentLength < 2 || offset + segmentLength > bytes.length) return false;
      offset += segmentLength;
    }
  } else if (mimeType === 'image/webp') {
    if (bytes.length < 30 || bytes.toString('ascii',0,4) !== 'RIFF' || bytes.toString('ascii',8,12) !== 'WEBP') return false;
    const chunk = bytes.toString('ascii',12,16);
    if (chunk === 'VP8X') { width = 1 + bytes.readUIntLE(24,3); height = 1 + bytes.readUIntLE(27,3); }
    else if (chunk === 'VP8 ' && bytes[23] === 0x9d && bytes[24] === 0x01 && bytes[25] === 0x2a) { width = bytes.readUInt16LE(26) & 0x3fff; height = bytes.readUInt16LE(28) & 0x3fff; }
    else if (chunk === 'VP8L' && bytes[20] === 0x2f) {
      width = 1 + bytes[21]! + ((bytes[22]! & 0x3f) << 8);
      height = 1 + ((bytes[22]! & 0xc0) >> 6) + (bytes[23]! << 2) + ((bytes[24]! & 0x0f) << 10);
    } else return false;
  } else return false;
  return width > 0 && height > 0 && width <= 4096 && height <= 4096 && width * height <= 8_000_000;
}

function normalizeRecurrence(value: CreatePromotionDto['recurrence']): PromotionRecurrence {
  if (value.kind === 'once') return { kind: 'once' };
  if (value.kind === 'weekly' && value.weekdays) return { kind: 'weekly', weekdays: value.weekdays };
  if (value.kind === 'monthly' && value.dayOfMonth) return { kind: 'monthly', dayOfMonth: value.dayOfMonth };
  throw new BadRequestException('La recurrencia requiere sus campos específicos.');
}
