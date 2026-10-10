// In-page confirmation and text prompts. They replace window.confirm/prompt/alert (blocked by the viewer and bad UX).
// Both return promises: askConfirm -> boolean, askPrompt -> string | null (null when cancelled).
import { icon } from './icons.js';
import { esc } from './components.js';

export function validatePromptValue(value, { minLength = 1, pattern = null, patternMessage = 'Formato no válido.' } = {}) {
  const text = String(value ?? '').trim();
  if (text.length < minLength) return { ok: false, message: minLength <= 1 ? 'Este dato es obligatorio.' : `Escribe al menos ${minLength} caracteres.` };
  if (pattern && !pattern.test(text)) return { ok: false, message: patternMessage };
  return { ok: true, value: text };
}

let openCount = 0;

function build(markup) {
  const dialog = document.createElement('dialog');
  dialog.className = 'dlg';
  dialog.innerHTML = markup;
  document.body.appendChild(dialog);
  return dialog;
}

function present(dialog, { onCancel }) {
  openCount += 1;
  if (typeof dialog.showModal === 'function') dialog.showModal(); else dialog.setAttribute('open', '');
  requestAnimationFrame(() => dialog.classList.add('is-open'));
  dialog.addEventListener('cancel', event => { event.preventDefault(); onCancel(); });
  dialog.addEventListener('click', event => { if (event.target === dialog) onCancel(); });
}

function dismiss(dialog) {
  dialog.classList.remove('is-open');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const done = () => { try { dialog.close(); } catch { /* already closed */ } dialog.remove(); openCount = Math.max(0, openCount - 1); };
  if (reduced) done(); else setTimeout(done, 160);
}

export function askConfirm({ title = 'Confirmar acción', text = '', confirmLabel = 'Confirmar', cancelLabel = 'Cancelar', tone = 'primary' } = {}) {
  return new Promise(resolve => {
    const kind = tone === 'danger' ? 'btn-danger' : 'btn-create';
    const dialog = build(`<form method="dialog" class="dlg-card" role="alertdialog" aria-labelledby="dlg-t" aria-describedby="dlg-d"><div class="dlg-head">${icon(tone === 'danger' ? 'alert-triangle' : 'info', { size: 22, cls: `dlg-icon dlg-icon--${tone === 'danger' ? 'crit' : 'info'}` })}<h2 id="dlg-t">${esc(title)}</h2></div><p id="dlg-d" class="dlg-text">${esc(text)}</p><div class="dlg-actions"><button type="button" class="btn btn-neutral" data-dlg="no">${icon('xmark', { size: 18 })}<span>${esc(cancelLabel)}</span></button><button type="button" class="btn ${kind}" data-dlg="yes">${icon('check', { size: 18 })}<span>${esc(confirmLabel)}</span></button></div></form>`);
    const finish = value => { dismiss(dialog); resolve(value); };
    present(dialog, { onCancel: () => finish(false) });
    dialog.querySelector('[data-dlg=no]').onclick = () => finish(false);
    dialog.querySelector('[data-dlg=yes]').onclick = () => finish(true);
    dialog.querySelector(tone === 'danger' ? '[data-dlg=no]' : '[data-dlg=yes]').focus();
  });
}

export function askPrompt({ title = 'Dato requerido', label = '', hint = '', placeholder = '', minLength = 1, multiline = true, confirmLabel = 'Aceptar', inputMode = '', pattern = null, patternMessage = '', tone = 'primary' } = {}) {
  return new Promise(resolve => {
    const control = multiline
      ? `<textarea id="dlg-f" class="field" rows="3" maxlength="500" placeholder="${esc(placeholder)}" aria-describedby="dlg-h dlg-e"></textarea>`
      : `<input id="dlg-f" class="field" type="text" maxlength="200" ${inputMode ? `inputmode="${esc(inputMode)}"` : ''} placeholder="${esc(placeholder)}" aria-describedby="dlg-h dlg-e">`;
    const dialog = build(`<form method="dialog" class="dlg-card" role="dialog" aria-labelledby="dlg-t" novalidate><div class="dlg-head">${icon('pencil', { size: 22, cls: 'dlg-icon dlg-icon--info' })}<h2 id="dlg-t">${esc(title)}</h2></div><label class="dlg-field" for="dlg-f"><span>${esc(label)}</span>${control}</label><p id="dlg-h" class="muted dlg-hint">${esc(hint)}</p><p id="dlg-e" class="error dlg-error" role="alert"></p><div class="dlg-actions"><button type="button" class="btn btn-neutral" data-dlg="no">${icon('xmark', { size: 18 })}<span>Cancelar</span></button><button type="submit" class="btn ${tone === 'danger' ? 'btn-danger' : 'btn-create'}" data-dlg="yes">${icon('check', { size: 18 })}<span>${esc(confirmLabel)}</span></button></div></form>`);
    const field = dialog.querySelector('#dlg-f');
    const error = dialog.querySelector('#dlg-e');
    const finish = value => { dismiss(dialog); resolve(value); };
    present(dialog, { onCancel: () => finish(null) });
    dialog.querySelector('[data-dlg=no]').onclick = () => finish(null);
    field.addEventListener('input', () => { error.textContent = ''; field.removeAttribute('aria-invalid'); });
    dialog.querySelector('form').addEventListener('submit', event => {
      event.preventDefault();
      const result = validatePromptValue(field.value, { minLength, pattern, patternMessage });
      if (!result.ok) { error.textContent = result.message; field.setAttribute('aria-invalid', 'true'); field.focus(); return; }
      finish(result.value);
    });
    field.addEventListener('keydown', event => { if (event.key === 'Enter' && !multiline) { event.preventDefault(); dialog.querySelector('form').requestSubmit(); } });
    field.focus();
  });
}

export const hasOpenDialog = () => openCount > 0;
