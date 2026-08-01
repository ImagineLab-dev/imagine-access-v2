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

  // ---------------------------------------------------------------------------
  // Doble envío: navegador + servidor, con el MISMO identificador
  // ---------------------------------------------------------------------------
  // El píxel del navegador se pierde cuando algo lo bloquea. Medido en la
  // campaña del 29/07/2026: 70 clics al enlace, 24 vistas de landing. Dos de
  // cada tres llegadas no llegaban, casi todas de iOS.
  //
  // Cada evento sale por los dos caminos con el mismo `event_id`. Meta los une
  // y cuenta UNO. Si cada lado generara el suyo contaría DOS, que es peor que
  // perder eventos: inflaría las conversiones y el optimizador de la campaña
  // trabajaría sobre números falsos. Por eso el identificador se genera acá,
  // una sola vez, y se le pasa a los dos.

  var ECO = 'https://api.imaginecloud.digital/functions/v1/meta_evento';

  function id() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    // Navegadores viejos: alcanza con que no se repita entre visitantes.
    return 'e-' + Date.now().toString(36) + '-' +
      Math.random().toString(36).slice(2, 12);
  }

  function cookie(nombre) {
    var m = document.cookie.match('(^|;)\\s*' + nombre + '\\s*=\\s*([^;]+)');
    return m ? m.pop() : null;
  }

  /* Se asegura de que `_fbp` exista ANTES de arrancar el píxel.
   *
   * Sin esto el envío por servidor salía casi siempre sin `_fbp`, y Meta lo
   * midió: de 14 eventos de servidor, 2 la llevaban. El 14 %.
   *
   * La causa es una carrera. `fbevents.js` se carga async, y el PageView se
   * manda apenas se inicializa el píxel: en ese instante el script de Meta
   * todavía no corrió, así que la cookie que él crea no existe. Los únicos que
   * la mandaban eran los visitantes repetidos, que ya la traían de antes —y
   * eso es exactamente 2 de 14—.
   *
   * Escribirla acá la vuelve determinista: existe desde el primer instante,
   * el píxel adopta la que encuentra en vez de generar otra, y las dos mitades
   * mandan el mismo valor. Formato de Meta: fb.<subdominio>.<ms>.<aleatorio>,
   * con 1 para un dominio de dos partes como el nuestro.
   *
   * Se comparte entre la landing y la app porque están en el mismo host, así
   * que Meta puede unir "vio la landing" con "abrió la app".
   */
  function asegurarFbp() {
    if (cookie('_fbp')) return;
    var aleatorio = Math.floor(Math.random() * 2147483647);
    var valor = 'fb.1.' + Date.now() + '.' + aleatorio;
    var vence = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toUTCString();
    document.cookie = '_fbp=' + valor + ';expires=' + vence +
      ';path=/;SameSite=Lax' + (location.protocol === 'https:' ? ';Secure' : '');
  }

  /* De qué clic de anuncio viene esta visita.
   *
   * Es el dato más valioso del envío por servidor: sin él la conversión llega
   * anónima y Meta no la puede atribuir a ninguna campaña.
   *
   * Se lee la cookie `_fbc`, pero en la PRIMERA visita todavía no existe —el
   * píxel la escribe después de cargar— así que se arma a mano desde `fbclid`
   * de la URL, que es justamente el caso que importa: alguien que acaba de
   * llegar desde el anuncio. Formato de Meta: fb.<subdominio>.<ms>.<fbclid>,
   * y el 1 corresponde a un dominio de dos partes como el nuestro. */
  function clicDeAnuncio() {
    var c = cookie('_fbc');
    if (c) return c;
    try {
      var fbclid = new URLSearchParams(location.search).get('fbclid');
      if (fbclid) return 'fb.1.' + Date.now() + '.' + fbclid;
    } catch (_) { /* URLSearchParams no soportado: se va sin fbc */ }
    return null;
  }

  function alServidor(nombre, eventId, datos) {
    try {
      fetch(ECO, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        // Sin esto el navegador CANCELA la petición al salir de la página, y
        // justamente el evento que más importa —el clic al botón— se dispara
        // mientras se está yendo.
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
      }).catch(function () { /* medir no puede romper la página */ });
    } catch (_) { /* idem */ }
  }

  /** Manda el evento por los dos caminos. */
  function evento(tipo, nombre, datos) {
    var eventId = id();
    fbq(tipo, nombre, datos || {}, { eventID: eventId });
    alServidor(nombre, eventId, datos);
  }

  // ANTES del init, no después: el píxel adopta la cookie que ya encuentra.
  asegurarFbp();

  fbq('init', PIXEL_ID);
  evento('track', 'PageView');

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
    evento('trackCustom', 'ClicProbarGratis', {
      donde: a.closest('header') ? 'navegacion'
           : seccion && seccion.id ? seccion.id
           : 'hero',
      texto: (a.textContent || '').trim().slice(0, 40)
    });
  }, true);
})();
