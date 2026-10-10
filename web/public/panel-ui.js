import { fieldMessage } from '/panel-lib.js';

// DOM layer: real-time validation for every data-entry form and CSP-safe sizing (style attributes are blocked by the panel CSP,
// so charts declare data-w / data-h and the dimensions are applied through the CSSOM).

const IGNORED_TYPES = new Set(['hidden', 'submit', 'button', 'reset', 'image', 'file']);
let counter = 0;

const isField = element => element.matches?.('input,select,textarea') && !IGNORED_TYPES.has(element.type);
const fieldsOf = form => [...form.elements].filter(isField);
const isActive = element => element.willValidate !== false && !element.closest('[hidden]');
const submitButtons = form => [...form.querySelectorAll('button')].filter(button => (button.getAttribute('type') || 'submit') === 'submit');

function labelOf(element) {
  const aria = element.getAttribute('aria-label');
  if (aria) return aria;
  const label = element.closest('label');
  if (label) {
    for (const node of label.childNodes) {
      if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) return node.textContent.trim();
    }
  }
  return element.name || 'campo';
}

function messageSlot(element) {
  if (element._errorSlot) return element._errorSlot;
  const slot = document.createElement('small');
  slot.className = 'field-error';
  slot.id = `${element.id || element.name || 'field'}-error-${++counter}`;
  slot.hidden = true;
  element.insertAdjacentElement('afterend', slot);
  element._errorSlot = slot;
  const described = (element.getAttribute('aria-describedby') || '').split(/\s+/).filter(Boolean);
  described.push(slot.id);
  element.setAttribute('aria-describedby', described.join(' '));
  return slot;
}

function paint(element, form) {
  const message = isActive(element) ? fieldMessage(element, form) : '';
  const show = Boolean(message) && element.dataset.touched === '1';
  if (show || element._errorSlot) {
    const slot = messageSlot(element);
    slot.textContent = show ? message : '';
    slot.hidden = !show;
  }
  if (show) element.setAttribute('aria-invalid', 'true');
  else element.removeAttribute('aria-invalid');
  return message;
}

function syncDependentLimits(form) {
  for (const select of form.querySelectorAll('select[data-max-for]')) {
    const target = form.elements[select.dataset.maxFor];
    const option = select.selectedOptions?.[0];
    if (target && option?.dataset.max !== undefined) target.max = option.dataset.max;
  }
}

function hintOf(form) {
  if (!form._hint) {
    const hint = document.createElement('small');
    hint.className = 'form-hint';
    hint.id = `form-hint-${++counter}`;
    hint.setAttribute('aria-live', 'polite');
    form.append(hint);
    form._hint = hint;
  }
  return form._hint;
}

export function refreshForm(form) {
  syncDependentLimits(form);
  const invalid = [];
  for (const element of fieldsOf(form)) {
    const message = paint(element, form);
    if (message && isActive(element)) invalid.push(element);
  }
  if (form.dataset.validate === 'messages') return invalid;
  const buttons = submitButtons(form);
  const hint = hintOf(form);
  if (invalid.length) {
    for (const button of buttons) {
      if (!button.disabled) { button.disabled = true; button.dataset.validityLock = '1'; }
      button.setAttribute('aria-describedby', hint.id);
    }
    const names = invalid.slice(0, 3).map(labelOf);
    hint.textContent = `Para continuar revisa: ${names.join(', ')}${invalid.length > 3 ? ` y ${invalid.length - 3} más` : ''}.`;
    hint.classList.remove('is-ready');
  } else {
    for (const button of buttons) {
      if (button.dataset.validityLock === '1') { button.disabled = false; delete button.dataset.validityLock; }
      button.removeAttribute('aria-describedby');
    }
    hint.textContent = '';
    hint.classList.remove('is-ready');
  }
  hint.hidden = !hint.textContent;
  return invalid;
}

export function enhanceForm(form) {
  const isFilter = form.id?.endsWith('-filter') || (form.classList.contains('filters') && !form.querySelector('[required]'));
  if (form.dataset.validate === 'off' || form.dataset.validityReady === '1' || isFilter) return;
  form.dataset.validityReady = '1';
  if (form.dataset.validate !== 'messages') form.noValidate = true;
  const touch = event => {
    const target = event.target;
    if (!isField(target)) return;
    target.dataset.touched = '1';
    refreshForm(form);
  };
  form.addEventListener('input', touch);
  form.addEventListener('focusout', touch);
  form.addEventListener('change', event => { if (isField(event.target)) event.target.dataset.touched = '1'; refreshForm(form); });
  form.addEventListener('click', () => setTimeout(() => refreshForm(form), 0));
  form.addEventListener('submit', event => {
    const invalid = refreshForm(form);
    if (!invalid.length) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    for (const element of invalid) element.dataset.touched = '1';
    refreshForm(form);
    invalid[0].focus();
  }, true);
  refreshForm(form);
  setTimeout(() => refreshForm(form), 0);
}

export function applyDataDimensions(root = document) {
  for (const element of root.querySelectorAll('[data-w]')) element.style.width = `${Math.max(0, Math.min(100, Number(element.dataset.w) || 0))}%`;
  for (const element of root.querySelectorAll('[data-h]')) element.style.height = `${Math.max(0, Math.min(100, Number(element.dataset.h) || 0))}%`;
}

export function startPanelUi(root = document) {
  let queued = false;
  const scan = () => {
    queued = false;
    for (const form of root.querySelectorAll('form')) enhanceForm(form);
    applyDataDimensions(root);
  };
  const schedule = () => { if (!queued) { queued = true; queueMicrotask(scan); } };
  new MutationObserver(schedule).observe(root.body || root, { childList: true, subtree: true });
  scan();
}
