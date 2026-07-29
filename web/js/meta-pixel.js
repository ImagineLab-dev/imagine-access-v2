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

  fbq('init', PIXEL_ID);
  fbq('track', 'PageView');
})();
