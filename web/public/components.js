// Shared UI building blocks: combobox, segmented control, skeletons, empty/error states, KPI cards.
// Markup helpers are pure strings (testable in node); createCombobox/bindSegmented wire the DOM.
import { icon } from './icons.js';

export const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
const fold = text => String(text ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

let uid = 0;
const nextId = prefix => `${prefix}-${++uid}`;

/* ------------------------------------------------------------------ */
/* Segmented control (fixed-width, equal segments: never reflows)      */
/* ------------------------------------------------------------------ */
export function segmentedMarkup({ name, label, options, value, size = '' }) {
  const buttons = options.map(o => `<button type="button" role="radio" aria-checked="${String(o.value) === String(value)}" data-value="${esc(o.value)}" class="seg-option${String(o.value) === String(value) ? ' is-selected' : ''}">${o.icon ? icon(o.icon, { size: 16 }) : ''}<span>${esc(o.label)}</span></button>`).join('');
  return `<div class="segmented${size ? ` segmented--${size}` : ''}" role="radiogroup" aria-label="${esc(label)}" data-segmented="${esc(name)}" data-count="${options.length}">${buttons}</div>`;
}

export function bindSegmented(root, onChange) {
  for (const group of root.querySelectorAll('[data-segmented]')) {
    if (group.dataset.bound) continue;
    group.dataset.bound = '1';
    const select = button => {
      for (const b of group.querySelectorAll('.seg-option')) { const on = b === button; b.classList.toggle('is-selected', on); b.setAttribute('aria-checked', String(on)); b.tabIndex = on ? 0 : -1; }
      onChange(group.dataset.segmented, button.dataset.value);
    };
    group.addEventListener('click', event => { const button = event.target.closest('.seg-option'); if (button && group.contains(button)) select(button); });
    group.addEventListener('keydown', event => {
      const items = [...group.querySelectorAll('.seg-option')];
      const index = items.indexOf(document.activeElement);
      if (index < 0) return;
      let next = -1;
      if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (index + 1) % items.length;
      else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (index - 1 + items.length) % items.length;
      if (next >= 0) { event.preventDefault(); items[next].focus(); select(items[next]); }
    });
    for (const b of group.querySelectorAll('.seg-option')) b.tabIndex = b.classList.contains('is-selected') ? 0 : -1;
  }
}

/* ------------------------------------------------------------------ */
/* Combobox: bordered button (label + value + chevron), searchable > 6  */
/* ------------------------------------------------------------------ */
export const SEARCH_THRESHOLD = 6;

export function filterOptions(options, query) {
  const q = fold(query).trim();
  if (!q) return options;
  return options.filter(o => fold(`${o.label} ${o.hint || ''} ${o.keywords || ''}`).includes(q));
}

export function summarizeSelection(options, values, { allLabel = 'Todos', plural = n => `${n} seleccionados` } = {}) {
  const chosen = options.filter(o => values.includes(o.value));
  if (!chosen.length) return allLabel;
  if (chosen.length === 1) return chosen[0].label;
  return plural(chosen.length);
}

export function createCombobox(host, config) {
  const cfg = { options: [], multi: false, allLabel: 'Todos', size: 'md', plural: n => `${n} seleccionados`, searchPlaceholder: 'Buscar…', ...config };
  const id = cfg.id || nextId('cb');
  let options = cfg.options;
  let values = cfg.multi ? [...(cfg.values || [])] : (cfg.value ? [cfg.value] : []);
  let open = false;
  let active = -1;
  let visible = [];
  let query = '';
  const searchable = () => cfg.searchable ?? options.length > SEARCH_THRESHOLD;

  host.classList.add('cb', `cb--${cfg.size}`);
  host.innerHTML = `<button type="button" class="cb-button" id="${id}-button" aria-haspopup="listbox" aria-expanded="false" aria-controls="${id}-pop"><span class="cb-text"><span class="cb-label">${esc(cfg.label)}</span><span class="cb-value"></span></span>${cfg.locked ? icon('lock', { size: 16, cls: 'cb-lock' }) : icon('chevron-down', { size: 16, cls: 'cb-chevron' })}</button><div class="cb-pop" id="${id}-pop" hidden></div>`;
  const button = host.querySelector('.cb-button');
  const pop = host.querySelector('.cb-pop');
  const valueEl = host.querySelector('.cb-value');

  const paintValue = () => {
    valueEl.textContent = summarizeSelection(options, values, { allLabel: cfg.allLabel, plural: cfg.plural });
    button.disabled = Boolean(cfg.disabled || cfg.locked);
    if (cfg.locked) button.title = cfg.lockedHint || 'Bloqueado para tu perfil';
  };

  const listMarkup = () => {
    visible = filterOptions(options, query);
    const rows = [];
    if (!cfg.multi && !query && cfg.allLabel) rows.push({ value: '', label: cfg.allLabel, all: true });
    rows.push(...visible);
    visible = rows;
    if (!rows.length) return `<li class="cb-empty" role="presentation">Sin resultados</li>`;
    let lastGroup = null;
    return rows.map((o, i) => {
      const selected = o.all ? !values.length : values.includes(o.value);
      const head = o.group && o.group !== lastGroup ? `<li class="cb-group" role="presentation">${esc(o.group)}</li>` : '';
      lastGroup = o.group || lastGroup;
      return `${head}<li role="option" id="${id}-opt-${i}" data-index="${i}" aria-selected="${selected}" class="cb-option${selected ? ' is-selected' : ''}${i === active ? ' is-active' : ''}${o.disabled ? ' is-disabled' : ''}"><span class="cb-check">${selected ? icon('check', { size: 16 }) : ''}</span><span class="cb-option-text"><span>${esc(o.label)}</span>${o.hint ? `<small>${esc(o.hint)}</small>` : ''}</span></li>`;
    }).join('');
  };

  const paintList = () => {
    const list = pop.querySelector('.cb-list');
    list.innerHTML = listMarkup();
    const input = pop.querySelector('.cb-search');
    const target = input || list;
    if (active >= 0) target.setAttribute('aria-activedescendant', `${id}-opt-${active}`); else target.removeAttribute('aria-activedescendant');
    list.querySelector('.is-active')?.scrollIntoView({ block: 'nearest' });
  };

  const commit = () => cfg.onChange?.(cfg.multi ? [...values] : (values[0] ?? ''));

  const choose = index => {
    const o = visible[index];
    if (!o || o.disabled) return;
    if (cfg.multi) {
      values = o.all ? [] : (values.includes(o.value) ? values.filter(v => v !== o.value) : [...values, o.value]);
      paintValue(); paintList(); commit();
    } else {
      values = o.all || !o.value ? [] : [o.value];
      paintValue(); close(true); commit();
    }
  };

  const onDocPointer = event => { if (!host.contains(event.target)) close(false); };

  function openPop() {
    if (open || button.disabled) return;
    open = true; query = ''; active = Math.max(0, visible.findIndex(o => values.includes(o.value)));
    pop.hidden = false;
    pop.classList.remove('align-end');
    pop.innerHTML = `${searchable() ? `<div class="cb-search-wrap">${icon('search', { size: 16 })}<input class="cb-search" type="search" role="combobox" aria-expanded="true" aria-controls="${id}-list" aria-autocomplete="list" aria-label="${esc(cfg.searchLabel || `Buscar ${cfg.label.toLowerCase()}`)}" placeholder="${esc(cfg.searchPlaceholder)}" autocomplete="off"></div>` : ''}<ul class="cb-list" id="${id}-list" role="listbox" ${searchable() ? '' : 'tabindex="0"'} aria-label="${esc(cfg.label)}" ${cfg.multi ? 'aria-multiselectable="true"' : ''}></ul>${cfg.multi ? `<div class="cb-foot"><button type="button" class="text-button" data-cb-clear>Limpiar</button><button type="button" class="secondary" data-cb-done>Listo</button></div>` : ''}`;
    visible = []; listMarkup();
    active = Math.max(0, visible.findIndex(o => (o.all ? !values.length : values.includes(o.value))));
    paintList();
    button.setAttribute('aria-expanded', 'true');
    const rect = host.getBoundingClientRect();
    if (rect.left + Math.max(rect.width, 288) > window.innerWidth - 12) pop.classList.add('align-end');
    document.addEventListener('pointerdown', onDocPointer, true);
    (pop.querySelector('.cb-search') || pop.querySelector('.cb-list')).focus({ preventScroll: true });
  }

  function close(refocus) {
    if (!open) return;
    open = false; pop.hidden = true; pop.innerHTML = '';
    button.setAttribute('aria-expanded', 'false');
    document.removeEventListener('pointerdown', onDocPointer, true);
    if (refocus) button.focus({ preventScroll: true });
  }

  const move = delta => {
    if (!visible.length) return;
    active = (active + delta + visible.length) % visible.length;
    paintList();
  };

  button.addEventListener('click', () => (open ? close(true) : openPop()));
  button.addEventListener('keydown', event => {
    if (['ArrowDown', 'ArrowUp'].includes(event.key)) { event.preventDefault(); openPop(); }
  });
  pop.addEventListener('keydown', event => {
    const typing = event.target.classList?.contains('cb-search');
    if (event.key === 'ArrowDown') { event.preventDefault(); move(1); }
    else if (event.key === 'ArrowUp') { event.preventDefault(); move(-1); }
    else if (event.key === 'Home' && !typing) { event.preventDefault(); active = 0; paintList(); }
    else if (event.key === 'End' && !typing) { event.preventDefault(); active = visible.length - 1; paintList(); }
    else if (event.key === 'Enter' || (event.key === ' ' && !typing)) { if (event.target.closest('[data-cb-done],[data-cb-clear]')) return; event.preventDefault(); if (active >= 0) choose(active); }
    else if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(true); }
    else if (event.key === 'Tab') close(false);
  });
  pop.addEventListener('input', event => { if (event.target.classList.contains('cb-search')) { query = event.target.value; active = 0; paintList(); } });
  pop.addEventListener('click', event => {
    const o = event.target.closest('.cb-option');
    if (o) { active = Number(o.dataset.index); choose(active); return; }
    if (event.target.closest('[data-cb-clear]')) { values = []; paintValue(); paintList(); commit(); }
    if (event.target.closest('[data-cb-done]')) close(true);
  });

  paintValue();
  return {
    el: host,
    setOptions(next) { options = next; paintValue(); if (open) paintList(); },
    setValue(next) { values = cfg.multi ? [...(next || [])] : (next ? [next] : []); paintValue(); if (open) paintList(); },
    getValue() { return cfg.multi ? [...values] : (values[0] ?? ''); },
    setLocked(locked, hint) { cfg.locked = locked; cfg.lockedHint = hint; paintValue(); },
    close: () => close(false),
    destroy() { close(false); host.innerHTML = ''; },
  };
}

