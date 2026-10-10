import { BadRequestException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Decimal } from 'decimal.js';
import { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AuthService } from '../auth/auth.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthPrincipal } from '../auth/auth.types.js';
@Injectable()
export class MetricsService {
 constructor(@Inject(PG_POOL) private readonly pool:Pool,private readonly auth:AuthService,private readonly audit:AuditService){}
 async setInventoryPolicy(id:string,p:AuthPrincipal,input:{warningPercent:unknown;criticalPercent:unknown},correlation:string){
  if(!(await this.auth.capabilities(p)).includes('branch.manage'))throw new ForbiddenException('Configuración de red restringida.');
  const warning=percent(input.warningPercent),critical=percent(input.criticalPercent);
  if(warning===null||critical===null||critical>=warning)throw new BadRequestException('Umbrales inválidos: 0 < crítico < aviso < 100.');
  const client=await this.pool.connect();
  try{
   await client.query('BEGIN');
   const b=await client.query(`SELECT id FROM branches WHERE id=$1 AND organization_id=$2 AND status='active' FOR UPDATE`,[id,p.organizationId]);
   if(!b.rows[0])throw new NotFoundException('Sucursal fuera de tu red.');
   const r=await client.query(`INSERT INTO branch_inventory_alert_policies(branch_id,organization_id,warning_percent,critical_percent,updated_by)
    VALUES($1,$2,$3,$4,$5) ON CONFLICT(branch_id) DO UPDATE SET warning_percent=EXCLUDED.warning_percent,
    critical_percent=EXCLUDED.critical_percent,updated_by=EXCLUDED.updated_by,updated_at=clock_timestamp()
    RETURNING warning_percent::text AS "warningPercent",critical_percent::text AS "criticalPercent",updated_at AS "updatedAt"`,
    [id,p.organizationId,warning,critical,p.userId]);
   await this.audit.appendTransaction(client,{principal:p,branchId:id,correlationId:correlation,
    action:'inventory.alert_policy.updated',entityType:'branch_inventory_alert_policy',entityId:id,after:r.rows[0]});
   await client.query('COMMIT');return {data:r.rows[0]};
  }catch(error){await client.query('ROLLBACK').catch(()=>undefined);throw error;}finally{client.release();}
 }
 async branch(id:string,p:AuthPrincipal){
  const capabilities=await this.auth.capabilities(p,id);
  if(!capabilities.includes('inventory.read'))throw new ForbiddenException('No puedes consultar el inventario.');
  const b=await this.pool.query<{id:string;name:string;timezone:string;countryCode:string;today:string}>(`SELECT id,name,timezone,country_code AS "countryCode",
   (clock_timestamp() AT TIME ZONE timezone)::date::text AS today
   FROM branches WHERE id=$1 AND organization_id=$2 AND status='active'`,[id,p.organizationId]);
  if(!b.rows[0])throw new NotFoundException('Sucursal fuera de tu ámbito.');
  const {today}=b.rows[0];
  const [tanks,cuts,incidents,maintenance,anomalies]=await Promise.all([
   this.pool.query(`SELECT t.id,t.code,t.name,f.display_name AS "fuelName",f.family,
    t.status,t.nominal_capacity_l::text AS "capacityLiters",t.safe_fill_limit_l::text AS "safeLimitLiters",
    t.unusable_reserve_l::text AS "unusableReserveLiters",
    bal.on_hand_l::text AS "onHandLiters",bal.valuation_quality AS "valuationQuality",bal.updated_at AS "updatedAt",
    COALESCE(policy.warning_percent,20)::text AS "warningPercent",
    COALESCE(policy.critical_percent,10)::text AS "criticalPercent"
    FROM tanks t JOIN fuel_products f ON f.id=t.fuel_product_id
    LEFT JOIN tank_inventory_balances bal ON bal.tank_id=t.id
    LEFT JOIN branch_inventory_alert_policies policy ON policy.branch_id=t.branch_id
    WHERE t.organization_id=$1 AND t.branch_id=$2 AND t.status<>'decommissioned' ORDER BY f.family,t.code`,
    [p.organizationId,id]),
   this.pool.query(`SELECT c.id,c.slot,c.status,c.starts_at AS "startsAt",c.ends_at AS "endsAt",
    cl.closed_at AS "closedAt",cl.closed_by AS "closedBy",p.review_required AS "reviewRequired",
    CASE WHEN $4 AND cl.id IS NOT NULL THEN p.financial_summary->>'salesUsd' END AS "closedSalesUsd",
    (SELECT count(DISTINCT d.dispenser_id)::integer FROM operational_cut_dispensers d
     WHERE d.cut_id=c.id AND d.physical_status='active') AS "expectedDispensers",
    (SELECT count(DISTINCT n.dispenser_id)::integer FROM operational_cut_nozzles n
     JOIN operational_cut_meter_captures m ON m.cut_id=n.cut_id AND m.nozzle_id=n.nozzle_id
     WHERE n.cut_id=c.id AND n.participation='expected') AS "registeredDispensers",
    (SELECT count(*)::integer FROM operational_cut_nozzles n WHERE n.cut_id=c.id AND n.participation='expected') AS "expectedNozzles",
    (SELECT count(*)::integer FROM operational_cut_meter_captures m WHERE m.cut_id=c.id) AS "registeredNozzles"
    FROM operational_cuts c LEFT JOIN operational_cut_closures cl ON cl.cut_id=c.id
    LEFT JOIN operational_cut_preparations p ON p.cut_id=c.id
    WHERE c.organization_id=$1 AND c.branch_id=$2 AND c.operational_date=$3::date
    ORDER BY c.slot`,[p.organizationId,id,today,capabilities.includes('sale.read')]),
   capabilities.includes('incident.read')?this.pool.query(`SELECT id,severity,status,category,description,occurred_at AS "occurredAt"
    FROM incidents WHERE organization_id=$1 AND branch_id=$2 AND status NOT IN('resolved','closed')
    ORDER BY CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 ELSE 2 END,occurred_at DESC LIMIT 5`,
    [p.organizationId,id]):Promise.resolve({rows:[]}),
   this.pool.query(`SELECT count(*)::integer AS open FROM maintenance_work_orders WHERE organization_id=$1 AND branch_id=$2
    AND status IN('planned','in_progress','completed')`,[p.organizationId,id]),
   capabilities.includes('incident.read')?this.pool.query(`SELECT id,rule_code AS "ruleCode",asset_key AS "assetKey",status,created_at AS "createdAt"
    FROM anomaly_alerts WHERE organization_id=$1 AND branch_id=$2 AND status IN('open','investigating')
    ORDER BY created_at DESC LIMIT 10`,[p.organizationId,id]):Promise.resolve({rows:[]}),
  ]);
  const inventory=tanks.rows.map(t=>({...t,percentage:t.onHandLiters===null?null:
   new Decimal(t.onHandLiters).div(t.capacityLiters).mul(100).toDecimalPlaces(1).toString(),
   usableLiters:t.onHandLiters===null?null:Decimal.max(0,new Decimal(t.onHandLiters).minus(t.unusableReserveLiters)).toFixed(3)}));
  const missing=inventory.filter(t=>t.onHandLiters===null).length;
  const total=missing?null:inventory.reduce((a,t)=>a.plus(t.onHandLiters!),new Decimal(0)).toFixed(3);
  const capacity=inventory.reduce((a,t)=>a.plus(t.capacityLiters),new Decimal(0)).toFixed(3);
  const lastSource=[...inventory.map(t=>t.updatedAt),...cuts.rows.map(t=>t.closedAt)]
   .filter((v):v is string=>!!v).map(v=>new Date(v).toISOString()).sort().at(-1)??null;
  const alerts=[
   ...(cuts.rows.length!==2?[{key:`cut-schedule:${id}:${today}`,severity:'high',
    title:'Cortes del día incompletos',detail:`${cuts.rows.length} de 2 cortes programados`,
    status:'open',action:{kind:'cut-calendar',id}}]:[]),
   ...inventory.filter(t=>t.onHandLiters===null).map(t=>({key:`tank-unmeasured:${t.id}`,severity:'high',
    title:`Medición pendiente: ${t.fuelName}`,detail:'Sin saldo inicial; no se puede estimar capacidad disponible.',
    status:'open',action:{kind:'tank',id:t.id}})),
   ...inventory.filter(t=>t.percentage!==null&&new Decimal(t.percentage).lt(t.warningPercent)).map(t=>({
    key:`tank-low:${t.id}`,severity:new Decimal(t.percentage!).lt(t.criticalPercent)?'critical':'high',
    title:`Inventario bajo: ${t.fuelName}`,detail:`${t.percentage}% de capacidad · ${t.onHandLiters} L · aviso <${t.warningPercent}%`,
    status:'open',action:{kind:'tank',id:t.id}})),
   ...(capabilities.includes('incident.read')?incidents.rows.map(i=>({key:`incident:${i.id}`,severity:i.severity,
    title:'Incidencia sin resolver',detail:i.description,status:i.status,action:{kind:'incident',id:i.id}})):[]),
   ...anomalies.rows.map(a=>({key:`anomaly:${a.id}`,severity:'high',title:'Variación de corte pendiente',
    detail:`${a.ruleCode} · ${a.assetKey}`,status:a.status,action:{kind:'anomaly',id:a.id}})),
  ];
  return {data:{branch:{id:b.rows[0].id,name:b.rows[0].name,timezone:b.rows[0].timezone,countryCode:b.rows[0].countryCode},
   operationalDate:today,cuts:cuts.rows,inventory:{tanks:inventory,totalLiters:total,capacityLiters:capacity,
    missingBaselines:missing,source:'current_inventory_ledger'},openIncidents:capabilities.includes('incident.read')?incidents.rows:[],alerts,
   openMaintenanceOrders:maintenance.rows[0]?.open??0,lastSourceAt:lastSource,
   metricSources:{sales:'closed_cut_snapshot',inventory:'current_inventory_ledger',incidents:'active_incident_records'}}};
 }
 async network(p:AuthPrincipal,daysRaw?:string,selected?:string,countryRaw?:string){
  const global=await this.auth.capabilities(p);
  if(!global.includes('branch.read'))throw new ForbiddenException('La red requiere permiso global.');
  const days=Number(daysRaw??'7');
  if(![1,7,30].includes(days)||selected!==undefined&&!uuid(selected)||countryRaw!==undefined&&countryRaw!==''&&!/^[A-Za-z]{2}$/.test(countryRaw))throw new BadRequestException('Filtro de red inválido.');
  const country=countryRaw?countryRaw.toUpperCase():undefined;
  const branches=await this.pool.query<{id:string;name:string;code:string;timezone:string;country_code:string;effective_date:string;today:string}>(`SELECT id,name,code,timezone,country_code,
   (COALESCE(opened_at,created_at) AT TIME ZONE timezone)::date::text AS effective_date,
   (clock_timestamp() AT TIME ZONE timezone)::date::text AS today
   FROM branches WHERE organization_id=$1 AND status='active' AND ($2::uuid IS NULL OR id=$2) AND ($3::text IS NULL OR country_code=$3)
   ORDER BY name,id`,[p.organizationId,selected??null,country??null]);
  if(selected&&!branches.rows[0])throw new NotFoundException('Sucursal fuera de la red.');
  const countries=await this.pool.query<{countryCode:string;branchCount:number}>(`SELECT country_code AS "countryCode",count(*)::integer AS "branchCount"
   FROM branches WHERE organization_id=$1 AND status='active' GROUP BY country_code ORDER BY country_code`,[p.organizationId]);
  const canInventory=global.includes('inventory.read'),canSales=global.includes('sale.read');
  const [cutSummary,productSummary,inventory,daily]=await Promise.all([
   this.pool.query(`SELECT c.branch_id,count(*) FILTER(WHERE cl.id IS NOT NULL)::integer AS closed,
    max(cl.closed_at) AS last_closed_at FROM operational_cuts c
    JOIN branches b ON b.id=c.branch_id LEFT JOIN operational_cut_closures cl ON cl.cut_id=c.id
    WHERE c.organization_id=$1 AND c.branch_id=ANY($2::uuid[])
     AND c.operational_date >= (clock_timestamp() AT TIME ZONE b.timezone)::date-$3::integer+1
     AND c.operational_date <= (clock_timestamp() AT TIME ZONE b.timezone)::date
    GROUP BY c.branch_id`,[p.organizationId,branches.rows.map(x=>x.id),days]),
   canSales?this.pool.query(`SELECT c.branch_id,x.item->>'fuelProductId' AS "fuelProductId",f.display_name AS "fuelName",f.family,
    sum((x.item->>'soldLiters')::numeric)::text AS "soldLiters",
    sum((x.item->>'salesUsd')::numeric)::text AS "salesUsd"
    FROM operational_cuts c JOIN branches b ON b.id=c.branch_id
    JOIN operational_cut_closures cl ON cl.cut_id=c.id
    JOIN operational_cut_preparations p ON p.id=cl.preparation_id
    CROSS JOIN LATERAL jsonb_array_elements(p.product_summary) x(item)
    JOIN fuel_products f ON f.id=(x.item->>'fuelProductId')::uuid
    WHERE c.organization_id=$1 AND c.branch_id=ANY($2::uuid[])
     AND c.operational_date >= (clock_timestamp() AT TIME ZONE b.timezone)::date-$3::integer+1
     AND c.operational_date <= (clock_timestamp() AT TIME ZONE b.timezone)::date
    GROUP BY c.branch_id,x.item->>'fuelProductId',f.display_name,f.family`,
    [p.organizationId,branches.rows.map(x=>x.id),days]):Promise.resolve({rows:[]}),
   canInventory?this.pool.query(`SELECT t.branch_id,t.fuel_product_id,f.display_name AS "fuelName",f.family,
    sum(bal.on_hand_l)::text AS "onHandLiters",sum(t.nominal_capacity_l)::text AS "capacityLiters",
    count(*) FILTER(WHERE bal.tank_id IS NULL)::integer AS "missingBaselines",
    max(bal.updated_at) AS "updatedAt",
    min(bal.on_hand_l / NULLIF(t.nominal_capacity_l,0) * 100)::text AS "minimumPercent",
    max(COALESCE(policy.warning_percent,20))::text AS "warningPercent",
    max(COALESCE(policy.critical_percent,10))::text AS "criticalPercent"
    FROM tanks t JOIN fuel_products f ON f.id=t.fuel_product_id
    LEFT JOIN tank_inventory_balances bal ON bal.tank_id=t.id
    LEFT JOIN branch_inventory_alert_policies policy ON policy.branch_id=t.branch_id
    WHERE t.organization_id=$1 AND t.branch_id=ANY($2::uuid[]) AND t.status<>'decommissioned'
    GROUP BY t.branch_id,t.fuel_product_id,f.display_name,f.family`,
    [p.organizationId,branches.rows.map(x=>x.id)]):Promise.resolve({rows:[]}),
   canSales?this.pool.query(`SELECT c.operational_date::text AS date,
    count(*)::integer AS "closedCuts",
    sum((prep.financial_summary->>'salesUsd')::numeric)::text AS "salesUsd",
    sum(COALESCE(items.sold_l,0))::text AS "soldLiters"
    FROM operational_cuts c JOIN branches b ON b.id=c.branch_id
    JOIN operational_cut_closures cl ON cl.cut_id=c.id
    JOIN operational_cut_preparations prep ON prep.id=cl.preparation_id
    LEFT JOIN LATERAL (SELECT sum((item.value->>'soldLiters')::numeric) AS sold_l
     FROM jsonb_array_elements(prep.product_summary) item(value)) items ON true
    WHERE c.organization_id=$1 AND c.branch_id=ANY($2::uuid[])
     AND c.operational_date >= (clock_timestamp() AT TIME ZONE b.timezone)::date-$3::integer+1
     AND c.operational_date <= (clock_timestamp() AT TIME ZONE b.timezone)::date
    GROUP BY c.operational_date ORDER BY c.operational_date`,
    [p.organizationId,branches.rows.map(x=>x.id),days]):Promise.resolve({rows:[]}),
  ]);
  const byBranch=branches.rows.map(b=>{
   const closure=cutSummary.rows.find(x=>x.branch_id===b.id);
   const localToday=b.today;
   const activeDays=Math.min(days,Math.max(0,Math.floor((Date.parse(localToday)-Date.parse(b.effective_date))/86400000)+1));
   const products=inventory.rows.filter(x=>x.branch_id===b.id);
   const risk=products.some(x=>x.missingBaselines>0)?'unknown':
    products.some(x=>x.minimumPercent!==null&&new Decimal(x.minimumPercent).lt(x.criticalPercent))?'critical':
    products.some(x=>x.minimumPercent!==null&&new Decimal(x.minimumPercent).lt(x.warningPercent))?'warning':'normal';
   return {id:b.id,name:b.name,code:b.code,countryCode:b.country_code,inventoryRisk:products.length?risk:'unknown',
    closedCuts:closure?.closed??0,expectedCuts:activeDays*2,
    lastClosedAt:closure?.last_closed_at??null,
    products:productSummary.rows.filter(x=>x.branch_id===b.id),
    tanks:products};
  });
  const closed=byBranch.reduce((n,b)=>n+b.closedCuts,0),expected=byBranch.reduce((n,b)=>n+b.expectedCuts,0);
  const lastSource=[...byBranch.map(x=>x.lastClosedAt),...inventory.rows.map(x=>x.updatedAt)]
   .filter((v):v is string=>!!v).map(v=>new Date(v).toISOString()).sort().at(-1)??null;
  return {data:{periodDays:days,scopeBranchId:selected??null,scopeCountryCode:country??null,countries:countries.rows,activeBranchCount:byBranch.length,
   cutCoverage:{closed,expected},branches:byBranch,dailySeries:daily.rows,lastSourceAt:lastSource,
   metricSources:{sales:canSales?'closed_cut_snapshot':null,inventory:canInventory?'current_inventory_ledger':null},
   permissions:{sales:canSales,inventory:canInventory}}};
 }
}
function uuid(v:unknown):v is string{return typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);}
function percent(v:unknown):string|null{
 if(typeof v!=='string'&&typeof v!=='number')return null;
 const text=String(v);
 return /^(?:[1-9]\d?|0)(?:\.\d{1,2})?$/.test(text)&&Number(text)>0&&Number(text)<100?text:null;
}
