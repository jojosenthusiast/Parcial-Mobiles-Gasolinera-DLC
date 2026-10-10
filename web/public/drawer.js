// Right-side drawer (440 px) for create/edit flows, plus per-form drafts stored in localStorage.
// Draft helpers are pure functions over a storage object so they can be tested in node.
import { icon } from './icons.js';

const safeStorage = () => { try { return globalThis.localStorage || null; } catch { return null; } };
export const DRAFT_TTL_MS = 14 * 24 * 60 * 60 * 1000;
export const draftKey = key => `dlc.draft.${key}`;

// Reads the values of a form into a plain object (passwords and files are never stored).
export function serializeForm(form) {
  const out = {};
  for (const el of form.elements) {
    if (!el.name || el.disabled) continue;
    if (['password', 'file', 'submit', 'button', 'hidden'].includes(el.type)) continue;
    if (el.type === 'checkbox') out[el.name] = el.checked;
    else if (el.type === 'radio') { if (el.checked) out[el.name] = el.value; }
    else out[el.name] = el.value;
  }
  return out;
}

export function applyDraftValues(form, values) {
  let applied = 0;
  for (const el of form.elements) {
    if (!el.name || !(el.name in values) || ['password', 'file', 'submit', 'button', 'hidden'].includes(el.type)) continue;
    const value = values[el.name];
    if (el.type === 'checkbox') el.checked = Boolean(value);
    else if (el.type === 'radio') el.checked = el.value === value;
    else el.value = value;
    applied += 1;
  }
  return applied;
}

const hasContent = values => Object.values(values || {}).some(v => (typeof v === 'string' ? v.trim() !== '' : v === true));

export function saveDraft(key, values, { storage = safeStorage(), now = Date.now() } = {}) {
  try {
    if (!hasContent(values)) { storage?.removeItem(draftKey(key)); return false; }
    storage?.setItem(draftKey(key), JSON.stringify({ values, savedAt: now }));
    return true;
  } catch { return false; }
}

export function loadDraft(key, { storage = safeStorage(), now = Date.now() } = {}) {
  try {
    const raw = JSON.parse(storage?.getItem(draftKey(key)) || 'null');
    if (!raw || typeof raw !== 'object' || typeof raw.values !== 'object' || !raw.values) return null;
    if (now - Number(raw.savedAt) > DRAFT_TTL_MS) { storage?.removeItem(draftKey(key)); return null; }
    return { values: raw.values, savedAt: Number(raw.savedAt) };
  } catch { return null; }
}

export function clearDraft(key, { storage = safeStorage() } = {}) {
  try { storage?.removeItem(draftKey(key)); } catch { /* storage can be blocked */ }
}

const clock = ms => new Date(ms).toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit', hour12: false });
const reduce = () => { try { return matchMedia('(prefers-reduced-motion: reduce)').matches; } catch { return false; } };

let root = null;
let current = null;

function ensureRoot() {
  if (root?.isConnected) return root;
  root = document.createElement('div');
  root.className = 'drawer-root';
  root.innerHTML = `<div class="drawer-scrim" data-drawer-close></div><aside class="drawer" role="dialog" aria-modal="true" aria-labelledby="drawer-title" tabindex="-1"><header class="drawer-head"><h2 id="drawer-title"></h2><button type="button" class="icon-button" data-drawer-close aria-label="Cerrar panel">${icon('xmark', { size: 20 })}</button></header><div class="drawer-body"></div><footer class="drawer-foot" hidden></footer></aside>`;
  document.body.append(root);
  root.addEventListener('click', event => { if (event.target.closest('[data-drawer-close]')) closeDrawer(); });
  root.addEventListener('keydown', event => {
    if (event.key === 'Escape') { event.stopPropagation(); closeDrawer(); return; }
    if (event.key !== 'Tab') return;
    const focusable = [...root.querySelectorAll('.drawer button:not([disabled]),.drawer input:not([disabled]):not([type=hidden]),.drawer select:not([disabled]),.drawer textarea:not([disabled]),.drawer [tabindex="0"]')].filter(el => el.offsetParent !== null);
    if (!focusable.length) return;
    const first = focusable[0]; const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  });
  return root;
}

export function isDrawerOpen() { return Boolean(current); }
export function drawerBody() { return root?.querySelector('.drawer-body') || null; }
export function drawerFooter() { return root?.querySelector('.drawer-foot') || null; }