/* ------------------------------------------------------------------ */
/* States: skeleton, empty, error                                      */
/* ------------------------------------------------------------------ */
const bar = (w = 'w-60', h = 'h-14') => `<span class="sk ${w} ${h}"></span>`;

export function skeletonMarkup(kind = 'cards') {
  const card = `<div class="sk-card"><span class="sk w-40 h-12"></span><span class="sk w-70 h-28"></span><span class="sk w-90 h-10"></span></div>`;
  if (kind === 'dashboard') {
    return `<div class="skeleton" aria-hidden="true"><div class="sk-strip">${bar('w-60', 'h-16')}</div><div class="sk-hero"><span class="sk w-30 h-12"></span><span class="sk w-50 h-44"></span><span class="sk w-70 h-12"></span></div><div class="grid stats">${card}${card}${card}</div><div class="grid split space-top"><div class="sk-card sk-tall"></div><div class="sk-card sk-tall"></div></div></div><span class="sr-only" role="status">Cargando…</span>`;
  }
  if (kind === 'list') {
    const row = `<div class="sk-row"><span class="sk w-30 h-14"></span><span class="sk w-20 h-14"></span><span class="sk w-10 h-14"></span></div>`;
    return `<div class="skeleton" aria-hidden="true"><div class="sk-card">${row}${row}${row}${row}${row}</div></div><span class="sr-only" role="status">Cargando…</span>`;
  }
  return `<div class="skeleton" aria-hidden="true"><div class="grid cards-two">${card}${card}${card}${card}</div></div><span class="sr-only" role="status">Cargando…</span>`;
}

