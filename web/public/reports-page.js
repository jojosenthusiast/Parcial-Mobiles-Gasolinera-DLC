// Reportes -> Analítica. Filter bar, KPI strip, charts, table and asynchronous exports for the 12 report types.
// All charts are SVG (charts.js); colours come from CSS tokens; every chart has a text alternative.
import { esc, kpiMarkup, skeletonMarkup, emptyMarkup } from './components.js';
import { icon } from './icons.js';
import { statusBadge } from './labels.js';
import { formatMoney, formatNumber, formatVolume, formatDateTime, formatDay, formatPrice, currencyForCountry, volumeValue, volumeUnitSymbol, NO_DATA } from './format.js';
import { lineChartMarkup, barChartMarkup, hbarsMarkup, chartCardMarkup, miniTableMarkup, legendMarkup, animateRegion } from './charts.js';
import { askConfirm } from './dialogs.js';
import { REPORT_TYPES, analyze, previousRange, quickRange, validateRange, exportView, columnLabel, columnKind, isValidDay, shortDay } from './reports-model.js';

const FORMATS = [['csv', 'CSV', 'Hoja de texto'], ['xlsx', 'Excel', 'Libro de Excel'], ['pdf', 'PDF', 'Documento']];
const MAX_AUX_PAGES = 20;
const GROUPS = [['', 'Detalle'], ['day', 'Agrupar por día'], ['fuel', 'Agrupar por combustible'], ['dispenser', 'Agrupar por bomba'], ['service_mode', 'Agrupar por modalidad']];
const MODES = [['', 'Todas las modalidades'], ['full_service', 'Servicio completo'], ['self_service', 'Autoservicio']];

