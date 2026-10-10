// Guided branch creation in five steps, shown in the right-side drawer. Every step is validated live and saved as a server checkpoint
// (POST /branches, then PATCH /branches/:id/onboarding). It can be closed and resumed at the last completed step.
import { icon } from './icons.js';
import { esc, bindSegmented, segmentedMarkup } from './components.js';
import { openDrawer, closeDrawer, drawerBody, drawerFooter, saveDraft, loadDraft, clearDraft } from './drawer.js';
import { animateRegion } from './charts.js';
import { countryChoiceMarkup, branchCountry } from './panel-lib.js';
import { CODE_HINT } from './codes.js';
import {
  DEFAULT_VALUES, FUEL_FAMILIES, STEPS, ZONES, categoryList, createDraftPayload, defaultFuels, identityPayload, infraPayloads, progressPercent, progressText,
  readinessItems, restoreFromBranch, staffPayload, suggestCodeFor, timezoneFor, validateStep, wizardCheckpoint,
} from './wizard-model.js';

const hhmm = ms => new Date(ms).toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit', hour12: false });
const field = (label, control, name, hint = '') => `<label class="wiz-field">${esc(label)}${control}${hint ? `<p class="code-hint" data-hint="${name}">${hint}</p>` : ''}<small class="field-error" data-err="${name}" hidden></small></label>`;

function stepperMarkup(index, completed) {
  return `<div class="wiz-head"><div class="wiz-progress-text"><b>${progressText(index)}</b><span>${esc(STEPS[index].title)}</span></div><div class="wiz-progress" role="progressbar" aria-valuemin="1" aria-valuemax="${STEPS.length}" aria-valuenow="${index + 1}" aria-label="${progressText(index)}"><span data-fill-w="${progressPercent(index)}"></span></div><ol class="wiz-steps">${STEPS.map((s, i) => `<li class="${i === index ? 'is-current' : i < completed ? 'is-done' : ''}"${i === index ? ' aria-current="step"' : ''}><span class="wiz-dot">${i < completed && i !== index ? icon('check', { size: 14 }) : i + 1}</span><span class="wiz-step-title">${esc(s.title)}</span></li>`).join('')}</ol></div>`;
}