export function emptyMarkup({ icon: name = 'info', title, text = '', action = null, compact = false } = {}) {
  const btn = action ? `<button type="button" class="${action.primary === false ? 'secondary' : 'primary'} btn-icon" ${action.attrs || ''}>${action.icon ? icon(action.icon, { size: 18 }) : ''}${esc(action.label)}</button>` : '';
  return `<div class="empty-state${compact ? ' empty-state--compact' : ''}" role="status">${icon(name, { size: compact ? 28 : 36, cls: 'empty-icon' })}<b>${esc(title)}</b>${text ? `<p>${esc(text)}</p>` : ''}${btn}</div>`;
}

// Same contract as panel-lib's errorCardMarkup (retry button id="retry", technical details folded), with an icon.
export function errorMarkup(error) {
  const meta = [];
  if (error?.code) meta.push(['Código', error.code]);
  if (error?.status) meta.push(['HTTP', error.status]);
  if (error?.correlationId) meta.push(['Ref.', error.correlationId]);
  const details = meta.length ? `<details class="chart-details error-details"><summary>Detalles técnicos</summary><p class="branch-meta">${meta.map(([k, v]) => `${esc(k)} ${esc(v)}`).join(' · ')}</p></details>` : '';
  return `<div class="empty-state empty-state--error" role="alert">${icon('alert-triangle', { size: 36, cls: 'empty-icon' })}<b>No se pudo cargar la información</b><p>${esc(error?.message || 'Error de operación')}. Revisa tu conexión e inténtalo otra vez.</p>${details}<button type="button" class="secondary btn-icon" id="retry">${icon('refresh', { size: 18 })}Reintentar</button></div>`;
}

