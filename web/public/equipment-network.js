// Bombas y tanques for several branches: one collapsible group per branch (branch name first), master -> detail.
import { icon } from './icons.js';
import { esc, emptyMarkup, errorMarkup, skeletonMarkup, segmentedMarkup, bindSegmented } from './components.js';
import { cacheKey, createModuleView, settleAll, debounce } from './module-view.js';
import { statusBadge, assetKindLabel, modeLabel } from './labels.js';
import { countryName, branchCountry } from './panel-lib.js';
import { formatVolume, formatClock } from './format.js';

const KINDS = [{ value: 'all', label: 'Todo' }, { value: 'dispenser', label: 'Bombas' }, { value: 'tank', label: 'Tanques' }];
const fold = text => String(text ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

export function groupEquipment(entries, { query = '', kind = 'all' } = {}) {
  const q = fold(query).trim();
  return entries.map(({ branch, dispensers, tanks }) => {
    const ds = kind === 'tank' ? [] : dispensers.filter(d => !q || fold(`${d.code} ${d.name} ${(d.products || []).map(p => p.name).join(' ')}`).includes(q));
    const ts = kind === 'dispenser' ? [] : tanks.filter(t => !q || fold(`${t.code} ${t.name} ${t.fuelName}`).includes(q));
    const issues = [...dispensers.map(d => d.physicalStatus), ...tanks.map(t => t.status)].filter(s => s && s !== 'active').length;
    return { branch, dispensers: ds, tanks: ts, totalDispensers: dispensers.length, totalTanks: tanks.length, issues, matches: ds.length + ts.length };
  }).filter(g => !q || g.matches > 0);
}

function dispenserRow(d) {
  const detail = `${d.activeNozzles ?? 0}/${d.nozzleCount ?? 0} mangueras activas${(d.products || []).length ? ` · ${(d.products || []).map(p => `${p.name} (${modeLabel(p.serviceMode).toLowerCase()})`).join(', ')}` : ''}`;
  return `<li class="asset-item">${icon('pump', { size: 20 })}<div class="grow"><b>${esc(d.code)} · ${esc(d.name || assetKindLabel('dispenser'))}</b><small>${esc(detail)}</small></div>${statusBadge(d.physicalStatus)}</li>`;
}
function tankRow(t) {
  return `<li class="asset-item">${icon('tank', { size: 20 })}<div class="grow"><b>${esc(t.code)} · ${esc(t.fuelName || t.name)}</b><small>Capacidad ${esc(formatVolume(t.nominalCapacityL))} · reserva ${esc(formatVolume(t.unusableReserveL))}</small></div>${statusBadge(t.status)}</li>`;
}

export function groupMarkup(g, open) {
  const b = g.branch; const id = esc(b.id);
  const summary = g.issues ? `<span class="pill pill--warn">${icon('alert-circle', { size: 14, cls: 'pill-icon' })}${g.issues} por revisar</span>` : `<span class="pill pill--ok">${icon('circle-check', { size: 14, cls: 'pill-icon' })}Todo operativo</span>`;
  return `<section class="group${open ? ' is-open' : ''}" data-group="${id}"><button type="button" class="group-head" aria-expanded="${open}" aria-controls="grp-${id}"><span class="group-badge">${icon('store', { size: 22 })}</span><span class="group-title"><b>${esc(b.name)}<span class="country-chip" title="${esc(countryName(branchCountry(b)))}">${esc(branchCountry(b))}</span></b><small>${g.totalDispensers} ${g.totalDispensers === 1 ? 'bomba' : 'bombas'} · ${g.totalTanks} ${g.totalTanks === 1 ? 'tanque' : 'tanques'}</small></span>${summary}<span class="group-chevron">${icon('chevron-down', { size: 20 })}</span></button><div class="group-body" id="grp-${id}"><div class="group-sections"><div><div class="sub-title">${icon('pump', { size: 16 })}Bombas</div>${g.dispensers.length ? `<ul class="asset-list">${g.dispensers.map(dispenserRow).join('')}</ul>` : emptyMarkup({ icon: 'pump', title: 'Sin bombas', compact: true })}</div><div><div class="sub-title">${icon('tank', { size: 16 })}Tanques</div>${g.tanks.length ? `<ul class="asset-list">${g.tanks.map(tankRow).join('')}</ul>` : emptyMarkup({ icon: 'tank', title: 'Sin tanques', compact: true })}</div></div><div><button type="button" class="btn btn-neutral btn-sm" data-config="${id}">${icon('wrench', { size: 16 })}<span>Configurar esta sucursal</span></button></div></div></section>`;
}

export function createEquipmentOverview(ctx) {
  let view = null; let region = null; let host = null;
  const open = new Set(); let query = ''; let kind = 'all';
  const branchesNow = () => ctx.scopeBranches();
  const params = () => ({ ids: branchesNow().map(b => b.id) });

  async function load(signal, p) {
    const list = branchesNow();
    const results = await settleAll(list.map(async b => {
      const [dispensers, tanks] = await Promise.all([ctx.request(`/branches/${b.id}/dispensers?limit=200`, { signal }), ctx.request(`/branches/${b.id}/tanks?limit=200`, { signal })]);
      return { branch: b, dispensers: ctx.arr(dispensers), tanks: ctx.arr(tanks) };
    }));
    const ok = results.filter(Boolean);
    if (!ok.length && list.length) throw new Error('No se pudo consultar el equipo de las sucursales.');
    return { entries: ok, failed: list.length - ok.length };
  }

  const render = data => {
    const groups = groupEquipment(data.entries, { query, kind });
    const total = data.entries.reduce((n, e) => n + e.dispensers.length + e.tanks.length, 0);
    if (!groups.length) return emptyMarkup({ icon: 'pump', title: query ? 'Sin coincidencias' : 'Sin equipo registrado', text: query ? 'Prueba con otro nombre, código o combustible.' : 'Las sucursales del alcance aún no tienen bombas ni tanques.' });
    const forced = Boolean(query) || groups.length === 1;
    return `${data.failed ? `<div class="stale-banner" role="status">${icon('alert-triangle', { size: 18 })}<span>${data.failed} ${data.failed === 1 ? 'sucursal no respondió' : 'sucursales no respondieron'}.</span></div>` : ''}<p class="branch-meta" role="status">${groups.length} ${groups.length === 1 ? 'sucursal' : 'sucursales'} · ${total} activos. Abre una sucursal para ver sus bombas y tanques.</p><div class="group-list">${groups.map(g => groupMarkup(g, forced || open.has(g.branch.id))).join('')}</div>`;
  };

  return {
    async mount(content) {
      host = content;
      content.innerHTML = `<div class="module-head"><div class="filters"><div class="search-box">${icon('search', { size: 18 })}<input id="equipment-search" type="search" maxlength="100" placeholder="Buscar bomba, tanque o combustible" aria-label="Buscar bomba, tanque o combustible" value="${esc(query)}"></div>${segmentedMarkup({ name: 'kind', label: 'Tipo de activo', options: KINDS, value: kind })}</div><div class="module-actions"><button type="button" class="btn btn-neutral btn-sm" id="equipment-expand">${icon('layers', { size: 16 })}<span>Expandir todo</span></button></div></div><div class="module-region" id="module-region" role="region" aria-label="Bombas y tanques por sucursal" aria-busy="true"></div>`;
      region = content.querySelector('#module-region');
      const repaint = () => view.repaint();
      content.querySelector('#equipment-search').addEventListener('input', debounce(event => { query = event.target.value; repaint(); }, 180));
      bindSegmented(content, (name, value) => { kind = value; repaint(); });
      content.querySelector('#equipment-expand').addEventListener('click', () => { for (const b of branchesNow()) open.add(b.id); repaint(); });
      region.addEventListener('click', event => {
        const cfg = event.target.closest('[data-config]');
        if (cfg) { ctx.go('equipment', { branchId: cfg.dataset.config, single: true }); return; }
        const head = event.target.closest('.group-head');
        if (!head) return;
        const group = head.closest('.group'); const id = group.dataset.group;
        const isOpen = group.classList.toggle('is-open');
        head.setAttribute('aria-expanded', String(isOpen));
        if (isOpen) open.add(id); else open.delete(id);
      });
      view = createModuleView({ region, cache: ctx.cache, keyOf: p => cacheKey('equipment', p), load, render, skeleton: () => skeletonMarkup('list'), errorMarkup, formatClock });
      await view.refresh({ params: params() });
    },
    update() { return view?.refresh({ params: params() }); },
    repaint() { view?.repaint(); },
    destroy() { view?.destroy(); view = null; },
  };
}