export function createReportsPage(ctx) {
  const { state, request, unwrap, arr, filterValue, saveFilter, today, toast, showError } = ctx;
  const $ = s => document.querySelector(s);
  let generation = 0; let destroyed = false; let observer = null; let resizeTimer = 0;
  const timers = new Set();
  let lastView = null; let saved = []; let recent = [];
  const jobs = new Map();

  const base = () => `/branches/${state.branchId}/reports`;
  const branch = () => state.allBranches.find(b => b.id === state.branchId);
  const currency = () => currencyForCountry(branch()?.countryCode);
  const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ----------------------------- formatting ----------------------------- */
  function formatKpi(k) {
    const v = k.value;
    if (v === null || v === undefined || v === '') return NO_DATA;
    const sign = k.signed && Number(v) > 0 ? '+' : '';
    switch (k.format) {
      case 'money': return `${sign}${formatMoney(v, { currency: currency() })}`;
      case 'liters': return `${sign}${formatVolume(v)}`;
      case 'hours': return `${formatNumber(v, { decimals: 1 })} h`;
      case 'day': return formatDay(v);
      case 'text': return String(v);
      case 'price': return formatPrice(v, { currency: currency() });
      default: return `${sign}${formatNumber(v, { decimals: 0 })}`;
    }
  }
  function deltaNote(k) {
    if (!k.delta) return '';
    const { pct, dir } = k.delta;
    const good = k.invertDelta ? dir === 'down' : dir === 'up';
    const tone = dir === 'flat' ? 'flat' : good ? 'good' : 'bad';
    const text = dir === 'flat' ? 'Sin cambio' : `${pct > 0 ? '+' : '−'}${formatNumber(Math.abs(pct), { decimals: 1 })} %`;
    return `<span class="delta delta--${tone}">${icon(dir === 'up' ? 'trend-up' : dir === 'down' ? 'trend-down' : 'minus', { size: 16 })}${text}</span> <span>vs. periodo anterior</span>`;
  }
  const axisFormat = fmt => (fmt === 'price' ? v => formatNumber(v, { decimals: 2 }) : fmt === 'liters' ? v => formatNumber(volumeValue(v), { decimals: 0 }) : fmt === 'hours' ? v => formatNumber(v, { decimals: 0 }) : undefined);
  const unitNote = fmt => (fmt === 'money' || fmt === 'price' ? `Importes en ${currency()}` : fmt === 'liters' ? `Volumen en ${volumeUnitSymbol()}` : fmt === 'hours' ? 'Horas' : '');
  const valueText = (fmt, v) => (fmt === 'money' ? formatMoney(v, { currency: currency() }) : fmt === 'liters' ? formatVolume(v) : fmt === 'price' ? formatPrice(v, { currency: currency() }) : fmt === 'hours' ? `${formatNumber(v, { decimals: 1 })} h` : formatNumber(v, { decimals: 0 }));

  function cell(key, value, type) {
    if (value === null || value === undefined || value === '') return NO_DATA;
    switch (columnKind(key, type)) {
      case 'money': return esc(formatMoney(value, { currency: currency() }));
      case 'liters': return esc(formatVolume(value, { detail: true }));
      case 'price': return esc(formatPrice(value, { currency: currency() }));
      case 'datetime': return esc(formatDateTime(value, { timeZone: branch()?.timezone }));
      case 'date': return esc(formatDay(value));
      case 'status': return statusBadge(value, { kind: key === 'severity' ? 'severity' : '' });
      case 'bool': return value === true || value === 'true' ? statusBadge('warning', { label: 'Requerida' }) : '<span class="muted">No</span>';
      case 'id': return `<code title="${esc(value)}">${esc(String(value).slice(-8))}</code>`;
      case 'count': return esc(formatNumber(value, { decimals: Number.isInteger(Number(value)) ? 0 : 1 }));
      default: return esc(value);
    }
  }
  const numericKind = key => ['money', 'liters', 'price', 'count'].includes(columnKind(key));
  function tableMarkup(columns, rows, type) {
    if (!rows.length) return emptyMarkup({ icon: 'list', title: 'Sin registros', text: 'No hay datos para este periodo y estos filtros. Prueba con un rango más amplio.', compact: true });
    return `<div class="table-wrap" role="group" aria-label="Tabla desplazable horizontalmente" tabindex="0"><table class="data-table"><thead><tr>${columns.map(c => `<th scope="col"${numericKind(c) ? ' class="num"' : ''}>${esc(columnLabel(c))}</th>`).join('')}</tr></thead><tbody>${rowsMarkup(columns, rows, type)}</tbody></table></div>`;
  }
  const rowsMarkup = (columns, rows, type) => rows.map(r => `<tr>${columns.map(c => `<td${numericKind(c) ? ' class="num"' : ''}>${cell(c, r[c], type)}</td>`).join('')}</tr>`).join('');

  /* ----------------------------- charts ----------------------------- */
  function chartSvg(spec, width) {
    const fmt = spec.format;
    const yFormat = axisFormat(fmt);
    const aria = `${spec.title}. ${spec.subtitle || ''}`.trim();
    if (spec.kind === 'line') return lineChartMarkup({ width, categories: spec.categories, series: spec.series, step: spec.step, area: spec.area, zeroBase: spec.zeroBase !== false, yFormat, ariaLabel: `${aria}. ${summaryText(spec)}` });
    if (spec.kind === 'bar') return barChartMarkup({ width, categories: spec.categories, series: spec.series, stacked: spec.stacked, signed: spec.signed, yFormat, ariaLabel: `${aria}. ${summaryText(spec)}` });
    return '';
  }
  function summaryText(spec) {
    if (spec.kind === 'hbar') return `${spec.rows.length} elementos. Mayor: ${spec.rows[0]?.label ?? NO_DATA}.`;
    const values = spec.series.flatMap(s => s.values).filter(v => Number.isFinite(Number(v)));
    if (!values.length) return 'Sin datos.';
    const max = Math.max(...values); const min = Math.min(...values);
    return `${spec.categories.length} puntos. Máximo ${valueText(spec.format, max)}, mínimo ${valueText(spec.format, min)}.`;
  }
  function chartTable(spec) {
    if (spec.kind === 'hbar') return miniTableMarkup(['Elemento', valueHeader(spec.format)], spec.rows.map(r => [r.label, valueText(spec.format, r.value)]));
    return miniTableMarkup(['Categoría', ...spec.series.map(s => s.name)], spec.categories.map((c, i) => [c, ...spec.series.map(s => (s.values[i] === null || s.values[i] === undefined ? NO_DATA : valueText(spec.format, s.values[i])))]));
  }
  const valueHeader = fmt => (fmt === 'money' ? 'Importe' : fmt === 'liters' ? 'Volumen' : fmt === 'hours' ? 'Horas' : 'Cantidad');
  function chartHasData(spec) {
    if (spec.kind === 'hbar') return spec.rows.some(r => r.value > 0);
    return spec.categories.length > 0 && spec.series.some(s => s.values.some(v => Number.isFinite(Number(v)) && v !== null));
  }
  function chartMarkup(spec, width) {
    const subtitle = [spec.subtitle, unitNote(spec.format)].filter(Boolean).join(' · ');
    if (!chartHasData(spec)) return chartCardMarkup({ title: spec.title, subtitle, wide: spec.wide, empty: emptyMarkup({ icon: 'chart-bar', title: 'Sin datos para graficar', text: 'El periodo no tiene registros de este tipo.', compact: true }) });
    if (spec.kind === 'hbar') {
      const rows = spec.rows.map(r => ({ label: r.label, value: r.value, valueText: valueText(spec.format, r.value), family: r.family && r.family !== 'other' ? r.family : '', sub: r.liters ? formatVolume(r.liters) : '' }));
      return chartCardMarkup({ title: spec.title, subtitle, wide: spec.wide, svg: hbarsMarkup(rows), summary: '', table: chartTable(spec) }).replace('class="chart-host" data-chart-host', 'class="chart-host chart-host--bars"');
    }
    const legend = spec.series.length > 1 ? legendMarkup(spec.series) : '';
    return chartCardMarkup({ title: spec.title, subtitle, wide: spec.wide, svg: chartSvg(spec, width), legend, summary: summaryText(spec), table: chartTable(spec) }).replace('<div class="chart-host" data-chart-host>', `<div class="chart-host" data-chart-host data-chart-id="${esc(spec.id)}">`);
  }
  function chartWidth(wide) {
    const out = $('#report-analytics');
    const total = Math.max(300, (out?.clientWidth || 640));
    return Math.round(wide || total < 700 ? total - 40 : (total - 14) / 2 - 40);
  }
  function repaintCharts() {
    if (!lastView || destroyed) return;
    for (const host of document.querySelectorAll('[data-chart-id]')) {
      const spec = lastView.charts.find(c => c.id === host.dataset.chartId);
      const card = host.closest('.chart-card');
      if (!spec || !card) continue;
      const width = Math.max(260, Math.round(card.clientWidth - 40));
      if (Math.abs(width - Number(host.dataset.w || 0)) < 8) continue;
      host.dataset.w = String(width);
      host.innerHTML = chartSvg(spec, width);
    }
  }
  function observeResize() {
    observer?.disconnect();
    const target = $('#report-analytics');
    if (!target || typeof ResizeObserver === 'undefined') return;
    observer = new ResizeObserver(() => { clearTimeout(resizeTimer); resizeTimer = setTimeout(repaintCharts, 120); });
    observer.observe(target);
  }

  /* ----------------------------- data loading ----------------------------- */
  const newRun = async (type, from, to, extra = {}) => unwrap(await request(`${base()}/runs`, { method: 'POST', data: { type, from, to, ...extra, commandId: crypto.randomUUID() } }));
  const readRun = async (id, offset = 0) => unwrap(await request(`${base()}/runs/${id}${offset ? `?offset=${offset}` : ''}`));
  async function allRows(runId, first) {
    const rows = [...first.rows]; let next = first.nextOffset; let pages = 1;
    while (Number.isInteger(next) && pages < MAX_AUX_PAGES) { const d = await readRun(runId, next); rows.push(...d.rows); next = d.nextOffset; pages += 1; }
    return { rows, truncated: Number.isInteger(next) };
  }
  async function groupedRows(type, from, to, groupBy, serviceMode) {
    const run = await newRun(type, from, to, { groupBy, ...(serviceMode ? { serviceMode } : {}) });
    return (await allRows(run.id, await readRun(run.id))).rows;
  }

  /* ----------------------------- page frame ----------------------------- */
  function frameMarkup(types, f) {
    const field = (label, control, cls = '') => `<label class="rf-field ${cls}"><span>${esc(label)}</span>${control}</label>`;
    const select = (name, options, value) => `<select name="${name}">${options.map(([v, t]) => `<option value="${esc(v)}"${v === value ? ' selected' : ''}>${esc(t)}</option>`).join('')}</select>`;
    return `<p class="page-subtitle">Elige un reporte, ajusta el periodo y revisa sus gráficas, indicadores y detalle. Los datos salen de una instantánea fechada y respetan tus permisos.</p>
<section class="card report-filters" aria-label="Filtros del reporte"><form id="report-form" class="rf" novalidate>
  <div class="rf-row">${field('Reporte', select('type', types.map(t => [t.id, t.label]), f.type), 'rf-w-lg')}${field('Desde', `<input type="date" name="from" value="${esc(f.from)}">`, 'rf-w-sm')}${field('Hasta', `<input type="date" name="to" value="${esc(f.to)}">`, 'rf-w-sm')}
    <div class="rf-chips" role="group" aria-label="Rangos rápidos"><button type="button" class="chip" data-quick="7d">7 días</button><button type="button" class="chip" data-quick="30d">30 días</button><button type="button" class="chip" data-quick="month">Este mes</button></div></div>
  <div class="rf-row" id="rf-fuel" ${f.type === 'fuel_sales' ? '' : 'hidden'}>${field('Agrupación', select('groupBy', GROUPS, f.groupBy), 'rf-w-md')}${field('Modalidad', select('serviceMode', MODES, f.serviceMode), 'rf-w-md')}</div>
  <p class="error rf-error" id="rf-error" role="alert"></p>
  <div class="rf-row rf-actions"><button class="btn btn-create" type="submit">${icon('play', { size: 18 })}<span>Generar reporte</span></button><button class="btn btn-neutral" type="button" id="rf-save-toggle" aria-expanded="false" aria-controls="rf-save">${icon('bookmark', { size: 18 })}<span>Guardar filtro</span></button></div>
  <div class="rf-row rf-save" id="rf-save" hidden>${field('Nombre del filtro', '<input name="filterName" maxlength="80" placeholder="Ej. Ventas de la semana" autocomplete="off">', 'rf-w-lg')}<button class="btn btn-create" type="button" id="rf-save-do">${icon('check', { size: 18 })}<span>Guardar</span></button></div>
</form>
<div class="saved-wrap"><span class="saved-label">${icon('bookmark', { size: 16 })}Filtros guardados</span><div class="chips" id="saved-chips" role="list"></div></div></section>
<div id="report-output" class="report-output" aria-live="polite">${emptyMarkup({ icon: 'chart-bar', title: 'Genera un reporte', text: 'Elige tipo y periodo, o toca un filtro guardado, para ver gráficas, indicadores y detalle.', compact: true })}</div>
<article class="card report-box" id="export-card" hidden><div class="section-head compact"><h2>Exportaciones</h2></div><ul class="export-list" id="export-list"></ul></article>
<article class="card report-box"><div class="section-head compact"><h2>Reportes recientes</h2><button class="btn btn-neutral btn-sm" id="reload-reports" type="button">${icon('refresh', { size: 16 })}<span>Actualizar</span></button></div><div id="reports-list"></div></article>`;
  }

  function readForm() {
    const form = $('#report-form'); const v = new FormData(form);
    return { type: String(v.get('type')), from: String(v.get('from') || ''), to: String(v.get('to') || ''), groupBy: String(v.get('groupBy') || ''), serviceMode: String(v.get('serviceMode') || ''), name: String(v.get('filterName') || '').trim() };
  }
  const setError = text => { const el = $('#rf-error'); if (el) el.textContent = text || ''; };

  /* ----------------------------- generate ----------------------------- */
  async function generate() {
    const f = readForm();
    const check = validateRange(f.from, f.to);
    const span = (Date.parse(`${f.to}T00:00:00Z`) - Date.parse(`${f.from}T00:00:00Z`)) / 86400000;
    if (!check.ok || !validReportDate(f.from) || !validReportDate(f.to) || span > 365) { setError(check.message || 'Selecciona fechas válidas en un rango de hasta 366 días.'); return; }
    setError('');
    const { from, to, type } = f;
    const grouped = type === 'fuel_sales' ? f.groupBy : ''; const mode = type === 'fuel_sales' ? f.serviceMode : '';
    saveFilter('reports.from', from); saveFilter('reports.to', to); saveFilter('reports.type', type); saveFilter('reports.groupBy', grouped); saveFilter('reports.serviceMode', mode);
    const mine = ++generation;
    const out = $('#report-output');
    out.innerHTML = `${skeletonMarkup('dashboard')}`;
    try {
      const run = await newRun(type, from, to, { ...(grouped ? { groupBy: grouped } : {}), ...(mode ? { serviceMode: mode } : {}) });
      const data = await readRun(run.id);
      let analysisData; let previous = null; let truncated = false;
      if (type === 'fuel_sales') {
        const prev = previousRange(from, to);
        const [byDay, byFuel, prevDay] = await Promise.all([groupedRows(type, from, to, 'day', mode), groupedRows(type, from, to, 'fuel', mode), groupedRows(type, prev.from, prev.to, 'day', mode).catch(() => null)]);
        analysisData = { byDay, byFuel }; previous = prevDay ? { byDay: prevDay } : null;
      } else {
        const everything = await allRows(run.id, data); truncated = everything.truncated; analysisData = everything.rows;
        if (type === 'expenses') { const prev = previousRange(from, to); previous = await (async () => { try { const r = await newRun(type, prev.from, prev.to); return (await allRows(r.id, await readRun(r.id))).rows; } catch { return null; } })(); }
      }
      if (mine !== generation || destroyed) return;
      const view = analyze(type, analysisData, { previous });
      renderResult({ run, data, type, from, to, view, truncated, snapshot: false });
      reloadList();
    } catch (error) {
      if (mine !== generation || destroyed) return;
      out.innerHTML = `<div class="empty-state empty-state--error" role="alert">${icon('alert-triangle', { size: 36, cls: 'empty-icon' })}<b>No se pudo generar el reporte</b><p>${esc(error.message || 'Error de operación')}. Revisa el periodo e inténtalo otra vez.</p><button type="button" class="btn btn-neutral" id="rf-retry">${icon('refresh', { size: 18 })}<span>Reintentar</span></button></div>`;
      $('#rf-retry').onclick = generate;
    }
  }
  const validReportDate = isValidDay;

  function renderResult({ run, data, type, from, to, view, truncated, snapshot }) {
    lastView = view;
    const meta = REPORT_TYPES.find(t => t.id === type);
    const cols = data.columns;
    const kpis = view.kpis.length ? `<div class="kpi-board kpi-board--n${view.kpis.length}" role="list" aria-label="Indicadores del periodo">${view.kpis.map(k => kpiMarkup({ label: k.label, value: formatKpi(k), note: deltaNote(k), icon: k.icon, tone: k.tone || '', size: k.hero ? 'hero' : 'standard' })).join('')}</div>` : '';
    const charts = view.charts.length ? `<div class="chart-grid" id="report-analytics">${view.charts.map(spec => chartMarkup(spec, chartWidth(spec.wide))).join('')}</div>` : '<div id="report-analytics"></div>';
    const exportButtons = FORMATS.map(([fmt, label]) => `<button type="button" class="btn btn-neutral btn-sm" data-export="${fmt}" data-run="${esc(run.id)}" aria-label="Exportar ${esc(label)}">${icon('arrow-down-doc', { size: 16 })}<span>${esc(label)}</span></button>`).join('');
    $('#report-output').innerHTML = `<div class="report-head"><div><h2>${icon(meta?.icon || 'reports', { size: 22 })}${esc(meta?.label || type)}</h2><p class="muted">${esc(shortDay(from))} – ${esc(shortDay(to))} · ${esc(formatNumber(data.rowCount, { decimals: 0 }))} filas · Corte al ${esc(formatDateTime(data.asOf, { timeZone: branch()?.timezone }))} · ${esc(data.timezone || '')}${snapshot ? ' · Instantánea guardada' : ''}</p></div><div class="report-export" role="group" aria-label="Exportar reporte">${exportButtons}</div></div>${truncated ? `<p class="notice">Las gráficas usan las primeras ${formatNumber(MAX_AUX_PAGES, { decimals: 0 })} páginas de datos; acota el periodo para ver todo.</p>` : ''}${kpis}${charts}<article class="card report-box"><div class="section-head compact"><h2>Detalle</h2></div><div id="report-table">${tableMarkup(cols, data.rows, type)}</div><button class="text-button" id="more-rows" data-offset="${esc(data.nextOffset ?? '')}" ${data.nextOffset ? '' : 'hidden'}>${data.nextOffset ? 'Cargar más →' : ''}</button></article>`;
    const out = $('#report-output');
    out.querySelectorAll('[data-export]').forEach(b => { b.onclick = () => startExport(b.dataset.run, b.dataset.export, meta?.label || type); });
    $('#more-rows').onclick = () => loadMore(run.id, Number(data.nextOffset), cols, type);
    animateRegion(out);
    observeResize();
    requestAnimationFrame(repaintCharts);
  }

  async function loadMore(id, offset, cols, type) {
    if (!Number.isInteger(offset) || offset < 0) return;
    const button = $('#more-rows'); button.disabled = true;
    try {
      const d = await readRun(id, offset);
      $('#report-table tbody').insertAdjacentHTML('beforeend', rowsMarkup(cols, d.rows, type));
      button.dataset.offset = d.nextOffset ?? ''; button.hidden = !Number.isInteger(d.nextOffset);
      button.textContent = d.nextOffset ? 'Cargar más →' : '';
      button.onclick = () => loadMore(id, Number(d.nextOffset), cols, type);
    } catch (e) { showError(e); } finally { button.disabled = false; }
  }

  /* ----------------------------- exports ----------------------------- */
  function startExport(runId, format, label) {
    const key = `${runId}:${format}`;
    const existing = jobs.get(key);
    if (existing && existing.view?.busy) { toast('Esa exportación ya está en curso.'); return; }
    const job = { key, runId, format, label, id: null, view: exportView({ state: 'queued' }, 0), startedAt: Date.now(), cancelled: false, downloaded: false };
    jobs.set(key, job);
    paintJobs();
    (async () => {
      try {
        const created = unwrap(await request(`${base()}/runs/${runId}/exports`, { method: 'POST', data: { format, commandId: crypto.randomUUID() } }));
        job.id = created.id; job.startedAt = Date.now();
        poll(job);
      } catch (e) { job.view = exportView({ state: 'failed', error: e.message }); paintJobs(); showError(e); }
    })();
  }
  function poll(job) {
    const step = async () => {
      timers.delete(handle);
      if (destroyed || job.cancelled || !job.view.busy) return;
      try {
        const j = unwrap(await request(`${base()}/exports/${job.id}`));
        job.view = exportView(j, Date.now() - job.startedAt); job.filename = j.filename;
        paintJobs();
        if (j.state === 'succeeded') { if (!job.downloaded) await download(job); return; }
        if (['failed', 'cancelled'].includes(j.state)) { if (j.state === 'failed') toast(j.error || 'La exportación falló.'); return; }
        if (Date.now() - job.startedAt > 180_000) { job.view = { ...exportView({ state: 'failed', error: 'La exportación tardó demasiado.' }) }; paintJobs(); return; }
      } catch (e) { job.view = exportView({ state: 'failed', error: e.message }); paintJobs(); showError(e); return; }
      handle = setTimeout(step, 1500); timers.add(handle);
    };
    let handle = setTimeout(step, 900); timers.add(handle);
  }
  async function download(job) {
    try {
      const r = await fetch(`/api/v1${base()}/exports/${job.id}/download`);
      if (!r.ok) throw new Error('Descarga no disponible');
      const blob = await r.blob();
      const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = job.filename || `reporte.${job.format}`; a.click(); URL.revokeObjectURL(a.href);
      job.downloaded = true; toast('Archivo descargado.');
    } catch (e) { job.view = exportView({ state: 'failed', error: e.message }); paintJobs(); toast(e.message); }
  }
  async function cancelJob(job) {
    job.cancelled = true;
    try { if (job.id) { const result = unwrap(await request(`${base()}/exports/${job.id}/cancel`, { method: 'POST', data: {} })); toast(result.cancelled ? 'Exportación cancelada.' : 'La exportación ya terminó.'); } } catch (e) { showError(e); }
    job.view = exportView({ state: 'cancelled' }); paintJobs();
  }
  function paintJobs() {
    const card = $('#export-card'); const list = $('#export-list');
    if (!card || !list) return;
    const items = [...jobs.values()].reverse();
    card.hidden = !items.length;
    list.innerHTML = items.map(job => {
      const v = job.view;
      const tone = { ok: 'ok', crit: 'crit', warn: 'warn', info: 'info', muted: 'muted' }[v.tone] || 'info';
      const pillIcon = { ok: 'circle-check', crit: 'circle-x', warn: 'alert-circle', info: 'clock', muted: 'info' }[tone];
      return `<li class="export-job" data-job="${esc(job.key)}"><div class="export-main"><span class="export-name">${icon('arrow-down-doc', { size: 20 })}<b>${esc(job.format.toUpperCase())}</b><span class="muted">${esc(job.label)}</span></span><span class="pill pill--${tone}" role="status">${icon(pillIcon, { size: 14, cls: 'pill-icon' })}${esc(v.label)}</span></div><div class="export-bar" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${v.percent}" aria-label="Progreso de ${esc(job.format.toUpperCase())}"><span class="export-fill tone-${tone}${v.busy && v.percent === 0 ? ' is-indeterminate' : ''}" data-fill-w="${v.busy && v.percent === 0 ? 35 : v.percent}"></span></div><div class="export-foot"><span class="muted">${esc(v.detail)}</span><span class="export-actions">${v.canCancel ? `<button type="button" class="btn btn-danger btn-sm" data-job-cancel="${esc(job.key)}">${icon('xmark', { size: 16 })}<span>Cancelar</span></button>` : ''}${v.canRetry ? `<button type="button" class="btn btn-neutral btn-sm" data-job-retry="${esc(job.key)}">${icon('refresh', { size: 16 })}<span>Reintentar</span></button>` : ''}${v.canDownload ? `<button type="button" class="btn btn-create btn-sm" data-job-download="${esc(job.key)}">${icon('arrow-down-doc', { size: 16 })}<span>Descargar</span></button>` : ''}</span></div></li>`;
    }).join('');
    list.querySelectorAll('[data-job-cancel]').forEach(b => { b.onclick = () => cancelJob(jobs.get(b.dataset.jobCancel)); });
    list.querySelectorAll('[data-job-retry]').forEach(b => { b.onclick = async () => { const job = jobs.get(b.dataset.jobRetry); if (job.id && job.view.busy) await cancelJob(job); jobs.delete(job.key); startExport(job.runId, job.format, job.label); }; });
    list.querySelectorAll('[data-job-download]').forEach(b => { b.onclick = () => download(jobs.get(b.dataset.jobDownload)); });
    animateRegion(list, { animate: !reduced() });
  }

  /* ----------------------------- saved filters & recent runs ----------------------------- */
  async function loadSaved() {
    try { saved = arr(await request(`${base()}/saved-filters`)); } catch { saved = []; }
    window.savedReportFilters = saved;
    paintSaved();
  }
  function paintSaved() {
    const host = $('#saved-chips'); if (!host) return;
    host.innerHTML = saved.length ? saved.map(f => `<span class="chip chip--saved" role="listitem"><button type="button" class="chip-main" data-apply="${esc(f.id)}" title="Aplicar y generar">${esc(f.name)}</button><button type="button" class="chip-x" data-del="${esc(f.id)}" aria-label="Quitar filtro ${esc(f.name)}">${icon('xmark', { size: 14 })}</button></span>`).join('') : '<span class="muted">Aún no guardas filtros. Ajusta los controles y usa Guardar filtro.</span>';
    host.querySelectorAll('[data-apply]').forEach(b => { b.onclick = () => { applySaved(saved.find(f => f.id === b.dataset.apply)); generate(); }; });
    host.querySelectorAll('[data-del]').forEach(b => { b.onclick = () => removeSaved(saved.find(f => f.id === b.dataset.del)); });
  }
  function applySaved(f) {
    if (!f) return;
    const form = $('#report-form'); const v = f.filters || {};
    form.elements.type.value = REPORT_TYPES.some(t => t.id === f.type) ? f.type : form.elements.type.value;
    form.elements.from.value = v.from || ''; form.elements.to.value = v.to || '';
    form.elements.groupBy.value = v.groupBy || ''; form.elements.serviceMode.value = v.serviceMode || '';
    syncFuelFields();
  }
  async function removeSaved(f) {
    if (!f) return;
    if (!await askConfirm({ title: 'Quitar filtro guardado', text: `Se quitará el filtro "${f.name}" de tu lista. Los reportes ya generados no cambian.`, confirmLabel: 'Quitar filtro', tone: 'danger' })) return;
    try { await request(`${base()}/saved-filters/${f.id}`, { method: 'DELETE' }); toast('Filtro quitado.'); await loadSaved(); } catch (e) { showError(e); }
  }
  async function saveCurrent() {
    const f = readForm();
    if (f.name.length < 2) { setError('Escribe un nombre de al menos dos caracteres para el filtro.'); $('#report-form').elements.filterName.focus(); return; }
    const check = validateRange(f.from, f.to); if (!check.ok) { setError(check.message); return; }
    setError('');
    try {
      await request(`${base()}/saved-filters`, { method: 'POST', data: { name: f.name, type: f.type, from: f.from, to: f.to, ...(f.type === 'fuel_sales' && f.groupBy ? { groupBy: f.groupBy } : {}), ...(f.type === 'fuel_sales' && f.serviceMode ? { serviceMode: f.serviceMode } : {}) } });
      toast('Filtro guardado para tu usuario.'); $('#rf-save').hidden = true; $('#rf-save-toggle').setAttribute('aria-expanded', 'false'); $('#report-form').elements.filterName.value = ''; await loadSaved();
    } catch (e) { showError(e); }
  }
  async function reloadList() {
    const host = $('#reports-list'); if (!host) return;
    try {
      const d = arr(await request(`${base()}/runs`)); recent = d;
      if (!d.length) { host.innerHTML = emptyMarkup({ icon: 'file-text', title: 'Sin reportes recientes', text: 'Los reportes que generes aparecerán aquí.', compact: true }); return; }
      host.innerHTML = `<div class="table-wrap" role="group" aria-label="Reportes recientes" tabindex="0"><table class="data-table"><thead><tr><th scope="col">Tipo</th><th scope="col" class="num">Filas</th><th scope="col">Periodo</th><th scope="col">Generado</th><th scope="col"><span class="sr-only">Acción</span></th></tr></thead><tbody>${d.map(r => `<tr><td>${esc(REPORT_TYPES.find(t => t.id === r.type)?.label || r.type)}</td><td class="num">${esc(formatNumber(r.rowCount, { decimals: 0 }))}</td><td>${esc(r.filters?.from ? shortDay(r.filters.from) : NO_DATA)} – ${esc(r.filters?.to ? shortDay(r.filters.to) : NO_DATA)}</td><td>${esc(formatDateTime(r.createdAt, { timeZone: branch()?.timezone }))}</td><td><button type="button" class="btn btn-ghost btn-sm" data-open-run="${esc(r.id)}">${icon('eye', { size: 16 })}<span>Ver</span></button></td></tr>`).join('')}</tbody></table></div>`;
      host.querySelectorAll('[data-open-run]').forEach(b => { b.onclick = () => openRun(recent.find(r => r.id === b.dataset.openRun)); });
    } catch (e) { host.innerHTML = `<p class="error">${esc(e.message)}</p>`; }
  }
  async function openRun(row) {
    if (!row) return;
    const id = row.id;
    const mine = ++generation; $('#report-output').innerHTML = skeletonMarkup('list');
    $('#report-output').scrollIntoView({ behavior: reduced() ? 'auto' : 'smooth', block: 'start' });
    try {
      const data = await readRun(id);
      const type = row.type;
      const rows = await allRows(id, data);
      if (mine !== generation || destroyed) return;
      const f = row.filters || data.filters || {};
      const view = type === 'fuel_sales' ? { kpis: [], charts: [] } : analyze(type, rows.rows);
      renderResult({ run: { id }, data, type, from: f.from || '', to: f.to || '', view, truncated: rows.truncated, snapshot: true });
    } catch (e) { if (mine === generation) $('#report-output').innerHTML = `<p class="error">${esc(e.message)}</p>`; }
  }

  function syncFuelFields() {
    const form = $('#report-form'); const fuel = form.elements.type.value === 'fuel_sales';
    $('#rf-fuel').hidden = !fuel;
    if (!fuel) { form.elements.groupBy.value = ''; form.elements.serviceMode.value = ''; }
  }

  /* ----------------------------- mount ----------------------------- */
  async function mount(container) {
    destroyed = false;
    const types = REPORT_TYPES.filter(t => state.permissions.includes(t.permission));
    if (!types.length) { container.innerHTML = emptyMarkup({ icon: 'lock', title: 'Sin reportes disponibles', text: 'Tu perfil no tiene permisos de lectura para ningún tipo de reporte.' }); return; }
    const t = today();
    const fallback = quickRange('7d', t);
    let from = filterValue('reports.from'); let to = filterValue('reports.to');
    if (!validReportDate(from) || !validReportDate(to) || from > to || (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86400000 > 365) { from = fallback.from; to = fallback.to; }
    const type = types.some(x => x.id === filterValue('reports.type')) ? filterValue('reports.type') : types[0].id;
    const groupBy = GROUPS.some(([v]) => v === filterValue('reports.groupBy')) ? filterValue('reports.groupBy') : '';
    const serviceMode = MODES.some(([v]) => v === filterValue('reports.serviceMode')) ? filterValue('reports.serviceMode') : '';
    container.innerHTML = frameMarkup(types, { type, from, to, groupBy, serviceMode });
    const form = $('#report-form');
    form.elements.type.onchange = syncFuelFields;
    form.onsubmit = e => { e.preventDefault(); generate(); };
    form.querySelectorAll('[data-quick]').forEach(b => { b.onclick = () => { const r = quickRange(b.dataset.quick, today()); form.elements.from.value = r.from; form.elements.to.value = r.to; }; });
    $('#rf-save-toggle').onclick = () => { const box = $('#rf-save'); box.hidden = !box.hidden; $('#rf-save-toggle').setAttribute('aria-expanded', String(!box.hidden)); if (!box.hidden) form.elements.filterName.focus(); };
    $('#rf-save-do').onclick = saveCurrent;
    form.elements.filterName.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); saveCurrent(); } });
    $('#reload-reports').onclick = reloadList;
    state.view = { destroy };
    await Promise.all([loadSaved(), reloadList()]);
    generate();
  }
  function destroy() { destroyed = true; generation += 1; observer?.disconnect(); for (const h of timers) clearTimeout(h); timers.clear(); clearTimeout(resizeTimer); }

  return { mount, destroy };
}
