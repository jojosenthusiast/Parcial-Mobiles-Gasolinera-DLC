// Chart building blocks as pure markup (tank gauges, comparison bars, price markers) + one DOM helper for the entrance animation.
// Sizes are applied through the CSSOM (data-fill-h / data-fill-w) because the CSP blocks style attributes.
import { icon } from './icons.js';
import { esc } from './components.js';
import { toneForPercent } from './labels.js';
import { formatNumber, formatPrice, priceUnitName } from './format.js';

export const TONE_META = Object.freeze({
  ok: { label: 'Óptimo', icon: 'circle-check' },
  warn: { label: 'Medio', icon: 'alert-circle' },
  crit: { label: 'Crítico', icon: 'alert-triangle' },
  muted: { label: 'Sin medición', icon: 'info' },
});

export const fuelClass = family => (['super', 'regular', 'diesel'].includes(String(family || '').toLowerCase()) ? String(family).toLowerCase() : 'other');
export const clampPercent = value => { const n = Number(value); return Number.isFinite(n) ? Math.max(0, Math.min(100, n)) : 0; };

// One vertical gauge. Thresholds are drawn at 30 % and 60 %; level text and icon always accompany the colour.
export function gaugeMarkup({ name, family = 'other', percent, caption = '', detail = '' }) {
  const value = percent === null || percent === undefined || percent === '' ? NaN : Number(percent);
  const tone = toneForPercent(value);
  const meta = TONE_META[tone];
  const shown = Number.isFinite(value) ? `${formatNumber(Math.round(value), { decimals: 0 })} %` : '—';
  const label = `${name}: ${Number.isFinite(value) ? `${Math.round(value)} % de capacidad` : 'sin medición'}, nivel ${meta.label.toLowerCase()}`;
  return `<figure class="gauge" role="img" aria-label="${esc(label)}"><div class="gauge-tube"><span class="gauge-mark gauge-mark--60"></span><span class="gauge-mark gauge-mark--30"></span><span class="gauge-fill tone-${tone}" data-fill-h="${Number.isFinite(value) ? clampPercent(value) : 0}"></span></div><div class="gauge-pct">${shown}</div><figcaption class="gauge-name"><span class="fuel-dot fuel-dot--${fuelClass(family)}"></span>${esc(name)}</figcaption><span class="pill pill--${tone}">${icon(meta.icon, { size: 14, cls: 'pill-icon' })}${esc(meta.label)}</span>${caption ? `<span class="gauge-meta">${esc(caption)}</span>` : ''}${detail ? `<span class="gauge-meta">${esc(detail)}</span>` : ''}</figure>`;
}

export const gaugeLegendMarkup = () => `<div class="gauge-legend"><span><i class="dot dot--crit"></i>Crítico hasta 30 %</span><span><i class="dot dot--warn"></i>Medio hasta 60 %</span><span><i class="dot dot--ok"></i>Óptimo sobre 60 %</span></div>`;

export function gaugeGridMarkup(items) {
  if (!items.length) return '';
  return `<div class="gauge-grid">${items.map(gaugeMarkup).join('')}</div>${gaugeLegendMarkup()}`;
}

// Horizontal comparison bars. rows: [{ label, chip, value, valueText, sub, family }]; widths are relative to the largest value.
export function hbarsMarkup(rows) {
  const peak = Math.max(0, ...rows.map(r => Number(r.value) || 0));
  if (!rows.length || peak <= 0) return '';
  return `<ol class="hbars">${rows.map(r => {
    const width = Math.max(2, Math.round(((Number(r.value) || 0) / peak) * 100));
    return `<li><div class="hbar-head"><b>${esc(r.label)}${r.chip ? `<span class="country-chip">${esc(r.chip)}</span>` : ''}</b><span>${esc(r.valueText)}</span></div><div class="hbar-track" role="img" aria-label="${esc(`${r.label}: ${r.valueText}`)}"><span class="hbar-fill${r.family ? ` fuel-${fuelClass(r.family)}` : ''}" data-fill-w="${width}"></span></div>${r.sub ? `<div class="hbar-sub">${esc(r.sub)}</div>` : ''}</li>`;
  }).join('')}</ol>`;
}