// open({ title, content (Element | html string), footer (html string), wide, onClose, key })
export function openDrawer({ title, content, footer = '', wide = false, onClose = null }) {
  if (current) closeDrawer({ silent: true });
  const el = ensureRoot();
  const panel = el.querySelector('.drawer');
  el.querySelector('#drawer-title').textContent = title;
  const body = el.querySelector('.drawer-body');
  body.innerHTML = '';
  if (typeof content === 'string') body.innerHTML = content; else if (content) body.append(content);
  const foot = el.querySelector('.drawer-foot');
  foot.innerHTML = footer; foot.hidden = !footer;
  panel.style.maxWidth = '';
  panel.classList.toggle('drawer--wide', wide);
  const opener = document.activeElement;
  current = { onClose, opener };
  el.classList.add('is-open');
  const show = () => el.classList.add('is-shown');
  if (reduce()) show(); else requestAnimationFrame(() => requestAnimationFrame(show));
  setTimeout(() => (body.querySelector('input:not([type=hidden]),select,textarea,button') || panel).focus({ preventScroll: true }), 40);
  return { el, body, foot };
}

export function closeDrawer({ silent = false } = {}) {
  if (!current || !root) return;
  const { onClose, opener } = current;
  current = null;
  root.classList.remove('is-shown');
  const finish = () => { if (!current) { root.classList.remove('is-open'); root.querySelector('.drawer-body').innerHTML = ''; } };
  if (reduce()) finish(); else setTimeout(finish, 260);
  if (!silent) { try { onClose?.(); } catch { /* caller errors must not trap the drawer */ } opener?.focus?.({ preventScroll: true }); }
}

// Wires draft persistence to a form: restores a saved draft, saves on input (debounced) and returns controls.
export function bindDraft(form, key, { storage = safeStorage(), note = null, wait = 400 } = {}) {
  const paintNote = text => { if (note) { note.innerHTML = `${icon('info', { size: 16 })}<span>${text}</span>`; note.hidden = !text; } };
  const draft = loadDraft(key, { storage });
  if (draft && applyDraftValues(form, draft.values)) paintNote(`Borrador restaurado (${clock(draft.savedAt)})`);
  else paintNote('');
  let timer = null;
  const save = () => {
    const ok = saveDraft(key, serializeForm(form), { storage });
    paintNote(ok ? `Borrador guardado ${clock(Date.now())}` : '');
  };
  const onInput = () => { clearTimeout(timer); timer = setTimeout(save, wait); };
  form.addEventListener('input', onInput);
  form.addEventListener('change', onInput);
  return {
    restored: Boolean(draft),
    save,
    clear() { clearTimeout(timer); clearDraft(key, { storage }); paintNote(''); },
    dispose() { clearTimeout(timer); form.removeEventListener('input', onInput); form.removeEventListener('change', onInput); },
  };
}

// Moves an existing page form (inside its card) into the drawer, keeping every handler bound to it.
// A trigger button is added to `host`. The form returns to its place when the drawer closes.
export function drawerize({ form, host, label, title, key, buttonIcon = 'plus', afterOpen = null }) {
  if (!form || !host || form.dataset.drawerized) return null;
  const card = form.closest('article,section,.card') || form;
  if (!card.parentNode) return null;
  form.dataset.drawerized = '1';
  const anchor = document.createComment('drawer-anchor');
  card.parentNode.insertBefore(anchor, card);
  card.hidden = true;
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'btn btn-create';
  button.innerHTML = `${icon(buttonIcon, { size: 18 })}<span>${label}</span>`;
  host.append(button);
  button.addEventListener('click', () => {
    const note = document.createElement('div');
    note.className = 'drawer-note'; note.hidden = true;
    const wrap = document.createElement('div');
    wrap.append(note);
    card.hidden = false;
    wrap.append(card);
    openDrawer({ title, content: wrap, onClose: () => { draft.dispose(); card.hidden = true; anchor.parentNode?.insertBefore(card, anchor.nextSibling); } });
    const draft = bindDraft(form, key, { note });
    form.addEventListener('submit', () => { form.dataset.submittedAt = String(Date.now()); }, { once: true });
    afterOpen?.(form, draft);
    drawerize.active = { form, draft, card };
  });
  return button;
}

// Called by the app after any successful mutating request: finished submissions clear their draft and close the drawer.
export function notifyMutation() {
  const active = drawerize.active;
  if (!active || !isDrawerOpen()) return;
  const at = Number(active.form.dataset.submittedAt || 0);
  if (at && Date.now() - at < 8000) { active.draft.clear(); delete active.form.dataset.submittedAt; drawerize.active = null; closeDrawer(); }
}
