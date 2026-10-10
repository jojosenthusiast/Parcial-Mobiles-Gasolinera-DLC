// ScopeBar: persistent "Red > Pais > Sucursal" selector. Pure helpers (testable) + a small DOM component.
import { icon } from './icons.js';
import { createCombobox } from './components.js';
import { branchCountry, countryName, deriveCountries } from './panel-lib.js';

// Branches that can be picked inside a country filter (all when no country is chosen).
export function branchesInCountry(branches, countryCode) {
  const list = branches || [];
  return countryCode ? list.filter(b => branchCountry(b) === countryCode) : list;
}

// Keeps only ids that still exist inside the chosen country; unknown ids are dropped silently.
export function reconcileSelection(branchIds, branches, countryCode) {
  const allowed = new Set(branchesInCountry(branches, countryCode).map(b => b.id));
  return [...new Set((branchIds || []).filter(id => allowed.has(id)))];
}

// Branches that a multi-branch module should load: the selection, or every branch of the country, or the whole network.
export function branchesInScope(branches, countryCode, branchIds) {
  const inCountry = branchesInCountry(branches, countryCode);
  const picked = reconcileSelection(branchIds, branches, countryCode);
  return picked.length ? inCountry.filter(b => picked.includes(b.id)) : inCountry;
}

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

// "Viendo: Toda la red · 2 sucursales"
export function scopeSummary({ branches, countryCode = null, branchIds = [], lockedBranch = null } = {}) {
  if (lockedBranch) return `Viendo: ${lockedBranch.name}`;
  const scoped = branchesInScope(branches, countryCode, branchIds);
  const place = countryCode ? countryName(countryCode) : 'Toda la red';
  const picked = reconcileSelection(branchIds, branches, countryCode);
  if (picked.length === 1) return `Viendo: ${scoped[0]?.name || place}`;
  return `Viendo: ${place} · ${plural(scoped.length, 'sucursal', 'sucursales')}`;
}

export function countryOptions(branches) {
  return deriveCountries(branches || []).map(c => ({ value: c.countryCode, label: countryName(c.countryCode), hint: plural(c.branchCount, 'sucursal', 'sucursales') }));
}

export function branchOptions(branches, countryCode) {
  return branchesInCountry(branches, countryCode).map(b => ({ value: b.id, label: b.name, hint: `${countryName(branchCountry(b))}${b.code ? ` · ${b.code}` : ''}`, group: countryCode ? undefined : countryName(branchCountry(b)), keywords: `${b.code || ''} ${branchCountry(b)}` }));
}

export function createScopeBar(host, { getModel, onChange }) {
  host.innerHTML = `<span class="scope-crumb">${icon('globe', { size: 18 })}Red</span><span class="scope-sep" aria-hidden="true">${icon('chevron-right', { size: 16 })}</span><div class="cb-country"></div><span class="scope-sep" aria-hidden="true">${icon('chevron-right', { size: 16 })}</span><div class="cb-branches"></div><span class="scope-view" role="status" aria-live="polite"></span>`;
  const view = host.querySelector('.scope-view');
  let countryBox = null; let branchBox = null;

  const build = () => {
    const m = getModel();
    countryBox = createCombobox(host.querySelector('.cb-country'), {
      id: 'scope-country', label: 'País', allLabel: 'Todos los países', size: 'md', options: countryOptions(m.branches), value: m.countryCode || '',
      locked: m.locked, lockedHint: 'Tu perfil solo ve su sucursal',
      onChange: value => onChange({ countryCode: value || null, branchIds: [] }),
    });
    branchBox = createCombobox(host.querySelector('.cb-branches'), {
      id: 'scope-branches', label: 'Sucursal', multi: true, allLabel: 'Todas', size: 'md', options: branchOptions(m.branches, m.countryCode), values: m.branchIds,
      plural: n => `${n} sucursales`, searchLabel: 'Buscar sucursal', searchPlaceholder: 'Buscar sucursal…',
      locked: m.locked, lockedHint: 'Sucursal asignada a tu perfil',
      onChange: ids => onChange({ branchIds: ids }),
    });
  };

  const update = () => {
    const m = getModel();
    if (!countryBox) build();
    if (m.locked) {
      host.querySelector('.cb-country').hidden = true;
      host.querySelector('.cb-country').previousElementSibling.hidden = true;
      host.querySelector('.cb-country').nextElementSibling.hidden = true;
    }
    countryBox.setOptions(countryOptions(m.branches));
    countryBox.setValue(m.countryCode || '');
    branchBox.setOptions(m.locked && m.lockedBranch ? [{ value: m.lockedBranch.id, label: m.lockedBranch.name }] : branchOptions(m.branches, m.countryCode));
    branchBox.setValue(m.locked && m.lockedBranch ? [m.lockedBranch.id] : m.branchIds);
    branchBox.setLocked(Boolean(m.locked), 'Sucursal asignada a tu perfil');
    countryBox.setLocked(Boolean(m.locked), 'Tu perfil solo ve su sucursal');
    view.innerHTML = `${icon(m.locked ? 'lock' : 'eye', { size: 16 })}<span>${scopeSummary(m).replace(/&/g, '&amp;').replace(/</g, '&lt;')}</span>`;
  };
  update();
  return { update };
}