// Price "marcador": big price in the fuel colour, variation arrow and 2 decimals.
export function variationOf(current, previous) {
  const a = Number(current); const b = Number(previous);
  if (!Number.isFinite(a) || !Number.isFinite(b) || b === 0) return null;
  const delta = a - b;
  return { delta, pct: (delta / b) * 100, dir: Math.abs(delta) < 1e-9 ? 'flat' : delta > 0 ? 'up' : 'down' };
}

export function markerMarkup({ name, family, mode = '', price, currency = 'USD', unit = 'liter', previous = null, since = '', decimals, action = '' }) {
  const opts = decimals === undefined ? { currency } : { currency, decimals };
  const text = formatPrice(price, opts);
  const [code, ...rest] = text.split(' ');
  const v = variationOf(price, previous);
  const variation = v
    ? `<span class="marker-var marker-var--${v.dir}">${icon(v.dir === 'up' ? 'trend-up' : v.dir === 'down' ? 'trend-down' : 'minus', { size: 16 })}${v.dir === 'flat' ? 'Sin cambio' : `${v.delta > 0 ? '+' : '−'}${formatNumber(Math.abs(v.delta), decimals === undefined ? {} : { decimals })} (${formatNumber(Math.abs(v.pct), { decimals: 1 })} %)`}</span>`
    : `<span class="marker-var marker-var--flat">${icon('minus', { size: 16 })}Sin variación previa</span>`;
  return `<article class="marker marker--${fuelClass(family)}"><div class="marker-name"><span class="fuel-dot fuel-dot--${fuelClass(family)}"></span>${esc(name)}${mode ? `<span class="marker-mode">· ${esc(mode)}</span>` : ''}</div><div class="marker-price" aria-label="${esc(`${name}: ${text} por ${priceUnitName(unit)}`)}"><span class="marker-unit">${esc(code)}</span> ${esc(rest.join(' '))}<span class="marker-unit"> / ${esc(priceUnitName(unit))}</span></div>${variation}<div class="marker-foot"><span>${since ? `Vigente desde ${esc(since)}` : ''}</span>${action}</div></article>`;
}

/* ---- Analytics charts: pure SVG markup. Geometry as attributes, colour through classes (CSP blocks inline styles). ---- */
export function niceTicks(min, max, count = 4) {
  let lo = Number.isFinite(min) ? min : 0;
  let hi = Number.isFinite(max) ? max : 1;
  if (hi === lo) { hi = lo + (Math.abs(lo) || 1); }
  const raw = (hi - lo) / count;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const norm = raw / mag;
  const step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 5 ? 5 : 10) * mag;
  lo = Math.floor(lo / step) * step;
  hi = Math.ceil(hi / step) * step;
  const ticks = [];
  for (let v = lo; v <= hi + step / 2; v += step) ticks.push(Math.round(v / step) * step);
  return { ticks, min: lo, max: hi, step };
}

const compactNumber = value => {
  const n = Number(value);
  if (!Number.isFinite(n)) return '—';
  const a = Math.abs(n);
  if (a >= 1e6) return `${formatNumber(n / 1e6, { decimals: 1, fixed: false })} M`;
  if (a >= 1e4) return `${formatNumber(n / 1e3, { decimals: 0 })} k`;
  return formatNumber(n, { decimals: a < 10 && n % 1 ? 1 : 0 });
};

function frame({ width, height, categories, values, yFormat, zeroBase }) {
  const nums = values.filter(v => Number.isFinite(v));
  let min = nums.length ? Math.min(...nums) : 0;
  let max = nums.length ? Math.max(...nums) : 1;
  if (zeroBase) { min = Math.min(0, min); max = Math.max(0, max); } else { const pad = (max - min) * 0.1 || 1; min -= pad; max += pad; }
  const scale = niceTicks(min, max, 4);
  const fmt = yFormat || compactNumber;
  const labels = scale.ticks.map(fmt);
  const left = Math.min(86, 14 + Math.max(...labels.map(t => t.length)) * 6.4);
  const box = { left, right: 12, top: 12, bottom: 30 };
  const plotW = Math.max(40, width - box.left - box.right);
  const plotH = height - box.top - box.bottom;
  const y = v => box.top + plotH - ((v - scale.min) / (scale.max - scale.min || 1)) * plotH;
  const every = Math.max(1, Math.ceil(categories.length / Math.max(1, Math.floor(plotW / 64))));
  const grid = scale.ticks.map((t, i) => `<line class="ch-grid${t === 0 ? ' ch-zero' : ''}" x1="${box.left}" x2="${width - box.right}" y1="${y(t).toFixed(1)}" y2="${y(t).toFixed(1)}"/><text class="ch-tick" x="${box.left - 8}" y="${(y(t) + 4).toFixed(1)}" text-anchor="end">${esc(labels[i])}</text>`).join('');
  return { box, plotW, plotH, y, every, grid, scale };
}

