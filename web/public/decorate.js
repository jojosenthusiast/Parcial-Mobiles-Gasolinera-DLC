// Light pass for modules that still use the legacy markup: gives their buttons the semantic colour + icon of DESIGN.md section 4.
// classifyAction is pure (tested); decorateButtons/startDecorators touch the DOM.
import { icon } from './icons.js';
import { ACTIONS } from './components.js';

const fold = text => String(text ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[→↻]/g, '').trim();

const RULES = [
  ['approve', /^(aprobar|autorizar|verificar y habilitar)/],
  ['delete', /^(eliminar|rechazar|anular|retirar|revocar|descartar|desactivar)/],
  ['cancel', /^(cancelar|cerrar ficha|cerrar detalle|volver)/],
  ['edit', /^(editar|modificar|corregir)/],
  ['export', /^(exportar|descargar|imprimir)/],
  ['refresh', /^(actualizar|reintentar|recargar)/],
  ['filter', /^(filtrar|aplicar filtro)/],
  ['search', /^(buscar)/],
  ['create', /^(crear|nuevo|nueva|agregar|anadir|registrar|proponer|abrir caja|generar|iniciar)/],
  ['save', /^(guardar|confirmar|enviar|entrar|aplicar|programar|preparar|cerrar |activar|asignar|habilitar|cobrar|pagar|recibir)/],
  ['view', /^(ver|abrir|mostrar|consultar)/],
];

export function classifyAction(text) {
  const t = fold(text);
  if (!t) return null;
  for (const [kind, rule] of RULES) if (rule.test(t)) return kind;
  return null;
}

const SWAP = { delete: 'btn-danger', approve: 'btn-approve', edit: 'btn-neutral', cancel: 'btn-neutral', export: 'btn-neutral', refresh: 'btn-neutral', filter: 'btn-neutral', search: 'btn-neutral' };

export function decorateButtons(root) {
  const nodes = root.matches?.('button') ? [root, ...root.querySelectorAll('button')] : [...(root.querySelectorAll?.('button') || [])];
  for (const button of nodes) {
    if (button.dataset.decorated || button.classList.contains('btn') || button.classList.contains('icon-button') || button.classList.contains('nav-link') || button.closest('.cb,.segmented,.menu-pop,.user-chip,.group-head')) continue;
    if (!button.matches('.primary,.secondary,.text-button')) continue;
    if (button.querySelector('svg')) { button.dataset.decorated = '1'; continue; }
    const kind = classifyAction(button.textContent);
    button.dataset.decorated = '1';
    if (!kind) continue;
    if (button.classList.contains('text-button')) {
      button.innerHTML = `${button.innerHTML.replace(/\s*→\s*$/, '')}${icon(kind === 'edit' ? 'pencil' : 'chevron-right', { size: 16 })}`;
      continue;
    }
    const a = ACTIONS[kind] || ACTIONS.view;
    button.classList.add('btn-icon');
    if (SWAP[kind]) button.classList.remove('primary', 'secondary'), button.classList.add('btn', SWAP[kind]);
    button.insertAdjacentHTML('afterbegin', icon(a.icon, { size: 18 }));
  }
}

export function startDecorators(root = document.body) {
  decorateButtons(root);
  let queued = false;
  new MutationObserver(() => { if (queued) return; queued = true; queueMicrotask(() => { queued = false; decorateButtons(root); }); }).observe(root, { childList: true, subtree: true });
}
