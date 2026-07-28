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
      'position:fixed', 'left:0', 'right:0', 'bottom:0', 'z-index:2147483647',
      'display:flex', 'align-items:center', 'justify-content:center',
      'gap:16px', 'flex-wrap:wrap',
      'padding:12px 16px', 'background:#0B0F16', 'color:#fff',
      'border-top:1px solid rgba(255,255,255,.15)',
      'font:600 14px/1.4 system-ui,-apple-system,Segoe UI,Roboto,sans-serif',
      'box-shadow:0 -4px 20px rgba(0,0,0,.4)',
    ].join(';');

    var text = document.createElement('span');
    text.textContent = 'Hay una versión nueva disponible.';

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = 'Actualizar';
    btn.style.cssText = [
      'padding:8px 20px', 'border:0', 'border-radius:8px', 'cursor:pointer',
      'background:#fff', 'color:#0B0F16',
      'font:600 14px/1 system-ui,-apple-system,Segoe UI,Roboto,sans-serif',
    ].join(';');

    var later = document.createElement('button');
    later.type = 'button';
    later.textContent = 'Más tarde';
    later.style.cssText = [
      'padding:8px 12px', 'border:0', 'background:transparent',
      'color:rgba(255,255,255,.6)', 'cursor:pointer',
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

  function watchForUpdate(registration) {
    if (registration.waiting) {
      showUpdateBanner(registration.waiting);
    }

    registration.addEventListener('updatefound', function () {
      var installing = registration.installing;
      if (!installing) return;
      installing.addEventListener('statechange', function () {
        // 'installed' con un controller ya activo significa que hay una versión
        // nueva esperando. Sin controller es la primera instalación: nada que
        // avisar, el usuario ya está viendo la versión más reciente.
        if (installing.state === 'installed' && navigator.serviceWorker.controller) {
          showUpdateBanner(installing);
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

  var refreshing = false;
  navigator.serviceWorker.addEventListener('controllerchange', function () {
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
    }).catch(function (err) {
      console.error('No se pudo registrar el service worker:', err);
    });
  });
})();
