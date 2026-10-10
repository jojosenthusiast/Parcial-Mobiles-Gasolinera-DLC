// Resumen: alert strip -> one hero KPI + three secondary -> tank gauges, sales trend, branch comparison.
// Filters (period, scope) live outside the region, so changing them repaints only the region and keeps the old data visible.
import { icon } from './icons.js';
import { esc, emptyMarkup, errorMarkup, segmentedMarkup, bindSegmented, skeletonMarkup, kpiMarkup } from './components.js';
import { createModuleView, cacheKey, settleAll } from './module-view.js';
import { animateRegion, gaugeGridMarkup, hbarsMarkup, fuelClass } from './charts.js';
import { statusBadge } from './labels.js';
import { aggregateTanksByFuel, countryName, salesTrendSvg } from './panel-lib.js';
import { formatClock, formatDateTime, formatMoney, formatNumber, formatVolume, formatDay, formatSubtotals, NO_DATA } from './format.js';
import { getPrefs } from './prefs.js';
import { mergeNetwork, sliceRequests, summarizeBranch, summarizeNetwork, fuelBreakdown, tankPercent } from './dashboard-model.js';

const PERIODS = [{ value: '1', label: 'Hoy' }, { value: '7', label: '7 días' }, { value: '30', label: '30 días' }];
const SEVERITY_ICON = { crit: 'alert-triangle', warn: 'alert-circle' };

export function alertStripMarkup(alerts, { limit = 3 } = {}) {
  if (!alerts.length) return `<section class="alert-strip alert-strip--ok" aria-label="Alertas"><div class="alert-strip-head">${icon('circle-check', { size: 22 })}<span class="grow">Sin alertas por ahora. Los tanques y cortes están en orden.</span></div></section>`;
  const crit = alerts.filter(a => a.severity === 'crit').length;
  const tone = crit ? 'crit' : 'warn';
  const item = a => `<li class="alert-item is-${a.severity}">${icon(SEVERITY_ICON[a.severity] || 'alert-circle', { size: 20 })}<div><b>${esc(a.title)}</b><small>${esc(a.detail)}</small></div><button type="button" class="btn btn-ghost btn-sm alert-go" data-go="${esc(a.page)}"${a.branchId ? ` data-branch="${esc(a.branchId)}"` : ''}>Ver${icon('chevron-right', { size: 16 })}</button></li>`;
  const first = alerts.slice(0, limit); const rest = alerts.slice(limit);
  return `<section class="alert-strip alert-strip--${tone}" aria-label="Alertas" role="region"><div class="alert-strip-head">${icon(SEVERITY_ICON[tone], { size: 22 })}<span class="grow">${crit ? `${crit} ${crit === 1 ? 'alerta crítica' : 'alertas críticas'}` : `${alerts.length} ${alerts.length === 1 ? 'aviso' : 'avisos'}`} · ${alerts.length} en total</span></div><ul class="alert-strip-list">${first.map(item).join('')}</ul>${rest.length ? `<details class="chart-details"><summary>Ver ${rest.length} más</summary><ul class="alert-strip-list">${rest.map(item).join('')}</ul></details>` : ''}</section>`;
}

function salesHero(summary, merged, days) {
  const [top, ...others] = summary.sales;
  const periodText = days === 1 ? 'hoy' : `últimos ${days} días`;
  if (!top) return kpiMarkup({ label: 'Ventas del periodo', value: NO_DATA, note: 'Sin ventas en cortes cerrados', icon: 'banknote', size: 'hero' });
  const more = others.length ? `Otras monedas: ${formatSubtotals(others.map(o => ({ currency: o.currency, total: o.total })))}` : '';
  const note = `${formatVolume(summary.liters)} vendidos · ${periodText}${more ? ` · ${more}` : ''}`;
  return kpiMarkup({ label: `Ventas del periodo (${top.currency})`, value: formatMoney(top.total, { currency: top.currency, withCode: false }), unit: top.currency, note, icon: 'banknote', size: 'hero', count: { value: top.total, decimals: getPrefs().decimals } });
}

