// DLC icon system: own line icons (24 grid, 1.75 stroke, rounded caps, currentColor), shipped as one inline SVG sprite.
// Pure module: no DOM access at import time, so node tests can load it. Style rules live in styles.css (.icon).

const c = (cx, cy, r) => `<circle cx="${cx}" cy="${cy}" r="${r}"/>`;
const rect = (x, y, w, h, r = 2.5) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}"/>`;
const p = d => `<path d="${d}"/>`;

export const ICONS = Object.freeze({
  plus: p('M12 5v14M5 12h14'),
  copy: p('M9 9h10v11H9zM5 15V4.5h10'),
  mail: p('M3.5 6h17v12h-17zM4 7l8 6.5L20 7'),
  'flask': p('M9.5 3.5h5M10.5 3.5v6L5 19a1.5 1.5 0 001.3 2h11.4A1.5 1.5 0 0019 19l-5.5-9.5v-6M8 15h8'),
  'file-text': p('M7 3.5h7.5L19 8v12.5H7zM14.5 3.5V8H19M10 12.5h6M10 16h6'),
  bookmark: p('M7 4h10v16l-5-3.5L7 20z'),
  play: p('M8 5.5l11 6.5-11 6.5z'),
  'receipt-in': p('M6 3.5h12v17l-3-2-3 2-3-2-3 2zM9 8h6M9 12h6'),
  minus: p('M5 12h14'),
  check: p('M5 12.5l4.5 4.5L19 7.5'),
  xmark: p('M6 6l12 12M18 6L6 18'),
  'chevron-right': p('M9.5 6l6 6-6 6'),
  'chevron-left': p('M14.5 6l-6 6 6 6'),
  'chevron-down': p('M6 9.5l6 6 6-6'),
  'chevron-up': p('M6 14.5l6-6 6 6'),
  'arrow-up': p('M12 19V5M6 11l6-6 6 6'),
  'arrow-down': p('M12 5v14M6 13l6 6 6-6'),
  'trend-up': p('M3.5 17l6-6 4 4 7-7.5M15 7.5h5.5V13'),
  'trend-down': p('M3.5 7l6 6 4-4 7 7.5M15 16.5h5.5V11'),
  search: c(11, 11, 6.5) + p('M16 16l4.5 4.5'),
  pencil: p('M4 20l1-4L16.5 4.5a2 2 0 012.8 0l.2.2a2 2 0 010 2.8L8 19l-4 1zM14.5 6.5l3 3'),
  trash: p('M4.5 7h15M9.5 7V4.5h5V7M6.5 7l.8 12a1.5 1.5 0 001.5 1.4h6.4a1.5 1.5 0 001.5-1.4L17.5 7M10 11v6M14 11v6'),
  eye: p('M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z') + c(12, 12, 3),
  funnel: p('M4 5h16l-6.2 7.5V19l-3.6-2v-4.5z'),
  'arrow-down-doc': p('M7 3.5h7.5L19 8v12.5H7zM14.5 3.5V8H19M12 11v6M9.5 14.5L12 17l2.5-2.5'),
  'check-seal': p('M12 3l2.2 1.7 2.8-.2 1 2.6 2.4 1.5-.8 2.7.8 2.7-2.4 1.5-1 2.6-2.8-.2L12 21l-2.2-1.7-2.8.2-1-2.6-2.4-1.5.8-2.7-.8-2.7 2.4-1.5 1-2.6 2.8.2zM8.7 12.2l2.2 2.2 4.4-4.6'),
  lock: rect(5, 10.5, 14, 10, 2.5) + p('M8 10.5V8a4 4 0 018 0v2.5'),
  globe: c(12, 12, 9) + p('M3 12h18M12 3c2.8 3 2.8 15 0 18M12 3c-2.8 3-2.8 15 0 18'),
  sun: c(12, 12, 4) + p('M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6L7 7M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4'),
  moon: p('M20 14.5A8 8 0 019.5 4a8 8 0 1010.5 10.5z'),
  'half-circle': c(12, 12, 8.5) + '<path d="M12 3.5a8.5 8.5 0 010 17z" fill="currentColor"/>',
  sliders: p('M4 7h9M17 7h3M4 17h3M11 17h9') + c(15, 7, 2) + c(9, 17, 2),
  logout: p('M10 4.5H6.5a2 2 0 00-2 2v11a2 2 0 002 2H10M14 8l4 4-4 4M18 12H9.5'),
  dashboard: rect(4, 4, 7, 8) + rect(13, 4, 7, 5) + rect(13, 11, 7, 9) + rect(4, 14, 7, 6),
  store: p('M4 9.5l1.5-5h13l1.5 5M4 9.5a2.7 2.7 0 005.3 0 2.7 2.7 0 005.4 0 2.7 2.7 0 005.3 0M5.5 12.5V20h13v-7.5M10 20v-5h4v5'),
  pump: p('M6 20.5V5.5A1.5 1.5 0 017.5 4h6a1.5 1.5 0 011.5 1.5v15M4.5 20.5h12M8 8h5M15 10h2a1.5 1.5 0 011.5 1.5v5a1.2 1.2 0 002.4 0V9l-2.4-2.4'),
  tank: p('M5 7.5c0-1.7 3.1-3 7-3s7 1.3 7 3v9c0 1.7-3.1 3-7 3s-7-1.3-7-3zM5 7.5c0 1.7 3.1 3 7 3s7-1.3 7-3M9 14.5v2.5M12 13.5v3.5M15 15v2'),
  tag: p('M3.5 12.2V4.5a1 1 0 011-1h7.7l8.3 8.3a1.5 1.5 0 010 2.1l-6.1 6.1a1.5 1.5 0 01-2.1 0z') + c(8, 8, 1.3),
  clock: c(12, 12, 9) + p('M12 7v5l3.2 2'),
  drop: p('M12 3.5c3.5 4 6 7 6 10.5a6 6 0 01-12 0c0-3.5 2.5-6.5 6-10.5z'),
  'alert-triangle': p('M12 4l9 15.5H3zM12 10v4.2M12 17h.01'),
  'alert-circle': c(12, 12, 9) + p('M12 7.5v5.2M12 16h.01'),
  flag: p('M6 20.5V4M6 4.5h11l-2 4 2 4H6'),
  cart: p('M3.5 4.5h2.2l2 11h9.8l1.8-8H6.4') + c(10, 19.3, 1.1) + c(17, 19.3, 1.1),
  users: c(9, 8.5, 3.2) + p('M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5M16 5.6a3.2 3.2 0 010 5.8M17.5 14.3c2.2.5 3.5 2.4 3.5 4.7'),
  user: c(12, 8.5, 3.8) + p('M4.5 20c0-3.6 3.4-6 7.5-6s7.5 2.4 7.5 6'),
  key: c(8, 15, 3.5) + p('M10.5 12.5L19 4M16 7l2.5 2.5M14 9l2 2'),
  bag: p('M5 8h14l-1 12H6zM9 8V6.5a3 3 0 016 0V8'),
  receipt: p('M6 3.5h12v17l-2.5-1.7-1.8 1.7-1.7-1.7-1.8 1.7-1.7-1.7L6 20.5zM9 8.5h6M9 12h6M9 15.5h3'),
  banknote: rect(3, 6.5, 18, 11) + c(12, 12, 2.5) + p('M6.5 10h.01M17.5 14h.01'),
  wrench: p('M20 7.5l-3.2 3.2-3.5-.5-.5-3.5L16 3.5a5 5 0 00-6.2 6.7L3.7 16.3a2.1 2.1 0 003 3l6.1-6.1A5 5 0 0020 7.5z'),
  cube: p('M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9'),
  'chart-bar': p('M4.5 20.5h15M7 17v-6M12 17V5.5M17 17V9'),
  info: c(12, 12, 9) + p('M12 11v5.5M12 7.8h.01'),
  'circle-check': c(12, 12, 9) + p('M8 12.3l2.8 2.8 5.4-5.6'),
  'circle-x': c(12, 12, 9) + p('M9 9l6 6M15 9l-6 6'),
  refresh: p('M20 11a8 8 0 00-14.4-4.2L4 9M4 4.5V9h4.5M4 13a8 8 0 0014.4 4.2L20 15M20 19.5V15h-4.5'),
  menu: p('M4 7h16M4 12h16M4 17h16'),
  'map-pin': p('M12 21s6.5-5.6 6.5-11a6.5 6.5 0 00-13 0c0 5.4 6.5 11 6.5 11z') + c(12, 10, 2.3),
  calendar: rect(4, 5.5, 16, 15) + p('M4 10h16M8.5 3.5v4M15.5 3.5v4'),
  bell: p('M6 16.5V11a6 6 0 0112 0v5.5l1.5 1.5h-15zM10 20.5a2 2 0 004 0'),
  layers: p('M12 4l8.5 4.5L12 13 3.5 8.5zM3.5 12.5L12 17l8.5-4.5M3.5 16.5L12 21l8.5-4.5'),
  list: p('M8.5 7H20M8.5 12H20M8.5 17H20M4.5 7h.01M4.5 12h.01M4.5 17h.01'),
  edit: p('M4 20l1-4L16.5 4.5a2 2 0 012.8 0l.2.2a2 2 0 010 2.8L8 19l-4 1z'),
  save: p('M5 4.5h11l3.5 3.5v11.5a1 1 0 01-1 1h-13.5a1 1 0 01-1-1v-14a1 1 0 011-1zM8 4.5v5h7v-5M8 20v-6h8v6'),
  external: p('M13 5h6v6M19 5l-8 8M18 14v4.5a1.5 1.5 0 01-1.5 1.5h-10A1.5 1.5 0 015 18.5v-10A1.5 1.5 0 016.5 7H11'),
});

