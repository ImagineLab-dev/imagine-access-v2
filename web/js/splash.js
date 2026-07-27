/**
 * Quita la pantalla de carga cuando Flutter dibuja su primer frame.
 *
 * No alcanza con esperar el evento `load` de la ventana: para entonces el
 * bundle todavía se está compilando y arrancando, y la app aún no pintó nada.
 * Quitar el splash ahí deja unos segundos de pantalla vacía, que es
 * exactamente el parpadeo que se quiere evitar.
 *
 * Flutter web monta su superficie de dibujo como un elemento propio dentro del
 * body (`flutter-view`, o `flt-glass-pane` en versiones anteriores). Observar
 * su aparición es la señal más fiable de "ya hay algo en pantalla" sin
 * depender de APIs internas del engine, que cambian entre versiones.
 */
'use strict';

(function () {
  var splash = document.getElementById('app-splash');
  if (!splash) return;

  var SELECTOR = 'flutter-view, flt-glass-pane, flt-scene-host';
  var LIMITE_MS = 20000;
  var terminado = false;

  function ocultar() {
    if (terminado) return;
    terminado = true;

    if (observador) observador.disconnect();
    clearTimeout(temporizador);

    splash.classList.add('hidden');
    // Se elimina del DOM recién al terminar la transición: si se quitara antes,
    // el fundido se cortaría de golpe.
    splash.addEventListener('transitionend', function () {
      if (splash.parentNode) splash.parentNode.removeChild(splash);
    }, { once: true });

    // Respaldo por si el navegador no dispara transitionend (pasa si la
    // pestaña está en segundo plano cuando ocurre).
    setTimeout(function () {
      if (splash.parentNode) splash.parentNode.removeChild(splash);
    }, 600);
  }

  // Un frame extra después de detectar la superficie: el elemento existe un
  // instante antes de tener contenido dibujado, y sin esta espera se alcanza a
  // ver un fotograma en negro.
  function ocultarTrasPintar() {
    requestAnimationFrame(function () {
      requestAnimationFrame(ocultar);
    });
  }

  if (document.querySelector(SELECTOR)) {
    ocultarTrasPintar();
    return;
  }

  var observador = new MutationObserver(function () {
    if (document.querySelector(SELECTOR)) ocultarTrasPintar();
  });

  observador.observe(document.body, { childList: true, subtree: true });

  // Red de seguridad: si algo falla al arrancar la app, es preferible mostrar
  // lo que haya —aunque sea un error— antes que dejar el splash para siempre.
  var temporizador = setTimeout(ocultar, LIMITE_MS);
})();
