/* Meta Pixel — 1083477920911623
 *
 * Va en un archivo externo y no en línea dentro de index.html: la CSP del sitio
 * no permite `unsafe-inline` en script-src, así que el fragmento que da Meta,
 * pegado tal cual, sería bloqueado por el navegador sin ejecutarse jamás. El
 * único síntoma sería un error de política en la consola y cero eventos en el
 * administrador — que es exactamente el tipo de fallo que se descubre semanas
 * después, con la campaña ya gastada.
 *
 * La app es una SPA: el navegador carga la página una sola vez y después
 * navega por rutas sin recargar. Por eso `PageView` se dispara UNA vez, acá, y
 * no hay ningún enganche a los cambios de ruta. Agregarlo duplicaría el evento
 * en cada pantalla que abra el usuario.
 */
(function () {
  'use strict';

  var PIXEL_ID = '1083477920911623';

  // Guarda contra doble ejecución. El cargador de Meta ya se protege a sí mismo
  // (`if (f.fbq) return`), pero eso NO impide que un segundo `track('PageView')`
  // se dispare si este archivo llegara a evaluarse dos veces — por el service
  // worker, por un `import` repetido o por una recarga parcial.
  if (window.__imagineMetaPixelCargado) return;
  window.__imagineMetaPixelCargado = true;

  // Cargador oficial de Meta, sin modificar.
  !function (f, b, e, v, n, t, s) {
    if (f.fbq) return;
    n = f.fbq = function () {
      n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments);
    };
    if (!f._fbq) f._fbq = n;
    n.push = n;
    n.loaded = !0;
    n.version = '2.0';
    n.queue = [];
    t = b.createElement(e);
    t.async = !0;
    t.src = v;
    s = b.getElementsByTagName(e)[0];
    s.parentNode.insertBefore(t, s);
  }(window, document, 'script',
    'https://connect.facebook.net/en_US/fbevents.js');

  // ---------------------------------------------------------------------------
  // Doble envío: navegador + servidor, con el MISMO identificador
  // ---------------------------------------------------------------------------
  // Mismo mecanismo que la landing, por el mismo motivo: lo que el navegador
  // no puede mandar —bloqueado por extensiones o por la prevención de rastreo
  // de iOS— lo manda el servidor, y Meta une los dos por `event_name` +
  // `event_id` y cuenta UNO.
  //
  // Acá hacía más falta que en la landing. El diagnóstico de Meta del
  // 01/08/2026 mostraba que solo el 13,45 % de los eventos del navegador
  // llevaban identificador, y que el servidor mandaba 443 eventos menos que el
  // píxel en siete días: eran justamente los de la app, que salían solo por
  // navegador y sin con qué deduplicarlos.

  var ECO = 'https://api.imaginecloud.digital/functions/v1/meta_evento';

  function id() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'e-' + Date.now().toString(36) + '-' +
      Math.random().toString(36).slice(2, 12);
  }

  function cookie(nombre) {
    var m = document.cookie.match('(^|;)\\s*' + nombre + '\\s*=\\s*([^;]+)');
    return m ? m.pop() : null;
  }

  /* Crea `_fbp` si no existe, ANTES de arrancar el píxel.
   *
   * `fbevents.js` carga async, así que si se lee la cookie apenas se inicializa
   * el píxel todavía no está: el evento sale sin ella y Meta pierde con qué
   * cotejarlo. Medido en la landing antes de arreglarlo: 2 de 14 eventos de
   * servidor la llevaban, y esos 2 eran visitantes repetidos.
   *
   * Escribirla nosotros la vuelve determinista, y el píxel adopta la que
   * encuentra. Como la landing y la app comparten host, además es la MISMA
   * cookie en las dos: así Meta puede unir "vio la landing" con "abrió la app",
   * que es justo el salto que hoy no se ve. */
  function asegurarFbp() {
    if (cookie('_fbp')) return;
    var valor = 'fb.1.' + Date.now() + '.' +
      Math.floor(Math.random() * 2147483647);
    var vence = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toUTCString();
    document.cookie = '_fbp=' + valor + ';expires=' + vence +
      ';path=/;SameSite=Lax' + (location.protocol === 'https:' ? ';Secure' : '');
  }

  /* Cuál clic de anuncio trajo a esta persona, PERSISTIDO.
   *
   * Igual que en la landing y por el mismo motivo: es el parámetro más valioso
   * para la atribución, y hasta ahora salía en 0% desde el servidor porque el
   * `fbclid` solo vive en la URL de la landing. Al llegar acá —la app— ya no
   * está, y el evento que importa, CompleteRegistration, se disparaba sin fbc.
   *
   * Guardar `_fbc` con `path=/` la primera vez que se lo ve hace que sobreviva
   * de la landing a la app, que comparten host, y ate el clic hasta la
   * conversión. */
  function clicDeAnuncio() {
    var c = cookie('_fbc');
    if (c) return c;
    try {
      var fbclid = new URLSearchParams(location.search).get('fbclid');
      if (!fbclid) return null;
      var valor = 'fb.1.' + Date.now() + '.' + fbclid;
      var vence = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toUTCString();
      document.cookie = '_fbc=' + valor + ';expires=' + vence +
        ';path=/;SameSite=Lax' + (location.protocol === 'https:' ? ';Secure' : '');
      return valor;
    } catch (_) { /* sin fbc */ }
    return null;
  }

  function alServidor(nombre, eventId, datos) {
    try {
      fetch(ECO, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        // La app puede navegar o cerrarse justo después del evento.
        keepalive: true,
        body: JSON.stringify({
          nombre: nombre,
          eventId: eventId,
          urlOrigen: location.href,
          fbp: cookie('_fbp'),
          fbc: clicDeAnuncio(),
          momento: Math.floor(Date.now() / 1000),
          datos: datos || null
        })
      }).catch(function () { /* medir no puede romper la app */ });
    } catch (_) { /* idem */ }
  }

  /**
   * Manda un evento por los dos caminos.
   *
   * Expuesto en `window.imagineMeta` porque Dart también dispara eventos
   * (`CompleteRegistration`, `ViewContent`, `InitiateCheckout`) y tiene que
   * pasar por acá: si llamara a `fbq` directo, saldrían sin identificador y sin
   * copia de servidor, que es exactamente el estado que esto viene a arreglar.
   */
  function evento(nombre, datos) {
    var eventId = id();
    try {
      fbq('track', nombre, datos || {}, { eventID: eventId });
    } catch (_) { /* el píxel puede estar bloqueado; el servidor sigue yendo */ }
    alServidor(nombre, eventId, datos);
  }

  window.imagineMeta = { evento: evento };

  asegurarFbp();
  fbq('init', PIXEL_ID);
  evento('PageView');
})();