function formMarkup(id, v, ctx) {
  if (id === 'basic') {
    return `${field('Nombre de la sucursal', `<input name="name" maxlength="120" autocomplete="off" value="${esc(v.name)}" placeholder="Ej. DLC Santa Ana">`, 'name')}
      ${field('País', `<select name="countryCode">${countryChoiceMarkup(v.countryCode, ctx.countries)}</select>`, 'countryCode')}
      ${field('Código', `<div class="code-row"><input name="code" maxlength="24" autocomplete="off" value="${esc(v.code)}"><button type="button" class="btn btn-neutral btn-sm" data-suggest>Sugerir</button></div>`, 'code', esc(CODE_HINT))}
      ${field('Zona', `<select name="zone">${ZONES.map(([k, l]) => `<option value="${k}" ${v.zone === k ? 'selected' : ''}>${l}</option>`).join('')}</select>`, 'zone')}
      ${field('Zona horaria', `<input name="timezone" maxlength="64" value="${esc(v.timezone)}">`, 'timezone', 'Se completa sola según el país. Cámbiala solo si la estación usa otra.')}`;
  }
  if (id === 'infra') {
    return `${field('Bombas (surtidores) de la estación', `<input name="dispenserCount" type="number" min="1" max="200" inputmode="numeric" value="${esc(v.dispenserCount)}">`, 'dispenserCount', 'La estación estándar tiene 6 bombas.')}
      <div class="wiz-field"><span>Tipos de combustible que se manejan</span>${segmentedMarkup({ name: 'fuelCount', label: 'Tipos de combustible', value: String(v.fuelCount), options: [{ value: '1', label: '1 tipo' }, { value: '2', label: '2 tipos' }, { value: '3', label: '3 tipos' }] })}<small class="field-error" data-err="fuelCount" hidden></small></div>
      <fieldset class="wiz-chips"><legend>Cuáles son</legend>${FUEL_FAMILIES.map(f => `<label class="chip"><input type="checkbox" name="fuel" value="${f.id}" ${v.fuels.includes(f.id) ? 'checked' : ''}><span class="fuel-dot fuel-dot--${f.id}"></span>${f.label}</label>`).join('')}<small class="field-error" data-err="fuels" hidden></small></fieldset>
      ${field('Tanques por combustible', `<input name="tanksPerFuel" type="number" min="1" max="6" inputmode="numeric" value="${esc(v.tanksPerFuel)}">`, 'tanksPerFuel', `<span data-tank-total></span>`)}`;
  }
  if (id === 'staff') {
    return `<div class="wiz-field"><span>¿Quién administra la estación?</span>${segmentedMarkup({ name: 'staffMode', label: 'Personal', value: v.staffMode, options: [{ value: 'now', label: 'Lo registro ahora' }, { value: 'later', label: 'Completar después' }] })}</div>
      <div data-staff-now ${v.staffMode === 'now' ? '' : 'hidden'}>${field('Nombre completo', `<input name="managerName" maxlength="120" value="${esc(v.managerName)}" autocomplete="off">`, 'managerName')}${field('Correo (opcional)', `<input name="managerEmail" type="email" maxlength="254" value="${esc(v.managerEmail)}" autocomplete="off">`, 'managerEmail')}<p class="drawer-note">${icon('info', { size: 16 })}<span>El alta formal (puesto, horario y acceso) se hace en Personal. Aquí queda anotado para recordártelo al activar.</span></p></div>
      <p class="drawer-note" data-staff-later ${v.staffMode === 'later' ? '' : 'hidden'}>${icon('clock', { size: 16 })}<span>Puedes seguir sin personal. Para activar la sucursal necesitarás al menos una persona activa.</span></p>`;
  }
  if (id === 'store') {
    return `<label class="wiz-switch"><input type="checkbox" name="hasStore" role="switch" ${v.hasStore ? 'checked' : ''}><span class="wiz-switch-ui" aria-hidden="true"></span><span><b>Tendrá tienda</b><small>Activa categorías de producto y caja registradora.</small></span></label>
      <div data-store-on ${v.hasStore ? '' : 'hidden'}>${field('Cajas registradoras', `<input name="registers" type="number" min="1" max="10" inputmode="numeric" value="${esc(v.registers)}">`, 'registers')}${field('Categorías iniciales', `<textarea name="categories" maxlength="400" placeholder="Bebidas, Snacks, Lubricantes">${esc(v.categories)}</textarea>`, 'categories', 'Sepáralas con comas. Los productos se cargan después desde Tienda.')}</div>
      <p class="drawer-note" data-store-off ${v.hasStore ? 'hidden' : ''}>${icon('info', { size: 16 })}<span>Sin tienda: la estación solo vende combustible.</span></p>`;
  }
  return '<div data-review><p class="branch-meta">Consultando al servidor lo que falta…</p></div>';
}