const seriesClass = (s, i) => s.cls || `ch-s${i % 6}`;

export function legendMarkup(series) {
  if (series.length < 2) return '';
  return `<ul class="ch-legend">${series.map((s, i) => `<li><i class="ch-sw ${seriesClass(s, i)}"></i>${esc(s.name)}</li>`).join('')}</ul>`;
}

// Multi-series line, area or step chart over shared categories. values[i] may be null (gap).
export function lineChartMarkup({ width = 640, height = 240, categories, series, yFormat, step = false, area = false, zeroBase = true, ariaLabel = '' }) {
  if (!categories.length || !series.length) return '';
  const all = series.flatMap(s => s.values.map(Number));
  const f = frame({ width, height, categories, values: all, yFormat, zeroBase });
  const n = categories.length;
  const x = i => f.box.left + (n === 1 ? f.plotW / 2 : (i / (n - 1)) * f.plotW);
  const ticks = categories.map((c, i) => (i % f.every === 0 || i === n - 1 && n > 1 && (n - 1) % f.every >= f.every / 2 ? `<text class="ch-tick" x="${x(i).toFixed(1)}" y="${height - 9}" text-anchor="${i === 0 ? 'start' : i === n - 1 ? 'end' : 'middle'}">${esc(c)}</text>` : '')).join('');
  const layers = series.map((s, si) => {
    const pts = s.values.map((v, i) => (v === null || v === undefined || !Number.isFinite(Number(v)) ? null : [x(i), f.y(Number(v)), Number(v), i]));
    let d = ''; let prev = null;
    for (const p of pts) {
      if (!p) { prev = null; continue; }
      if (!prev) d += `M${p[0].toFixed(1)} ${p[1].toFixed(1)}`;
      else d += step ? `H${p[0].toFixed(1)}V${p[1].toFixed(1)}` : `L${p[0].toFixed(1)} ${p[1].toFixed(1)}`;
      prev = p;
    }
    if (!d) return '';
    const cls = seriesClass(s, si);
    const base = f.y(Math.max(f.scale.min, Math.min(0, f.scale.max)));
    const live = pts.filter(Boolean);
    const areaPath = area && live.length > 1 ? `<path class="ch-area ${cls}" d="${d}${step ? `H${live.at(-1)[0].toFixed(1)}` : ''}V${base.toFixed(1)}H${live[0][0].toFixed(1)}Z"/>` : '';
    const dots = live.length <= 45 ? live.map(p => `<circle class="ch-dot ${cls}" cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="3"><title>${esc(`${s.name} · ${categories[p[3]]}: ${(yFormat || compactNumber)(p[2])}`)}</title></circle>`).join('') : '';
    return `${areaPath}<path class="ch-line ${cls}" d="${d}" pathLength="1"/>${dots}`;
  }).join('');
  return `<svg class="ch" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="${esc(ariaLabel)}" focusable="false">${f.grid}${ticks}${layers}</svg>`;
}