export const NAV_ICON = Object.freeze({
  dashboard: 'dashboard', cuts: 'clock', equipment: 'pump', inventory: 'drop', incidents: 'flag',
  prices: 'tag', purchases: 'cart', store: 'bag', cash: 'banknote',
  branches: 'store', staff: 'users', users: 'key', finance: 'receipt',
  reports: 'chart-bar', maintenance: 'wrench', assets: 'cube',
});

export function hasIcon(name) { return Object.hasOwn(ICONS, name); }

export function iconSprite() {
  const symbols = Object.entries(ICONS).map(([name, body]) => `<symbol id="i-${name}" viewBox="0 0 24 24">${body}</symbol>`).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" class="icon-sprite" width="0" height="0" aria-hidden="true" focusable="false">${symbols}</svg>`;
}

// Markup for one icon. `label` makes it an image for assistive technology; otherwise it is decorative.
export function icon(name, { size = 20, cls = '', label = '' } = {}) {
  const id = hasIcon(name) ? name : 'info';
  const a11y = label ? `role="img" aria-label="${String(label).replace(/"/g, '&quot;')}"` : 'aria-hidden="true"';
  return `<svg class="icon${cls ? ` ${cls}` : ''}" width="${size}" height="${size}" ${a11y} focusable="false"><use href="#i-${id}"/></svg>`;
}

// Inserts the sprite once. Safe to call repeatedly.
export function installIcons(doc = globalThis.document) {
  if (!doc?.body || doc.querySelector?.('.icon-sprite')) return;
  doc.body.insertAdjacentHTML('afterbegin', iconSprite());
}