export function createBranchWizard(ctx) {
  const { request, unwrap, arr, state } = ctx;
  let s = null;

  const draftKeyOf = () => `branch-wizard:${s.branchId || 'new'}`;
  const persistLocal = () => saveDraft(draftKeyOf(), { ...Object.fromEntries(Object.entries(s.values).map(([k, v]) => [k, Array.isArray(v) ? v.join(',') : v])), __step: String(s.step), __f: s.values.fuels.join(',') }, {});

  function restoreLocal() {
    const d = loadDraft(draftKeyOf());
    if (!d) return false;
    const { __step, __f, ...rest } = d.values;
    for (const [k, v] of Object.entries(rest)) if (k in DEFAULT_VALUES && k !== 'fuels') s.values[k] = typeof DEFAULT_VALUES[k] === 'number' ? Number(v) : typeof DEFAULT_VALUES[k] === 'boolean' ? v === true || v === 'true' : v;
    if (__f) s.values.fuels = String(__f).split(',').filter(Boolean);
    if (Number.isInteger(Number(__step)) && Number(__step) > s.step) s.step = Math.min(Number(__step), s.completed);
    s.restored = d.savedAt;
    return true;
  }

  async function open({ branchId = null } = {}) {
    let existing = [];
    try { existing = arr(await request('/branches?limit=100')).map(b => b.code); } catch { existing = (state.allBranches || []).map(b => b.code); }
    s = { branchId, version: null, step: 0, completed: 0, values: { ...DEFAULT_VALUES, fuels: [...DEFAULT_VALUES.fuels] }, savedAt: null, restored: null, existing, currentCode: '', busy: false, error: '', note: '', readiness: null, confirming: false, done: false, countries: (state.branches || []).map(branchCountry) };
    if (branchId) {
      try {
        const b = unwrap(await request(`/branches/${branchId}`));
        if (b.status !== 'draft') { ctx.toast('Esta sucursal ya no es un borrador.'); return; }
        s.version = b.onboardingVersion; const r = restoreFromBranch(b);
        Object.assign(s, { values: r.values, step: r.step, completed: r.completed, savedAt: r.savedAt ? Date.parse(r.savedAt) : Date.parse(b.updatedAt) || null, currentCode: b.code });
      } catch (e) { ctx.showError(e); return; }
    } else {
      s.values.code = suggestCodeFor(existing, s.values.countryCode);
      s.values.timezone = timezoneFor(s.values.countryCode);
    }
    restoreLocal();
    openDrawer({ title: branchId ? 'Completar preparación' : 'Crear sucursal', wide: true, content: '<div class="wiz"></div>', onClose: () => { if (!s?.done) persistLocal(); ctx.onClosed?.(Boolean(s?.done)); s = null; } });
    paint();
  }

  const stepId = () => STEPS[s.step].id;
  const validation = () => validateStep(stepId(), s.values, { existingCodes: s.existing, currentCode: s.currentCode });

  function readForm(form) {
    const v = s.values; const data = new FormData(form);
    const text = n => (data.has(n) ? String(data.get(n)) : undefined);
    for (const name of ['name', 'code', 'zone', 'timezone', 'managerName', 'managerEmail', 'categories']) { const t = text(name); if (t !== undefined) v[name] = t; }
    for (const name of ['dispenserCount', 'tanksPerFuel', 'registers']) { const t = text(name); if (t !== undefined) v[name] = t === '' ? '' : Number(t); }
    if (data.has('countryCode')) v.countryCode = String(data.get('countryCode'));
    if (stepId() === 'infra') v.fuels = data.getAll('fuel').map(String);
    if (stepId() === 'store') v.hasStore = form.elements.hasStore.checked;
  }

  function showErrors(form, errors, touched) {
    for (const slot of form.querySelectorAll('[data-err]')) {
      const name = slot.dataset.err; const msg = touched.has(name) ? errors[name] : '';
      slot.textContent = msg || ''; slot.hidden = !msg;
      const input = form.elements[name]; if (input && !input.length) { if (msg) input.setAttribute('aria-invalid', 'true'); else input.removeAttribute('aria-invalid'); }
    }
    const code = form.querySelector('[data-hint="code"]');
    if (code && stepId() === 'basic') {
      const msg = errors.code; const touchedCode = touched.has('code');
      code.className = `code-hint${touchedCode ? (msg ? ' is-bad' : ' is-good') : ''}`;
      code.textContent = touchedCode ? (msg || 'Código disponible.') : CODE_HINT;
    }
    const total = form.querySelector('[data-tank-total]');
    if (total) total.textContent = `Se prepararán ${Number(s.values.tanksPerFuel || 0) * s.values.fuels.length} tanques en total (${s.values.fuels.length} ${s.values.fuels.length === 1 ? 'combustible' : 'combustibles'}).`;
  }

  function footerMarkup() {
    const last = s.step === STEPS.length - 1;
    if (s.confirming) return `<span class="grow branch-meta">¿Activar la sucursal ahora? Ya no se podrá editar como borrador.</span><button type="button" class="btn btn-neutral" data-act="cancel-activate">Cancelar</button><button type="button" class="btn btn-approve" data-act="activate">${icon('check-seal', { size: 18 })}<span>Sí, activar</span></button>`;
    return `${s.step > 0 ? `<button type="button" class="btn btn-neutral" data-act="back">${icon('chevron-left', { size: 18 })}<span>Atrás</span></button>` : ''}<span class="grow"></span><button type="button" class="btn btn-ghost" data-act="exit">Guardar y salir</button>${last ? `<button type="button" class="btn btn-approve" data-act="ask-activate" ${s.readiness?.canActivate ? '' : 'disabled'}>${icon('check-seal', { size: 18 })}<span>Activar sucursal</span></button>` : `<button type="button" class="btn btn-create" data-act="next" ${s.busy ? 'disabled' : ''}><span>${s.busy ? 'Guardando…' : 'Continuar'}</span>${icon('chevron-right', { size: 18 })}</button>`}`;
  }

  function savedChip() {
    if (s.restored) return `<span class="saved-chip">${icon('info', { size: 16 })}Borrador restaurado</span>`;
    return s.savedAt ? `<span class="saved-chip is-saved">${icon('circle-check', { size: 16 })}Guardado ${hhmm(s.savedAt)}</span>` : '<span class="saved-chip">Sin guardar aún</span>';
  }

  async function paint() {
    if (!s) return;
    const body = drawerBody(); const foot = drawerFooter();
    if (!body || !foot) return;
    if (s.done) { paintDone(body, foot); return; }
    const id = stepId();
    body.innerHTML = `<div class="wiz">${stepperMarkup(s.step, s.completed)}<div class="wiz-meta">${savedChip()}</div>${s.note ? `<p class="drawer-note">${icon('info', { size: 16 })}<span>${esc(s.note)}</span></p>` : ''}<div class="wiz-why">${icon('info', { size: 18 })}<p>${esc(STEPS[s.step].why)}</p></div>${s.error ? `<div class="alert-strip alert-strip--crit" role="alert"><div class="alert-strip-head">${icon('alert-triangle', { size: 20 })}<span class="grow">${esc(s.error)}</span></div></div>` : ''}<form class="wiz-form" data-validate="off" novalidate>${formMarkup(id, s.values, s)}</form></div>`;
    foot.innerHTML = footerMarkup(); foot.hidden = false;
    animateRegion(body);
    const form = body.querySelector('.wiz-form');
    if (id === 'review') { await paintReview(form); foot.innerHTML = footerMarkup(); return; }
    const touched = s.touched || (s.touched = new Set());
    const refresh = () => { readForm(form); const v = validation(); showErrors(form, v.errors, touched); const next = foot.querySelector('[data-act="next"]'); if (next) next.disabled = !v.ok || s.busy; persistLocal(); return v; };
    form.addEventListener('input', event => { if (event.target.name) touched.add(event.target.name); if (event.target.name === 'fuel') touched.add('fuels'); refresh(); });
    form.addEventListener('change', event => {
      const t = event.target;
      if (t.name === 'countryCode') { readForm(form); s.values.timezone = timezoneFor(t.value); if (!s.branchId) s.values.code = suggestCodeFor(s.existing, t.value); touched.add('countryCode'); paint(); return; }
      if (t.name === 'fuel') { s.values.fuelCount = String(Math.max(1, Math.min(3, form.querySelectorAll('input[name=fuel]:checked').length || 1))); readForm(form); }
      if (t.name === 'hasStore') { readForm(form); paint(); return; }
      refresh();
    });
    bindSegmented(form, (name, value) => {
      readForm(form);
      if (name === 'fuelCount') { s.values.fuelCount = value; s.values.fuels = defaultFuels(value); paint(); return; }
      if (name === 'staffMode') { s.values.staffMode = value; paint(); }
    });
    form.addEventListener('click', event => { if (event.target.closest('[data-suggest]')) { s.values.code = suggestCodeFor(s.existing, s.values.countryCode); touched.add('code'); paint(); } });
    refresh();
    if (!s.focusDone) { s.focusDone = true; (form.querySelector('input,select') || form).focus({ preventScroll: true }); }
  }

  async function paintReview(form) {
    const box = form.querySelector('[data-review]');
    try {
      s.readiness = unwrap(await request(`/branches/${s.branchId}/readiness`));
      s.version = s.readiness.onboardingVersion ?? s.version;
    } catch (e) { box.innerHTML = `<div class="alert-strip alert-strip--crit" role="alert"><div class="alert-strip-head">${icon('alert-triangle', { size: 20 })}<span class="grow">No se pudo consultar la revisión: ${esc(e.message)}</span></div></div><button type="button" class="btn btn-neutral" data-act="retry">${icon('refresh', { size: 18 })}<span>Reintentar</span></button>`; return; }
    const items = readinessItems(s.readiness.blockers);
    const wiz = s.values;
    const summary = `<ul class="wiz-summary"><li>${icon('store', { size: 18 })}<span><b>${esc(wiz.name)}</b> · ${esc(wiz.code)} · ${esc(wiz.countryCode)}</span></li><li>${icon('pump', { size: 18 })}<span>${esc(wiz.dispenserCount)} bombas · ${wiz.fuels.map(f => FUEL_FAMILIES.find(x => x.id === f)?.label).join(', ')}</span></li><li>${icon('users', { size: 18 })}<span>${wiz.staffMode === 'now' && wiz.managerName ? `Administra: ${esc(wiz.managerName)}` : 'Personal por completar'}</span></li><li>${icon('bag', { size: 18 })}<span>${wiz.hasStore ? `Con tienda · ${esc(wiz.registers)} ${Number(wiz.registers) === 1 ? 'caja' : 'cajas'}` : 'Sin tienda'}</span></li></ul>`;
    box.innerHTML = `${summary}${items.length ? `<div class="sub-title">${icon('alert-circle', { size: 16 })}Falta para activar (${items.length})</div><ul class="asset-list">${items.map(i => `<li class="asset-item">${icon('alert-circle', { size: 20 })}<div class="grow"><b>${esc(i.label)}</b>${i.detail && i.detail !== i.label ? `<small>${esc(i.detail)}</small>` : ''}</div><button type="button" class="btn btn-neutral btn-sm" data-fix="${esc(i.page)}">Resolver${icon('chevron-right', { size: 16 })}</button></li>`).join('')}</ul><p class="branch-meta">Puedes salir ahora: el borrador queda guardado y verás esta lista de nuevo.</p>` : `<div class="alert-strip alert-strip--ok"><div class="alert-strip-head">${icon('circle-check', { size: 22 })}<span class="grow">Todo listo. El servidor confirma que la sucursal se puede activar.</span></div></div>`}`;
  }

  function paintDone(body, foot) {
    body.innerHTML = `<div class="empty-state wiz-done">${icon('check-seal', { size: 36, cls: 'empty-icon' })}<b>${esc(s.values.name)} está activa</b><p>La sucursal ya aparece en el resumen y en los módulos de operación.</p></div>`;
    foot.innerHTML = `<span class="grow"></span><button type="button" class="btn btn-create" data-act="finish">${icon('check', { size: 18 })}<span>Ver sucursales</span></button>`;
  }

  async function patch(step, data) {
    const res = unwrap(await request(`/branches/${s.branchId}/onboarding`, { method: 'PATCH', data: { expectedVersion: s.version, step, data } }));
    s.version = res.onboardingVersion; s.savedAt = Date.now(); return res;
  }

  // Best effort: real infrastructure objects the API can create from the wizard answers (never blocks the checkpoint).
  async function applyInfrastructure() {
    const notes = [];
    if (state.permissions.includes('infrastructure.propose')) {
      try {
        const cfg = unwrap(await request(`/branches/${s.branchId}/configuration`));
        const version = cfg?.profile?.version ?? cfg?.profileVersion ?? cfg?.configurationVersion ?? cfg?.version ?? 1;
        await request(`/branches/${s.branchId}/operating-profile`, { method: 'PUT', data: { profile: 'operational', expectedDispenserCount: Number(s.values.dispenserCount), expectedVersion: Number(version) } });
        notes.push('bombas esperadas');
      } catch { notes.push('__profile'); }
      if (state.permissions.includes('fuel.read')) {
        try {
          const products = arr(await request('/fuel-products?status=active&limit=200'));
          let enabled = 0;
          for (const family of s.values.fuels) {
            const label = FUEL_FAMILIES.find(f => f.id === family).label.toLowerCase();
            const product = products.find(p => String(p.family || '').toLowerCase() === family) || products.find(p => String(p.displayName || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').includes(label.normalize('NFD').replace(/[̀-ͯ]/g, '')));
            if (!product) continue;
            try { await request(`/branches/${s.branchId}/fuel-offers/${product.id}`, { method: 'PUT', data: {} }); enabled += 1; } catch { /* reported below */ }
          }
          notes.push(`${enabled} de ${s.values.fuels.length} combustibles habilitados`);
        } catch { /* fuel catalog unavailable */ }
      }
    }
    const profileFailed = notes.includes('__profile');
    const text = notes.filter(n => n !== '__profile').join(' · ');
    return `${text ? `Se aplicó: ${text}. ` : ''}Tanques, mangueras y conexiones se terminan en “Bombas y tanques”.${profileFailed ? ' El número de bombas esperado quedó pendiente de confirmar allí.' : ''}`;
  }

  async function commit() {
    const id = stepId(); const v = s.values;
    if (id === 'basic') {
      if (!s.branchId) {
        const branch = unwrap(await request('/branches', { method: 'POST', data: createDraftPayload(v) }));
        s.branchId = branch.id; s.version = branch.onboardingVersion; s.currentCode = branch.code; s.savedAt = Date.now();
      } else { await patch('identity', identityPayload(v)); s.currentCode = String(v.code).trim().toUpperCase(); }
      await patch('review', wizardCheckpoint(v, 1));
    } else if (id === 'infra') {
      const p = infraPayloads(v);
      await patch('dispensers', p.dispensers); await patch('products', p.products); await patch('tanks', p.tanks);
      s.note = await applyInfrastructure();
      await patch('review', wizardCheckpoint(v, 2));
    } else if (id === 'staff') {
      await patch('staff', staffPayload(0));
      await patch('review', wizardCheckpoint(v, 3));
    } else if (id === 'store') {
      await patch('review', wizardCheckpoint(v, 4));
    }
    s.completed = Math.max(s.completed, s.step + 1);
  }

  async function reloadVersion() {
    try { const b = unwrap(await request(`/branches/${s.branchId}`)); s.version = b.onboardingVersion; } catch { /* keep going */ }
  }

  async function run(action) {
    if (!s || s.busy) return;
    s.error = '';
    if (action === 'next') {
      if (!validation().ok) return;
      s.busy = true; s.note = ''; drawerFooter().innerHTML = footerMarkup();
      try { await commit(); s.step += 1; s.touched = new Set(); s.focusDone = false; s.restored = null; clearDraft(draftKeyOf()); if (s.branchId) persistLocal(); }
      catch (e) { s.error = e.status === 409 ? `${e.message} Se recargó la versión; vuelve a pulsar Continuar.` : e.message; if (e.status === 409 && s.branchId) await reloadVersion(); }
      s.busy = false; paint(); return;
    }
    if (action === 'back') { s.step = Math.max(0, s.step - 1); s.touched = new Set(); s.focusDone = false; s.note = ''; paint(); return; }
    if (action === 'exit') {
      if (s.branchId && stepId() !== 'review' && validation().ok && s.step >= s.completed) { s.busy = true; try { await commit(); clearDraft(draftKeyOf()); ctx.toast('Borrador guardado.'); } catch { persistLocal(); } s.busy = false; }
      else if (s.branchId) ctx.toast('Borrador guardado.');
      else persistLocal();
      closeDrawer(); return;
    }
    if (action === 'retry') { paint(); return; }
    if (action === 'ask-activate') { s.confirming = true; drawerFooter().innerHTML = footerMarkup(); return; }
    if (action === 'cancel-activate') { s.confirming = false; drawerFooter().innerHTML = footerMarkup(); return; }
    if (action === 'activate') {
      s.busy = true;
      try { await request(`/branches/${s.branchId}/activate`, { method: 'POST', data: { expectedVersion: s.version } }); s.done = true; clearDraft(draftKeyOf()); clearDraft('branch-wizard:new'); ctx.toast('Sucursal activada.'); }
      catch (e) { s.error = e.message; s.confirming = false; await paintReviewAgain(); }
      s.busy = false; paint(); return;
    }
    if (action === 'finish') closeDrawer();
  }

  const paintReviewAgain = async () => { try { s.readiness = unwrap(await request(`/branches/${s.branchId}/readiness`)); } catch { /* shown on repaint */ } };

  document.addEventListener('click', event => {
    if (!s) return;
    const act = event.target.closest('[data-act]');
    const inDrawer = event.target.closest('.drawer');
    if (act && inDrawer) { event.preventDefault(); run(act.dataset.act); return; }
    const fix = event.target.closest('[data-fix]');
    if (fix && inDrawer) { const id = s.branchId; closeDrawer(); ctx.go(fix.dataset.fix, { branchId: id }); }
  });

  return { open };
}