// Vertical bars, grouped or stacked, with negative values. `signed` colours by sign (variance charts).
export function barChartMarkup({ width = 640, height = 240, categories, series, stacked = false, signed = false, yFormat, ariaLabel = '' }) {
  if (!categories.length || !series.length) return '';
  const totals = categories.map((_, ci) => series.reduce((a, s) => a + (Number(s.values[ci]) || 0), 0));
  const flat = stacked ? [...totals, ...series.flatMap(s => s.values.map(v => Math.min(0, Number(v) || 0)))] : series.flatMap(s => s.values.map(v => Number(v) || 0));
  const f = frame({ width, height, categories, values: flat, yFormat, zeroBase: true });
  const n = categories.length;
  const slot = f.plotW / n;
  const groupW = Math.min(64, slot * 0.7);
  const barW = stacked ? groupW : Math.max(3, groupW / series.length);
  const zero = f.y(0);
  const fmt = yFormat || compactNumber;
  const bars = categories.map((c, ci) => {
    const cx = f.box.left + slot * ci + slot / 2;
    let acc = 0;
    return series.map((s, si) => {
      const v = Number(s.values[ci]) || 0;
      const x0 = stacked ? cx - groupW / 2 : cx - groupW / 2 + si * barW;
      const from = stacked ? acc : 0;
      const to = stacked ? acc + v : v;
      if (stacked) acc = to;
      const yA = f.y(Math.max(from, to));
      const yB = f.y(Math.min(from, to));
      const h = Math.max(v === 0 ? 2 : 1, yB - yA);
      const tone = signed ? (v === 0 ? 'ch-zero-bar' : v < 0 ? 'ch-neg' : 'ch-pos') : seriesClass(s, si);
      return `<rect class="ch-bar ${tone} ${v < 0 ? 'ch-bar--down' : 'ch-bar--up'}" x="${x0.toFixed(1)}" y="${(v === 0 ? zero - 1 : yA).toFixed(1)}" width="${Math.max(2, barW - (stacked ? 0 : 2)).toFixed(1)}" height="${h.toFixed(1)}" rx="2"><title>${esc(`${c} · ${s.name}: ${fmt(v)}`)}</title></rect>`;
    }).join('');
  }).join('');
  const ticks = categories.map((c, i) => (i % f.every === 0 ? `<text class="ch-tick" x="${(f.box.left + slot * i + slot / 2).toFixed(1)}" y="${height - 9}" text-anchor="middle">${esc(c)}</text>` : '')).join('');
  return `<svg class="ch" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="${esc(ariaLabel)}" focusable="false">${f.grid}${ticks}${bars}</svg>`;
}

// Chart card: title, svg, legend and a data table as the text alternative.
export function chartCardMarkup({ title, subtitle = '', svg, legend = '', summary = '', table = '', empty = null, wide = false }) {
  const body = svg
    ? `<div class="chart-host" data-chart-host>${svg}</div>${legend}${summary ? `<p class="chart-summary">${esc(summary)}</p>` : ''}${table ? `<details class="chart-details"><summary>Ver datos de la gráfica</summary>${table}</details>` : ''}`
    : (empty || '');
  return `<figure class="card chart-card${wide ? ' chart-card--wide' : ''}"><figcaption class="chart-title"><b>${esc(title)}</b>${subtitle ? `<small>${esc(subtitle)}</small>` : ''}</figcaption>${body}</figure>`;
}

export function miniTableMarkup(headers, rows) {
  if (!rows.length) return '';
  return `<div class="table-wrap"><table class="data-table"><thead><tr>${headers.map((h, i) => `<th scope="col"${i ? ' class="num"' : ''}>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.map(r => `<tr>${r.map((c, i) => `<td${i ? ' class="num"' : ''}>${esc(c)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}

/* ---- DOM helper: entrance animation (fill bars once, count numbers up once) ---- */
const reduced = () => { try { return matchMedia('(prefers-reduced-motion: reduce)').matches; } catch { return true; } };
const easeOut = t => 1 - (1 - t) ** 3;

function countUp(el, duration) {
  const finalText = el.textContent;
  const match = /^(\D*)([\d.,]+)(.*)$/s.exec(finalText);
  const target = Number(el.dataset.count);
  if (!match || !Number.isFinite(target)) return;
  const decimals = Number(el.dataset.countDecimals || 0);
  const [, prefix, , suffix] = match;
  const start = performance.now();
  const step = now => {
    const t = Math.min(1, (now - start) / duration);
    el.textContent = t >= 1 ? finalText : `${prefix}${formatNumber(target * easeOut(t), { decimals })}${suffix}`;
    if (t < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

export function animateRegion(region, { animate = true } = {}) {
  const still = !animate || reduced();
  const apply = () => {
    for (const el of region.querySelectorAll('[data-fill-h]')) el.style.height = `${clampPercent(el.dataset.fillH)}%`;
    for (const el of region.querySelectorAll('[data-fill-w]')) el.style.width = `${clampPercent(el.dataset.fillW)}%`;
  };
  if (still) apply(); else requestAnimationFrame(() => requestAnimationFrame(apply));
  if (!still) for (const el of region.querySelectorAll('[data-count]')) countUp(el, 280);
}
