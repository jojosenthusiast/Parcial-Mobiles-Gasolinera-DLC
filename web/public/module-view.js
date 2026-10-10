// Partial-render infrastructure: stale-while-revalidate cache, request sequencing/abort, and a region view that only repaints its own zone.
// Filters live outside the region, so changing one never blanks the page: previous data stays visible (dimmed) until the response lands.

export const DEFAULT_TTL = 60_000;

export function createCache({ ttl = DEFAULT_TTL, max = 80, now = () => Date.now() } = {}) {
  const store = new Map();
  return {
    get(key) {
      const hit = store.get(key);
      if (!hit) return null;
      return { data: hit.data, at: hit.at, fresh: now() - hit.at < ttl };
    },
    set(key, data) {
      store.delete(key);
      store.set(key, { data, at: now() });
      while (store.size > max) store.delete(store.keys().next().value);
    },
    clear(prefix = '') {
      if (!prefix) { store.clear(); return; }
      for (const key of [...store.keys()]) if (key.startsWith(prefix)) store.delete(key);
    },
    get size() { return store.size; },
  };
}

// Deterministic key from an ordered list of parts (objects are key-sorted).
export function cacheKey(...parts) {
  const norm = value => {
    if (Array.isArray(value)) return value.map(norm);
    if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, norm(value[k])]));
    return value ?? null;
  };
  return JSON.stringify(norm(parts));
}

// Only the most recent request may paint; earlier ones are ignored when they land late.
export function createSequencer() {
  let n = 0;
  return { next: () => ++n, isCurrent: token => token === n, current: () => n };
}

export const isAbortError = error => error?.name === 'AbortError' || error?.code === 20;

// Region view: `load(signal, params)` fetches in parallel, `render(data, params)` returns HTML for the region only.
export function createModuleView({ region, cache, keyOf, load, render, afterRender = () => {}, skeleton = () => '', errorMarkup, clock = () => Date.now(), formatClock = ms => new Date(ms).toLocaleTimeString() }) {
  const seq = createSequencer();
  let controller = null;
  let shownKey = null;
  let hasContent = false;
  let lastAt = 0;
  let lastData = null;
  let lastShownParams;
  let destroyed = false;

  const setBusy = busy => {
    region.classList.toggle('is-loading', busy && hasContent);
    region.setAttribute('aria-busy', busy ? 'true' : 'false');
  };

  function paint(data, params, { first }) {
    lastData = data; lastShownParams = params;
    region.innerHTML = render(data, params);
    hasContent = true;
    region.classList.remove('is-error');
    afterRender(region, data, params, { first });
  }

  function showStaleBanner(error) {
    region.querySelector('.stale-banner')?.remove();
    const when = lastAt ? ` Datos de las ${formatClock(lastAt)}.` : '';
    region.insertAdjacentHTML('afterbegin', `<div class="stale-banner" role="status"><span>No se pudo actualizar.${when}</span><button type="button" class="text-button" data-retry-view>Reintentar</button></div>`);
    region.querySelector('[data-retry-view]')?.addEventListener('click', () => refresh({ force: true }));
    return error;
  }

  let lastParams;
  async function refresh({ force = false, params = lastParams } = {}) {
    if (destroyed) return;
    lastParams = params;
    const token = seq.next();
    controller?.abort();
    controller = new AbortController();
    const key = keyOf(params);
    const cached = cache.get(key);
    const sameKey = shownKey === key;
    if (cached) {
      if (!sameKey || force) { paint(cached.data, params, { first: !hasContent || !sameKey }); shownKey = key; lastAt = cached.at; }
      if (cached.fresh && !force) { setBusy(false); return; }
    } else if (!hasContent) {
      region.innerHTML = skeleton(params);
    }
    setBusy(true);
    try {
      const data = await load(controller.signal, params);
      if (!seq.isCurrent(token) || destroyed) return;
      cache.set(key, data);
      lastAt = clock();
      const first = !hasContent || shownKey !== key;
      paint(data, params, { first });
      shownKey = key;
    } catch (error) {
      if (isAbortError(error) || !seq.isCurrent(token) || destroyed) return;
      if (hasContent) showStaleBanner(error);
      else {
        region.innerHTML = errorMarkup ? errorMarkup(error) : '';
        region.querySelector('#retry')?.addEventListener('click', () => refresh({ force: true }));
        region.classList.add('is-error');
      }
      throw error;
    } finally {
      if (seq.isCurrent(token)) setBusy(false);
    }
  }

  return {
    refresh: opts => refresh(opts).catch(() => undefined),
    refreshStrict: refresh,
    // Re-renders the data already on screen (for example after a units or decimals preference changed) without any request.
    repaint() { if (hasContent && !destroyed && lastData) paint(lastData, lastShownParams, { first: false }); },
    destroy() { destroyed = true; controller?.abort(); },
    get hasContent() { return hasContent; },
  };
}

// Debounce used by search boxes so typing never fires one request per keystroke.
export function debounce(fn, wait = 220) {
  let timer = null;
  const wrapped = (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), wait); };
  wrapped.cancel = () => clearTimeout(timer);
  return wrapped;
}

// Runs requests in parallel but never fails the whole module for optional ones.
export async function settleAll(tasks) {
  const results = await Promise.allSettled(tasks);
  return results.map(r => (r.status === 'fulfilled' ? r.value : null));
}