function kpiBoard(summary, merged, params, canSales) {
  const hero = canSales ? salesHero(summary, merged, params.days) : kpiMarkup({ label: 'Sucursales activas', value: String(summary.branchCount), note: 'En el alcance actual', icon: 'store', size: 'hero' });
  const coverage = summary.coveragePercent === null ? NO_DATA : `${summary.coveragePercent} %`;
  return `<div class="kpi-board">${hero}${kpiMarkup({ label: 'Cortes cerrados', value: `${summary.closed} / ${summary.expected}`, note: `Cobertura ${coverage}`, icon: 'clock', size: 'standard' })}${kpiMarkup({ label: 'Tanques en riesgo', value: String(summary.critical), tone: summary.critical ? 'crit' : 'ok', note: summary.critical ? 'Sucursales con nivel crítico' : `${summary.warn} con nivel medio`, icon: 'drop', size: 'standard' })}${kpiMarkup({ label: 'Sucursales activas', value: String(summary.branchCount), note: canSales ? 'En el alcance actual' : 'Sin acceso a ventas', icon: 'store', size: 'standard' })}</div>`;
}

function trendCard(merged, days) {
  if (!merged.permissions.sales) return `<article class="card"><div class="section-head"><h2>Tendencia de ventas</h2></div>${emptyMarkup({ icon: 'lock', title: 'Sin permiso para ventas', text: 'Tu cuenta no consulta métricas de ventas.', compact: true })}</article>`;
  if (!merged.series.length) return `<article class="card"><div class="section-head"><h2>Tendencia de ventas</h2></div>${emptyMarkup({ icon: 'trend-up', title: 'Aún no hay ventas', text: 'Aparecerán cuando se cierren cortes en este periodo.', compact: true })}</article>`;
  const charts = merged.series.map(({ currency, daily }) => {
    const money = v => formatMoney(v, { currency });
    const svg = salesTrendSvg(daily, { money, number: v => formatNumber(v, { decimals: 0 }), dayLabel: d => formatDay(d.date) });
    const rows = daily.map(d => `<tr><td>${esc(formatDay(d.date))}</td><td class="num">${d.closedCuts}</td><td class="num">${esc(money(d.salesUsd))}</td><td class="num">${esc(formatVolume(d.soldLiters))}</td></tr>`).join('');
    return `${merged.series.length > 1 ? `<span class="currency-tag">${esc(currency)}</span>` : ''}${svg}<details class="chart-details"><summary>Ver valores exactos por día</summary><div class="table-wrap" tabindex="0" role="group" aria-label="Tabla desplazable horizontalmente"><table class="data-table"><thead><tr><th scope="col">Fecha</th><th scope="col" class="num">Cortes</th><th scope="col" class="num">Ventas</th><th scope="col" class="num">Volumen</th></tr></thead><tbody>${rows}</tbody></table></div></details>`;
  }).join('');
  return `<article class="card"><div class="section-head"><div><h2>Tendencia de ventas</h2><p class="branch-meta">Solo cortes cerrados · ${days === 1 ? 'hoy' : `${days} días`}</p></div></div>${charts}</article>`;
}

