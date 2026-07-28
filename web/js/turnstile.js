/* Cloudflare Turnstile — captcha para registro, login y recuperación de clave.
 *
 * Vive en JS y no en Dart porque Turnstile se dibuja en un iframe propio, y
 * Flutter pinta sobre un canvas: no hay forma de meter un iframe ajeno dentro
 * del árbol de widgets sin platform views. El widget se monta en un contenedor
 * HTML por encima del canvas y Dart solo le pide el token.
 *
 * Modo `interaction-only`: en la mayoría de las visitas Turnstile resuelve solo
 * y nunca se ve nada. El contenedor únicamente aparece cuando Cloudflare decide
 * que hace falta interacción humana.
 *
 * Contrato con Dart: `window.imagineCaptcha.token()` devuelve una Promise que
 * resuelve un string, o `null` si el captcha no está disponible. Nunca rechaza
 * y nunca queda colgada — un login que se cuelga para siempre es peor que uno
 * que falla con un mensaje.
 */
(function () {
  'use strict';

  var SITE_KEY = '0x4AAAAAAD_-symeaYxV266Y';

  // Si Cloudflare no contesta en este tiempo, seguimos sin token. Generoso a
  // propósito: en una conexión mala de un evento, abortar temprano deja gente
  // afuera por algo que habría funcionado con dos segundos más.
  var ESPERA_MS = 20000;

  var widgetId = null;
  var apiLista = false;
  var tokenDisponible = null;
  var esperando = []; // resolvers a los que hay que entregarles el próximo token

  function contenedor() {
    return document.getElementById('turnstile-container');
  }

  /** Entrega el token a todos los que estén esperando y limpia la cola. */
  function repartir(token) {
    var cola = esperando;
    esperando = [];
    for (var i = 0; i < cola.length; i++) {
      try {
        cola[i](token);
      } catch (e) {
        console.warn('[turnstile] error entregando token', e);
      }
    }
  }

  function alResolver(token) {
    if (esperando.length > 0) {
      // Hay alguien esperando: se lo damos directo. No lo guardamos, porque un
      // token de Turnstile es de un solo uso.
      repartir(token);
    } else {
      tokenDisponible = token;
    }
  }

  function alFallar(codigo) {
    console.warn('[turnstile] fallo del widget:', codigo);
    tokenDisponible = null;
    // A quien esté esperando le decimos que no hay token, en vez de dejarlo
    // colgado hasta el timeout.
    repartir(null);
  }

  function alExpirar() {
    // Los tokens caducan a los ~5 minutos. Si el usuario dejó el login abierto
    // sin enviarlo, el que teníamos guardado ya no sirve.
    //
    // NO se pide otro acá: reiniciar el widget puede abrir un desafío visible,
    // y hacerlo por un temporizador significa que le aparece a alguien que está
    // haciendo cualquier otra cosa. El próximo `token()` lo pedirá.
    tokenDisponible = null;
  }

  function mostrar() {
    var c = contenedor();
    if (c) c.classList.add('visible');
  }

  function ocultar() {
    var c = contenedor();
    if (c) c.classList.remove('visible');
  }

  /** Reinicia el widget para que produzca un token nuevo. */
  function pedirOtro() {
    if (!apiLista || widgetId === null) return;
    try {
      window.turnstile.reset(widgetId);
    } catch (e) {
      console.warn('[turnstile] no se pudo reiniciar', e);
    }
  }

  function montar() {
    var c = contenedor();
    if (!c || !window.turnstile) return;
    try {
      widgetId = window.turnstile.render(c, {
        sitekey: SITE_KEY,
        appearance: 'interaction-only',
        callback: alResolver,
        'error-callback': alFallar,
        'expired-callback': alExpirar,
        'before-interactive-callback': mostrar,
        'after-interactive-callback': ocultar,
      });
      apiLista = true;
    } catch (e) {
      console.warn('[turnstile] no se pudo montar el widget', e);
      alFallar('render-failed');
    }
  }

  // La API de Cloudflare llama a esta función global cuando terminó de cargar.
  // El nombre está acoplado al parámetro `onload` de la URL del script.
  window.imagineTurnstileListo = montar;

  window.imagineCaptcha = {
    /**
     * Token de un solo uso para adjuntar a la próxima llamada de auth.
     * Resuelve `null` si el captcha no está disponible.
     */
    token: function () {
      return new Promise(function (resolve) {
        // Caso normal: el widget ya resolvió al cargar la página y el token
        // está esperando. Se consume y listo.
        //
        // NO se pide el siguiente acá. Adelantarse parecía una mejora —tener
        // uno listo hace más rápido el próximo envío— pero ese reinicio puede
        // abrir un desafío visible, y como ocurre en segundo plano le aparece
        // al usuario en un momento cualquiera: después de entrar, ya navegando
        // el panel. Pedirlo solo cuando hace falta hace que el desafío, si
        // aparece, aparezca junto al botón que lo provocó.
        if (tokenDisponible) {
          var t = tokenDisponible;
          tokenDisponible = null;
          resolve(t);
          return;
        }

        var resuelto = false;
        var temporizador = setTimeout(function () {
          if (resuelto) return;
          resuelto = true;
          var i = esperando.indexOf(entregar);
          if (i >= 0) esperando.splice(i, 1);
          console.warn('[turnstile] sin token tras ' + ESPERA_MS + 'ms');
          resolve(null);
        }, ESPERA_MS);

        function entregar(token) {
          if (resuelto) return;
          resuelto = true;
          clearTimeout(temporizador);
          resolve(token);
        }

        esperando.push(entregar);

        if (apiLista) {
          pedirOtro();
        }
        // Si la API todavía no cargó, no hacemos nada: cuando `montar()` corra,
        // el widget resuelve solo y `alResolver` despacha la cola.
      });
    },
  };

  // Carga del script de Cloudflare. `render=explicit` evita que busque widgets
  // por clase en el DOM — el canvas de Flutter no tiene ninguno.
  var s = document.createElement('script');
  s.src =
    'https://challenges.cloudflare.com/turnstile/v0/api.js' +
    '?onload=imagineTurnstileListo&render=explicit';
  s.async = true;
  s.defer = true;
  s.onerror = function () {
    console.warn('[turnstile] no se pudo cargar la API de Cloudflare');
    alFallar('script-load-failed');
  };
  document.head.appendChild(s);
})();