/* ------------------------------------------------------------------ */
/* Buttons with semantic colour + icon (DESIGN.md section 4)           */
/* ------------------------------------------------------------------ */
export const ACTIONS = Object.freeze({
  create: { cls: 'btn-create', icon: 'plus', label: 'Crear' },
  add: { cls: 'btn-create', icon: 'plus', label: 'Agregar' },
  save: { cls: 'btn-create', icon: 'check', label: 'Guardar' },
  confirm: { cls: 'btn-create', icon: 'check', label: 'Confirmar' },
  edit: { cls: 'btn-neutral', icon: 'pencil', label: 'Editar' },
  open: { cls: 'btn-ghost', icon: 'chevron-right', label: 'Abrir' },
  view: { cls: 'btn-ghost', icon: 'eye', label: 'Ver' },
  approve: { cls: 'btn-approve', icon: 'check-seal', label: 'Aprobar' },
  reject: { cls: 'btn-danger', icon: 'xmark', label: 'Rechazar' },
  delete: { cls: 'btn-danger', icon: 'trash', label: 'Eliminar' },
  cancel: { cls: 'btn-neutral', icon: 'xmark', label: 'Cancelar' },
  filter: { cls: 'btn-neutral', icon: 'funnel', label: 'Filtrar' },
  search: { cls: 'btn-neutral', icon: 'search', label: 'Buscar' },
  export: { cls: 'btn-neutral', icon: 'arrow-down-doc', label: 'Exportar' },
  refresh: { cls: 'btn-neutral', icon: 'refresh', label: 'Actualizar' },
});

export function actionButton(kind, { label = '', attrs = '', type = 'button', iconOnly = false } = {}) {
  const a = ACTIONS[kind] || ACTIONS.open;
  const text = label || a.label;
  return `<button type="${type}" class="btn ${a.cls}${iconOnly ? ' btn-square' : ''}" ${attrs}${iconOnly ? ` aria-label="${esc(text)}" title="${esc(text)}"` : ''}>${icon(a.icon, { size: 18 })}${iconOnly ? '' : `<span>${esc(text)}</span>`}</button>`;
}

/* ------------------------------------------------------------------ */
/* KPI cards with different visual weight                              */
/* ------------------------------------------------------------------ */
export function kpiMarkup({ label, value, unit = '', note = '', icon: name = '', tone = '', size = 'standard', count = '' }) {
  const attrs = count ? ` data-count="${esc(count.value)}" data-count-kind="${esc(count.kind || 'number')}" data-count-decimals="${esc(count.decimals ?? 0)}" ${count.currency ? `data-count-currency="${esc(count.currency)}"` : ''}` : '';
  return `<article class="kpi kpi--${size}${tone ? ` kpi--${tone}` : ''}"><div class="kpi-head">${name ? icon(name, { size: size === 'hero' ? 22 : 18, cls: 'kpi-icon' }) : ''}<span class="kpi-label">${esc(label)}</span></div><div class="kpi-value"><span class="kpi-number"${attrs}>${esc(value)}</span>${unit ? `<span class="kpi-unit">${esc(unit)}</span>` : ''}</div>${note ? `<div class="kpi-note">${note}</div>` : ''}</article>`;
}