function comparisonCard(merged) {
  const withSales = merged.branches.filter(b => b.sales > 0);
  if (!merged.permissions.sales) return '';
  if (!withSales.length) return `<article class="card"><div class="section-head"><h2>Comparación entre sucursales</h2></div>${emptyMarkup({ icon: 'chart-bar', title: 'Sin ventas por sucursal', text: 'Cierra cortes para comparar sucursales.', compact: true })}</article>`;
  const groups = new Map();
  for (const b of withSales) groups.set(b.currency, [...(groups.get(b.currency) || []), b]);
  const body = [...groups].map(([currency, rows]) => `${groups.size > 1 ? `<span class="currency-tag">${esc(currency)}</span>` : ''}${hbarsMarkup(rows.sort((a, c) => c.sales - a.sales).map(b => ({ label: b.name, chip: b.countryCode, value: b.sales, valueText: formatMoney(b.sales, { currency }), sub: `${formatVolume(b.liters)} · ${b.closedCuts ?? 0}/${b.expectedCuts ?? 0} cortes` })))}`).join('');
  return `<article class="card"><div class="section-head"><div><h2>Comparación entre sucursales</h2><p class="branch-meta">Ventas del periodo, ordenadas de mayor a menor</p></div></div>${body}</article>`;
}

function fuelCard(merged) {
  const rows = fuelBreakdown(merged.branches).filter(r => r.liters > 0);
  const body = rows.length
    ? hbarsMarkup(rows.map(r => ({ label: r.name, family: fuelClass(r.family), value: r.liters, valueText: formatVolume(r.liters), sub: [...r.sales].map(([c, v]) => formatMoney(v, { currency: c })).join(' · ') })))
    : emptyMarkup({ icon: 'drop', title: 'Sin volumen vendido', text: 'No hay litros en cortes cerrados de este periodo.', compact: true });
  return `<article class="card"><div class="section-head"><div><h2>Venta por combustible</h2><p class="branch-meta">Volumen en ${getPrefs().volumeUnit === 'gallons' ? 'galones' : 'litros'}; el importe se muestra por moneda</p></div></div>${body}</article>`;
}

function tanksCard(merged) {
  if (!merged.permissions.inventory) return `<article class="card"><div class="section-head"><h2>Nivel de tanques</h2></div>${emptyMarkup({ icon: 'lock', title: 'Sin permiso para inventario', compact: true })}</article>`;
  const rows = aggregateTanksByFuel(merged.branches);
  const items = rows.map(r => ({ name: r.name, family: r.family, percent: r.percentage, caption: r.capacity > 0 ? `${formatVolume(r.onHand)} de ${formatVolume(r.capacity)}` : '', detail: r.minimumPercent === null ? '' : `Mínimo ${Math.round(r.minimumPercent)} %` }));
  return `<article class="card"><div class="section-head"><div><h2>Nivel de tanques por combustible</h2><p class="branch-meta">Existencia sobre capacidad en el alcance actual</p></div><button type="button" class="text-button" data-go="inventory">Inventario${icon('chevron-right', { size: 16 })}</button></div>${items.length ? gaugeGridMarkup(items) : emptyMarkup({ icon: 'drop', title: 'Sin tanques en el alcance', compact: true })}</article>`;
}

function branchStatusCard(merged) {
  const rows = merged.branches.map(b => {
    const pcts = (b.tanks || []).map(tankPercent).filter(Number.isFinite);
    const min = pcts.length ? Math.min(...pcts) : null;
    const level = min === null ? 'unknown' : min <= 30 ? 'critical' : min <= 60 ? 'medium' : 'optimal';
    return `<div class="branch-row"><div><div class="branch-name">${esc(b.name)}<span class="country-chip" title="${esc(countryName(b.countryCode))}">${esc(b.countryCode)}</span></div><div class="branch-meta">${b.closedCuts ?? 0} de ${b.expectedCuts ?? 0} cortes cerrados</div></div><div><div class="meter" role="img" aria-label="${esc(`Nivel mínimo ${min === null ? 'sin medición' : `${Math.round(min)} %`}`)}"><span class="hbar-fill" data-fill-w="${min === null ? 0 : Math.max(2, Math.round(min))}"></span></div><div class="branch-meta">Nivel mínimo ${min === null ? NO_DATA : `${Math.round(min)} %`}</div></div>${statusBadge(level)}</div>`;
  }).join('');
  return `<article class="card"><div class="section-head"><h2>Estado por sucursal</h2><button type="button" class="text-button" data-go="branches">Sucursales${icon('chevron-right', { size: 16 })}</button></div><div class="branch-list">${rows || emptyMarkup({ icon: 'store', title: 'No hay sucursales en el alcance', compact: true })}</div></article>`;
}

