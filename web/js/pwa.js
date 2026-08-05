/**
 * Registro del service worker y aviso de actualización.
 *
 * En un sistema de control de acceso, un dispositivo de puerta corriendo una
 * versión vieja indefinidamente es un problema real: valida con reglas que ya
 * cambiaron. Pero recargar solo, sin avisar, en mitad de una validación es
 * peor. Por eso el SW nuevo queda esperando y el usuario decide cuándo aplicar.
 */
'use strict';

(function () {
  if (!('serviceWorker' in navigator)) return;

  var BANNER_ID = 'pwa-update-banner';

  function showUpdateBanner(waitingWorker) {
    if (document.getElementById(BANNER_ID)) return;

    var bar = document.createElement('div');
    bar.id = BANNER_ID;
    bar.setAttribute('role', 'status');
    bar.style.cssText = [
      'position:fixed', 'left:0', 'right:0', 'top:0', 'z-index:2147483647',
      'display:flex', 'align-items:center', 'justify-content:center',
      'gap:16px', 'flex-wrap:wrap',
      'padding:12px 16px', 'background:#AED500', 'color:#293500',
      'border-bottom:1px solid #293500',
      'font:700 13px/1.4 system-ui,-apple-system,Segoe UI,Roboto,sans-serif',
      'letter-spacing:.4px',
    ].join(';');

    var text = document.createElement('span');
    text.textContent = 'Hay una versión nueva disponible.';

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = 'Actualizar';
    btn.style.cssText = [
      'padding:8px 20px', 'border:0', 'border-radius:0', 'cursor:pointer',
      'background:#0A0A0B', 'color:#AED500',
      'font:600 14px/1 system-ui,-apple-system,Segoe UI,Roboto,sans-serif',
    ].join(';');

    var later = document.createElement('button');
    later.type = 'button';
    later.textContent = 'Más tarde';
    later.style.cssText = [
      'padding:8px 12px', 'border:0', 'background:transparent',
      'color:rgba(41,53,0,.65)', 'cursor:pointer',
      'font:400 13px/1 system-ui,-apple-system,Segoe UI,Roboto,sans-serif',
    ].join(';');

    btn.addEventListener('click', function () {
      btn.disabled = true;
      btn.textContent = 'Actualizando…';
      waitingWorker.postMessage({ type: 'SKIP_WAITING' });
    });

    later.addEventListener('click', function () {
      bar.remove();
    });

    bar.appendChild(text);
    bar.appendChild(btn);
    bar.appendChild(later);
    document.body.appendChild(bar);
  }

  /// Aplica la versión que está esperando. Dispara `controllerchange`, que
  /// recarga la página.
  function aplicarAhora(waiting) {
    waiting.postMessage({ type: 'SKIP_WAITING' });
  }

  /**
   * Decide entre aplicar sola o preguntar.
   *
   * Antes SIEMPRE preguntaba con un banner, y en el teléfono eso dejaba a la
   * gente con la versión vieja indefinidamente. El motivo es cómo sirve el
   * service worker: las navegaciones van a red primero —así que el index.html
   * llega nuevo— pero los estáticos salen del caché de la versión vieja, y ese
   * caché sigue en uso mientras el SW nuevo esté esperando. O sea: HTML nuevo,
   * app vieja, hasta que alguien toque el aviso. Si el aviso no se ve o se
   * ignora, el teléfono no se actualiza más.
   *
   * La regla ahora es por momento, no siempre la misma:
   *
   *   - **Recién cargó la página**: se aplica sola. La recarga ocurre antes de
   *     que nadie haya hecho nada; se siente como una carga un poco más lenta.
   *   - **La app está en segundo plano**: se aplica sola. Nadie está mirando.
   *   - **La app está abierta y en uso**: se pregunta. Es el único caso donde
   *     recargar puede interrumpir algo —una validación en la puerta— y es
   *     exactamente el caso para el que se escribió el aviso.
   */
  function resolverActualizacion(waiting, recienCargada) {
    if (recienCargada || document.visibilityState === 'hidden') {
      aplicarAhora(waiting);
      return;
    }
    showUpdateBanner(waiting);
  }

  function watchForUpdate(registration) {
    // Quedó una esperando de una visita anterior: es justo el arranque, se
    // aplica sin preguntar.
    if (registration.waiting) {
      resolverActualizacion(registration.waiting, true);
    }

    registration.addEventListener('updatefound', function () {
      var installing = registration.installing;
      if (!installing) return;
      installing.addEventListener('statechange', function () {
        // 'installed' con un controller ya activo significa que hay una versión
        // nueva esperando. Sin controller es la primera instalación: nada que
        // avisar, el usuario ya está viendo la versión más reciente.
        if (installing.state === 'installed' && navigator.serviceWorker.controller) {
          resolverActualizacion(installing, false);
        }
      });
    });
  }

  var registroActual = null;

  window.imaginePWA = {
    /**
     * Busca una versión nueva ahora mismo.
     *
     * Existe porque el chequeo automático es horario y solo corre con la app
     * abierta: alguien que cierra y abre puede quedarse sin saber que hay algo
     * nuevo hasta la próxima carga. En iPhone importa más, porque el sistema
     * suspende la app y ese temporizador deja de correr.
     *
     * Resuelve 'nueva' si quedó una versión esperando —ahí aparece el aviso
     * para aplicarla—, 'al-dia' si no hay nada, o 'sin-soporte'.
     */
    buscarActualizacion: function () {
      if (!registroActual) return Promise.resolve('sin-soporte');
      return registroActual.update()
        .then(function () {
          // `update()` resuelve cuando termina de consultar, pero el nuevo
          // worker puede seguir instalándose. Se le da un momento antes de
          // decidir, o diría 'al-dia' con la versión nueva a medio instalar.
          return new Promise(function (r) { setTimeout(r, 1500); });
        })
        .then(function () {
          if (registroActual.waiting) {
            showUpdateBanner(registroActual.waiting);
            return 'nueva';
          }
          return registroActual.installing ? 'nueva' : 'al-dia';
        })
        .catch(function () { return 'sin-soporte'; });
    },
  };

  // ¿Había un service worker a cargo cuando esta página cargó?
  //
  // Se mira ACÁ, al evaluar el script, y no dentro del listener: para cuando
  // `controllerchange` dispara, `controller` ya apunta al nuevo y la respuesta
  // sería siempre "sí".
  var habiaControlador = !!navigator.serviceWorker.controller;

  var refreshing = false;
  navigator.serviceWorker.addEventListener('controllerchange', function () {
    // PRIMERA VISITA: no había controlador. El service worker se instala, se
    // activa y hace `clients.claim()`, que toma el control de esta página —y eso
    // dispara `controllerchange` aunque no haya ninguna versión nueva que
    // aplicar—. Recargar acá es recargar sobre una página que ya está bien.
    //
    // El costo era real y medible: un visitante nuevo pedía el documento cuatro
    // veces y descargaba `main.dart.js` DOS veces, 5,2 MB cada una. En un
    // teléfono con 4G en la calle son varios segundos extra y el doble de datos,
    // con la pantalla recargándose encima. Para alguien que llega desde un
    // anuncio, eso se lee como que la app se rompió.
    //
    // Solo se recarga cuando de verdad cambió el worker que estaba a cargo, que
    // es el caso para el que se escribió esto: aplicar una actualización que la
    // persona ya aceptó.
    if (!habiaControlador) return;

    if (refreshing) return;   // guard: Chrome puede disparar esto más de una vez
    refreshing = true;
    window.location.reload();
  });

  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js').then(function (registration) {
      registroActual = registration;
      watchForUpdate(registration);

      // Chequeo horario: un dispositivo de puerta puede quedar abierto todo un
      // evento sin recargar nunca.
      setInterval(function () {
        registration.update().catch(function () {});
      }, 60 * 60 * 1000);

      // Y uno cada vez que la app vuelve al frente.
      //
      // El temporizador de arriba solo corre mientras la pestaña está viva. En
      // una PWA instalada en iPhone el sistema SUSPENDE la app al salir, así que
      // ese intervalo en la práctica no llega nunca a dispararse: se desplegaba
      // una versión nueva y el teléfono seguía con la vieja indefinidamente,
      // porque los estáticos se sirven caché-primero y el service worker viejo
      // sigue a cargo hasta que se activa el nuevo.
      //
      // Volver al frente es el momento natural para preguntar: la persona acaba
      // de abrir la app, no está en medio de nada. El aviso sigue pidiendo
      // permiso —no se recarga nada sin que lo acepte—, así que un dispositivo
      // de puerta no se ve interrumpido por esto.
      //
      // Se limita a una consulta cada dos minutos para que alternar entre apps
      // no dispare una por cada cambio de foco.
      var ultimaConsulta = 0;
      document.addEventListener('visibilitychange', function () {
        if (document.visibilityState !== 'visible') return;
        var ahora = Date.now();
        if (ahora - ultimaConsulta < 2 * 60 * 1000) return;
        ultimaConsulta = ahora;

        // Si quedó una esperando mientras la app estaba afuera, se aplica en
        // este mismo momento: la persona acaba de abrirla y no está en medio
        // de nada. Es el instante más seguro para recargar.
        if (registration.waiting) {
          aplicarAhora(registration.waiting);
          return;
        }
        registration.update().catch(function () {});
      });
    }).catch(function (err) {
      console.error('No se pudo registrar el service worker:', err);
    });
  });
})();
