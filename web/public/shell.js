// Application shell pieces: grouped navigation model, avatar menu and the settings drawer.
import { icon, NAV_ICON } from './icons.js';
import { bindSegmented, esc, segmentedMarkup } from './components.js';
import { openDrawer, closeDrawer } from './drawer.js';
import { MAX_DECIMALS, MIN_DECIMALS, getPrefs, setPrefs } from './prefs.js';
import { formatMoney, formatVolume } from './format.js';

export const NAV_GROUPS = Object.freeze([
  { label: 'Operación', items: [['dashboard', 'Resumen'], ['cuts', 'Cortes'], ['equipment', 'Bombas y tanques'], ['inventory', 'Inventario'], ['incidents', 'Incidencias']] },
  { label: 'Comercial', items: [['prices', 'Precios'], ['purchases', 'Compras'], ['store', 'Tienda'], ['cash', 'Caja']] },
  { label: 'Administración', items: [['branches', 'Sucursales'], ['staff', 'Personal'], ['users', 'Cuentas'], ['finance', 'Gastos']] },
  { label: 'Más', items: [['reports', 'Reportes'], ['maintenance', 'Mantenimiento'], ['assets', 'Activos']] },
]);

export const NAV_LABEL = Object.freeze(Object.fromEntries(NAV_GROUPS.flatMap(g => g.items)));
export const NAV_IDS = Object.freeze(Object.keys(NAV_LABEL));

// Groups visible items; empty groups disappear.
export function visibleGroups(visibleIds) {
  const allowed = new Set(visibleIds);
  return NAV_GROUPS.map(g => ({ label: g.label, items: g.items.filter(([id]) => allowed.has(id)) })).filter(g => g.items.length);
}

export function navItemMarkup(id, label, active) {
  return `<button class="nav-link ${active ? 'active' : ''}" data-page="${esc(id)}" aria-current="${active ? 'page' : 'false'}"><span class="nav-icon">${icon(NAV_ICON[id] || 'dashboard', { size: 20 })}</span><span class="nav-label">${esc(label)}</span></button>`;
}

/* ---- avatar menu (bottom of the sidebar) ---- */
export function bindAvatarMenu({ button, onSettings, onLogout }) {
  let pop = null;
  const close = () => { pop?.remove(); pop = null; button.setAttribute('aria-expanded', 'false'); document.removeEventListener('pointerdown', outside, true); document.removeEventListener('keydown', onKey, true); };
  const outside = event => { if (pop && !pop.contains(event.target) && !button.contains(event.target)) close(); };
  const onKey = event => { if (event.key === 'Escape') { close(); button.focus(); } };
  const open = () => {
    pop = document.createElement('div');
    pop.className = 'menu-pop'; pop.setAttribute('role', 'menu');
    pop.innerHTML = `<button type="button" class="menu-item" role="menuitem" data-menu="settings">${icon('sliders', { size: 20 })}<span>Configuración</span></button><div class="menu-sep"></div><button type="button" class="menu-item is-danger" role="menuitem" data-menu="logout">${icon('logout', { size: 20 })}<span>Cerrar sesión</span></button>`;
    button.parentElement.append(pop);
    button.setAttribute('aria-expanded', 'true');
    pop.addEventListener('click', event => {
      const item = event.target.closest('[data-menu]');
      if (!item) return;
      close();
      if (item.dataset.menu === 'settings') onSettings(); else onLogout();
    });
    document.addEventListener('pointerdown', outside, true);
    document.addEventListener('keydown', onKey, true);
    pop.querySelector('.menu-item').focus();
  };
  button.addEventListener('click', () => (pop ? close() : open()));
  return { close };
}

/* ---- settings drawer ---- */
const sample = prefs => `${formatMoney(1234.5, { decimals: prefs.decimals, currency: 'USD' })} · ${formatVolume(15000, { unit: prefs.volumeUnit })}`;

export function openSettings({ userName = '', onChange = () => {} } = {}) {
  const prefs = getPrefs();
  const html = `<div class="settings">
    <div class="setting-row"><b>Tema</b><small>Elige cómo se ve el panel. “Sistema” sigue la configuración de tu equipo.</small>${segmentedMarkup({ name: 'theme', label: 'Tema', value: prefs.theme, options: [{ value: 'light', label: 'Claro', icon: 'sun' }, { value: 'dark', label: 'Oscuro', icon: 'moon' }, { value: 'system', label: 'Sistema', icon: 'half-circle' }] })}</div>
    <div class="setting-row"><b>Unidad de volumen</b><small>El inventario y las ventas se muestran en esta unidad. Los precios conservan su unidad de origen.</small>${segmentedMarkup({ name: 'volumeUnit', label: 'Unidad de volumen', value: prefs.volumeUnit, options: [{ value: 'liters', label: 'Litros' }, { value: 'gallons', label: 'Galones' }] })}</div>
    <div class="setting-row"><b>Decimales</b><small>Para dinero y precios. Predeterminado: 2 (de ${MIN_DECIMALS} a ${MAX_DECIMALS}).</small>
      <div class="stepper"><button type="button" class="btn btn-neutral btn-square" data-step="-1" aria-label="Menos decimales">${icon('minus', { size: 18 })}</button><output id="decimals-out" aria-live="polite">${prefs.decimals}</output><button type="button" class="btn btn-neutral btn-square" data-step="1" aria-label="Más decimales">${icon('plus', { size: 18 })}</button></div></div>
    <div class="setting-row"><b>Densidad</b><small>Compacta muestra más filas en pantalla.</small>${segmentedMarkup({ name: 'density', label: 'Densidad', value: prefs.density, options: [{ value: 'comfortable', label: 'Cómoda' }, { value: 'compact', label: 'Compacta' }] })}</div>
    <p class="drawer-note" id="settings-sample">${icon('info', { size: 16 })}<span>Vista previa: ${esc(sample(prefs))}</span></p>
    <p class="branch-meta">La moneda de cada sucursal depende de su país. Las preferencias se guardan para ${esc(userName || 'tu usuario')} en este navegador.</p>
  </div>`;
  const { body } = openDrawer({ title: 'Configuración', content: html, footer: `<button type="button" class="btn btn-create" data-drawer-close>${icon('check', { size: 18 })}<span>Listo</span></button>` });
  const refresh = () => {
    const next = getPrefs();
    body.querySelector('#decimals-out').textContent = String(next.decimals);
    body.querySelector('#settings-sample span').textContent = `Vista previa: ${sample(next)}`;
    onChange(next);
  };
  bindSegmented(body, (name, value) => { setPrefs({ [name]: value }); refresh(); });
  body.addEventListener('click', event => {
    const step = event.target.closest('[data-step]');
    if (!step) return;
    setPrefs({ decimals: getPrefs().decimals + Number(step.dataset.step) });
    refresh();
  });
  return { close: closeDrawer };
}