export function networkMarkup(merged, params) {
  const summary = summarizeNetwork(merged, { days: params.days });
  const updated = merged.lastSourceAt ? `Última actualización ${formatDateTime(merged.lastSourceAt)}` : 'Sin lecturas registradas';
  return `${alertStripMarkup(summary.alerts)}${kpiBoard(summary, merged, params, merged.permissions.sales)}<div class="grid cards-two">${tanksCard(merged)}${trendCard(merged, params.days)}</div><div class="grid cards-two space-top">${comparisonCard(merged)}${fuelCard(merged)}</div><div class="space-top">${branchStatusCard(merged)}</div><p class="branch-meta space-top">${esc(updated)} · Consolida únicamente cortes cerrados.</p>`;
}

export function branchMarkup(d, helpers) {
  const s = summarizeBranch(d);
  const tankAlerts = s.tanks.map(t => ({ t, pct: Number(t.percentage) })).filter(x => Number.isFinite(x.pct) && x.pct <= 60).sort((a, b) => a.pct - b.pct).map(({ t, pct }) => ({ severity: pct <= 30 ? 'crit' : 'warn', title: `${t.fuelName || 'Combustible'} al ${Math.round(pct)} %`, detail: pct <= 30 ? 'Nivel crítico (30 % o menos).' : 'Nivel medio (hasta 60 %).', page: 'inventory' }));
  const alerts = [...tankAlerts, ...s.alerts];
  const hero = kpiMarkup({ label: 'Inventario disponible', value: s.totalLiters === null ? 'Sin dato' : formatVolume(s.totalLiters, { withUnit: false }), unit: s.totalLiters === null ? '' : getPrefs().volumeUnit === 'gallons' ? 'gal' : 'L', note: `${s.tanks.length} tanques · ${s.note}`, icon: 'drop', size: 'hero' });
  const board = `<div class="kpi-board">${hero}${kpiMarkup({ label: 'Cortes cerrados', value: `${s.cutsClosed} / ${s.cutsTotal}`, note: s.cutsTotal === 2 ? 'Avance del día' : 'Calendario pendiente', icon: 'clock' })}${kpiMarkup({ label: 'Incidencias abiertas', value: String(s.openIncidents), tone: s.openIncidents ? 'warn' : 'ok', note: 'Requieren seguimiento', icon: 'flag' })}${kpiMarkup({ label: 'Mantenimiento', value: String(s.openMaintenance), note: 'Órdenes en seguimiento', icon: 'wrench' })}</div>`;
  const gauges = s.tanks.map(t => ({ name: t.fuelName || t.code, family: t.family, percent: t.percentage, caption: `${formatVolume(t.onHandLiters)} de ${formatVolume(t.capacityLiters)}`, detail: t.autonomyDays != null ? `Autonomía ${formatNumber(t.autonomyDays, { decimals: 1 })} días` : '' }));
  const cuts = d?.cuts || []; const incidents = d?.openIncidents || [];
  return `${alertStripMarkup(alerts)}${board}<article class="card"><div class="section-head"><div><h2>Nivel por tanque</h2><p class="branch-meta">Operación del ${esc(d?.operationalDate || helpers.today())}</p></div><button type="button" class="text-button" data-go="inventory">Inventario${icon('chevron-right', { size: 16 })}</button></div>${gauges.length ? gaugeGridMarkup(gauges) : emptyMarkup({ icon: 'drop', title: 'No hay tanques configurados', compact: true })}</article><div class="grid cards-two space-top"><article class="card"><div class="section-head"><h2>Turnos de hoy</h2><button type="button" class="text-button" data-go="cuts">Cortes${icon('chevron-right', { size: 16 })}</button></div>${helpers.table([{ label: 'Turno', render: helpers.cutLabel }, { label: 'Estado', render: r => statusBadge(r.status) }, { label: 'Bombas capturadas', render: r => `${r.registeredDispensers || 0} / ${r.expectedDispensers || 0}` }], cuts)}</article><article class="card"><div class="section-head"><h2>Incidencias abiertas</h2><button type="button" class="text-button" data-go="incidents">Incidencias${icon('chevron-right', { size: 16 })}</button></div>${helpers.table([{ label: 'Tipo', key: 'category' }, { label: 'Prioridad', render: r => statusBadge(r.severity, { kind: 'severity' }) }, { label: 'Estado', render: r => statusBadge(r.status) }], incidents)}</article></div>`;
}

