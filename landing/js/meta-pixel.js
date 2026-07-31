/* Meta Pixel de la landing — 1083477920911623
 *
 * Mismo píxel que la app, a propósito: es un solo embudo y Meta necesita ver
 * la secuencia completa desde el anuncio hasta el cobro.
 *
 *   landing   PageView, ClicProbarGratis
 *   app       PageView, CompleteRegistration, InitiateCheckout
 *   servidor  Purchase, Subscribe   (desde dlocal_webhook, vía CAPI)
 *
 * `PageView` acá NO duplica el de la app: son dos documentos distintos, y así
 * se puede medir cuántos de los que ven la landing llegan a abrir la app.
 *
 * El clic en los botones va como evento PROPIO y no como `Lead`.
 * `CompleteRegistration` ya significa "creó la cuenta" y se dispara en
 * login_screen.dart; usar un evento estándar para un simple clic mezclaría
 * intención con conversión y dejaría al optimizador de la campaña persiguiendo
 * clics en vez de cuentas. Con un evento propio se mide qué creatividad trae
 * gente, mientras la campaña sigue optimizando sobre la cuenta creada.
 *
 * Va en un archivo externo porque la CSP del sitio no permite `unsafe-inline`
 * en script-src: el fragmento que da Meta, pegado tal cual en el HTML, sería
 * bloqueado sin ejecutarse jamás. El único síntoma sería un error de política
 * en la consola y cero eventos en el administrador — el tipo de falla que se
 * descubre semanas después, con el presupuesto ya gastado.
 */
(function () {
  'use strict';

  var PIXEL_ID = '1083477920911623';

  // Guarda contra doble ejecución. El cargador de Meta se protege a sí mismo
  // (`if (f.fbq) return`), pero eso no impide que un segundo `track('PageView')`
  // salga si este archivo llegara a evaluarse dos veces.
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

  fbq('init', PIXEL_ID);
  fbq('track', 'PageView');

  // ---------------------------------------------------------------------------
  // Clic en cualquier botón que lleve a la app
  // ---------------------------------------------------------------------------
  // Delegado en el documento y no un listener por botón: hay cinco CTA
  // repartidos por la página y uno más en la navegación. Enganchar cada uno
  // significa que el día que se agregue un sexto se olvide.
  //
  // `dónde` distingue el botón de arriba del de la sección de precio, que es
  // justamente lo que hace falta para saber cuánto de la página leyeron antes
  // de decidirse.
  document.addEventListener('click', function (e) {
    var a = e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;

    // Solo los que salen hacia la app. Los enlaces internos de la navegación
    // (#precio, #preguntas) no son intención de registro.
    if (a.getAttribute('href').indexOf('imaginecloud.digital') === -1) return;

    var seccion = a.closest('section');
    fbq('trackCustom', 'ClicProbarGratis', {
      donde: a.closest('header') ? 'navegacion'
           : seccion && seccion.id ? seccion.id
           : 'hero',
      texto: (a.textContent || '').trim().slice(0, 40)
    });
  }, true);
})();
