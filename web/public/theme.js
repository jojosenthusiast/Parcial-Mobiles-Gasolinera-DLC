// Theme preference (Claro / Oscuro / Sistema). Loaded as a blocking classic script in <head> to avoid a flash of the wrong theme.
(function () {
  var KEY = 'dlc.theme';
  var root = document.documentElement;
  var colors = { light: '#faf5ec', dark: '#14110f' };

  function read() {
    try {
      var value = localStorage.getItem(KEY);
      return value === 'light' || value === 'dark' ? value : 'system';
    } catch (error) { return 'system'; }
  }

  function write(mode) {
    try {
      if (mode === 'system') localStorage.removeItem(KEY);
      else localStorage.setItem(KEY, mode);
    } catch (error) { /* storage can be blocked; the choice then lasts for this page view only */ }
  }

  function prefersDark() {
    return typeof matchMedia === 'function' && matchMedia('(prefers-color-scheme: dark)').matches;
  }

  function sync(mode) {
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', (mode === 'dark' || (mode === 'system' && prefersDark())) ? colors.dark : colors.light);
    var buttons = document.querySelectorAll('[data-theme-choice]');
    for (var i = 0; i < buttons.length; i++) buttons[i].setAttribute('aria-pressed', String(buttons[i].getAttribute('data-theme-choice') === mode));
  }

  function apply(mode) {
    if (mode === 'light' || mode === 'dark') root.setAttribute('data-theme', mode);
    else root.removeAttribute('data-theme');
    sync(mode);
  }

  function choose(mode) {
    write(mode);
    apply(mode);
  }

  apply(read());

  document.addEventListener('DOMContentLoaded', function () {
    var buttons = document.querySelectorAll('[data-theme-choice]');
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].addEventListener('click', function (event) { choose(event.currentTarget.getAttribute('data-theme-choice')); });
    }
    sync(read());
  });

  if (typeof matchMedia === 'function') {
    var query = matchMedia('(prefers-color-scheme: dark)');
    var onChange = function () { if (read() === 'system') sync('system'); };
    if (query.addEventListener) query.addEventListener('change', onChange);
    else if (query.addListener) query.addListener(onChange);
  }

  window.dlcTheme = { get: read, set: choose };
})();