export function createDashboardPage(ctx) {
  let view = null; let region = null; let host = null;
  const params = () => ({ days: ctx.state.days, countryCode: ctx.state.countryCode, branchIds: [...ctx.state.scope.branchIds], general: ctx.isGeneral(), branchId: ctx.state.branchId });
  const key = p => cacheKey('dashboard', p.general ? { d: p.days, c: p.countryCode, b: p.branchIds } : { branch: p.branchId });

  async function load(signal, p) {
    if (!p.general) {
      const d = ctx.unwrap(await ctx.request(`/metrics/branches/${p.branchId}/dashboard`, { signal }));
      return { mode: 'branch', d };
    }
    const slices = sliceRequests({ branches: ctx.state.branches, countryCode: p.countryCode, branchIds: p.branchIds, days: p.days });
    const settled = await settleAll(slices.map(slice => ctx.request(`/metrics/network/dashboard?${slice.query}`, { signal }).then(r => ({ slice, data: ctx.unwrap(r) }))));
    const ok = settled.filter(Boolean);
    if (!ok.length) throw new Error('No se pudo consultar el resumen de la red.');
    return { mode: 'network', merged: mergeNetwork(ok), partial: ok.length < slices.length };
  }

  const render = (data, p) => (data.mode === 'branch'
    ? branchMarkup(data.d, ctx.helpers)
    : `${data.partial ? `<div class="stale-banner" role="status">${icon('alert-triangle', { size: 18 })}<span>Algunas sucursales no respondieron; se muestran las demás.</span></div>` : ''}${networkMarkup(data.merged, p)}`);

  return {
    async mount(content) {
      host = content;
      const general = ctx.isGeneral();
      content.innerHTML = `<div class="module-head">${general ? `<div>${segmentedMarkup({ name: 'period', label: 'Periodo', options: PERIODS, value: String(ctx.state.days) })}</div>` : '<span></span>'}<span class="branch-meta" id="dash-updated"></span></div><div class="module-region" id="module-region" role="region" aria-label="Resumen" aria-busy="true"></div>`;
      region = content.querySelector('#module-region');
      bindSegmented(content, (name, value) => { const days = Number(value); if (days === ctx.state.days) return; ctx.pushHistory(); ctx.state.days = days; ctx.syncRoute(); view.refresh({ params: params() }); });
      region.addEventListener('click', event => {
        const go = event.target.closest('[data-go]');
        if (go) ctx.go(go.dataset.go, { branchId: go.dataset.branch || null });
      });
      view = createModuleView({
        region, cache: ctx.cache, keyOf: key, load, render,
        skeleton: () => skeletonMarkup('dashboard'),
        errorMarkup,
        clock: () => Date.now(), formatClock,
        afterRender: (el, data, p, info) => {
          animateRegion(el, { animate: info.first });
          const stamp = host.querySelector('#dash-updated');
          if (stamp) stamp.textContent = `Actualizado ${formatClock(Date.now())}`;
        },
      });
      await view.refresh({ params: params() });
    },
    update() { return view?.refresh({ params: params() }); },
    repaint() { view?.repaint(); },
    destroy() { view?.destroy(); view = null; },
  };
}

