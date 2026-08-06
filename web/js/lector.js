/* Lector de QR rápido, sobre el decodificador NATIVO del navegador.
 *
 * EL PROBLEMA
 *
 * mobile_scanner 7.2.0 decodifica en web con ZXing-JS: un port a JavaScript que
 * corre en el hilo principal y analiza el cuadro ENTERO por software. En la
 * puerta eso se nota — hay que sostener el teléfono quieto un par de segundos, y
 * con poca luz o el código apenas torcido directamente no engancha.
 *
 * LA SOLUCIÓN
 *
 * Los navegadores basados en Chromium traen `BarcodeDetector`, que en Android
 * está respaldado por el motor de códigos del sistema, acelerado por hardware.
 * Es mucho más rápido que el port JS y más tolerante al ángulo, al desenfoque y
 * a la poca luz.
 *
 * Este módulo NO reemplaza a mobile_scanner: se monta sobre el MISMO elemento
 * <video> que el plugin ya creó y decodifica en paralelo. Donde no hay
 * `BarcodeDetector` —Safari en iPhone— se apaga solo y queda ZXing funcionando.
 * Nunca hay una pantalla sin escáner.
 *
 * TRES DECISIONES SOBRE EL DECODIFICADO
 *
 * 1. Se decodifica SOLO el cuadrado central. Es donde la mira pide poner el
 *    código. Recortar baja los píxeles a analizar a menos de la mitad y saca del
 *    cuadro la ropa, el piso y las luces del local, que es de donde salen los
 *    cuadros perdidos.
 *
 * 2. `requestVideoFrameCallback` cuando existe: un aviso por cuadro REAL de la
 *    cámara, en vez de adivinar con un temporizador.
 *
 * 3. Techo de cuadros por segundo. Decodificar a 60 fps no lee más rápido y le
 *    come la batería a un equipo que pasa la noche enchufado a la puerta.
 *
 * ---------------------------------------------------------------------------
 * POR QUÉ HAY SESIONES Y UN VIGÍA
 *
 * La primera versión de esto tenía dos fallas que se combinaban para dejar el
 * escáner muerto hasta cerrar y reabrir la app:
 *
 *   a) `iniciar()` devolvía temprano si ya estaba corriendo, SIN registrar el
 *      callback nuevo. La pantalla nueva creía estar escuchando y en realidad
 *      los códigos seguían yendo al callback de una pantalla ya destruida, que
 *      los descartaba por `!mounted`.
 *
 *   b) `detener()` no tenía dueño: cualquiera podía apagarlo. Y al navegar
 *      entre pantallas, Flutter monta la nueva ANTES de destruir la vieja, así
 *      que el `dispose` de la vieja apagaba el lector que la nueva acababa de
 *      encender.
 *
 * De ahí las sesiones: `iniciar()` devuelve un número y `detener(n)` solo apaga
 * si ese número sigue siendo el vigente. Un `dispose` tardío ya no puede matar
 * una sesión más nueva.
 *
 * Y de ahí el vigía: aunque la lógica quede bien, el bucle puede morir por
 * fuera —el plugin reemplaza el <video>, una promesa queda colgada, el sistema
 * suspende la pestaña—. Un escáner en una puerta no puede depender de que
 * alguien se dé cuenta y reinicie: si deja de procesar cuadros, se levanta solo.
 */
(function () {
  'use strict';

  var MAX_FPS = 15;
  var MIN_MS_ENTRE_CUADROS = 1000 / MAX_FPS;

  /* Proporción del lado más corto del video que se recorta. 0.7 deja margen
   * alrededor de la mira: recortar justo perdería un código que la persona ve
   * dentro del marco. */
  var RECORTE = 0.7;

  /* Si pasa esto sin procesar un cuadro estando encendido, el bucle está roto y
   * el vigía lo reinicia. Dos segundos es holgado: a 15 fps deberían haber
   * pasado treinta. */
  var VIGIA_MS = 2000;

  var detector = null;
  var lienzo = null;
  var contexto = null;
  var corriendo = false;
  var alEncontrar = null;
  var ultimoCuadro = 0;
  var handle = null;
  var videoActual = null;
  var vigia = null;

  /* Identifica quién encendió el lector. Solo el dueño puede apagarlo. */
  var sesion = 0;

  var stats = {
    motor: 'ninguno',
    sesion: 0,
    cuadros: 0,
    lecturas: 0,
    ultimoMs: 0,
    reinicios: 0,
    /* Instante del último cuadro procesado. Con esto la app puede mostrar si
     * el lector está vivo, en vez de suponerlo. */
    ultimoCuadroEn: 0,
  };

  function soportado() {
    return typeof window.BarcodeDetector === 'function';
  }

  function pistaDeVideo() {
    var videos = document.getElementsByTagName('video');
    for (var i = 0; i < videos.length; i++) {
      if (videos[i].videoWidth > 0 && videos[i].readyState >= 2) return videos[i];
    }
    return null;
  }

  function recortar(video) {
    var lado = Math.floor(Math.min(video.videoWidth, video.videoHeight) * RECORTE);
    if (lado <= 0) return null;

    if (!lienzo) {
      lienzo = document.createElement('canvas');
      /* `willReadFrequently` evita que el navegador suba el lienzo a la GPU:
       * acá se lee en cada cuadro, y el viaje de vuelta es más caro que
       * dibujar en memoria. */
      contexto = lienzo.getContext('2d', { willReadFrequently: true });
    }
    if (lienzo.width !== lado) {
      lienzo.width = lado;
      lienzo.height = lado;
    }

    contexto.drawImage(
      video,
      Math.floor((video.videoWidth - lado) / 2),
      Math.floor((video.videoHeight - lado) / 2),
      lado, lado,
      0, 0, lado, lado
    );
    return lienzo;
  }

  function programar(video, tarea) {
    if (video && video.requestVideoFrameCallback) {
      handle = video.requestVideoFrameCallback(tarea);
    } else {
      handle = requestAnimationFrame(tarea);
    }
  }

  function cancelarProgramado() {
    if (handle == null) return;
    /* No se sabe con cuál de los tres se programó; cancelar el que no
     * corresponde es inofensivo. */
    try { clearTimeout(handle); } catch (e) {}
    try { cancelAnimationFrame(handle); } catch (e) {}
    handle = null;
  }

  function bucle() {
    if (!corriendo) return;

    var video = videoActual && videoActual.videoWidth > 0
      ? videoActual
      : pistaDeVideo();

    if (!video) {
      /* Todavía no hay video —el plugin no montó la cámara— se reintenta sin
       * quemar CPU. Esto cuenta como actividad para el vigía: el bucle está
       * vivo, solo que esperando. */
      stats.ultimoCuadroEn = Date.now();
      handle = setTimeout(bucle, 250);
      return;
    }
    videoActual = video;

    var ahora = performance.now();
    if (ahora - ultimoCuadro < MIN_MS_ENTRE_CUADROS) {
      programar(video, bucle);
      return;
    }
    ultimoCuadro = ahora;

    var recorte = recortar(video);
    if (!recorte) {
      programar(video, bucle);
      return;
    }

    detector.detect(recorte).then(function (codigos) {
      stats.cuadros++;
      stats.ultimoMs = Math.round(performance.now() - ahora);
      stats.ultimoCuadroEn = Date.now();

      if (corriendo && codigos && codigos.length) {
        var valor = (codigos[0].rawValue || '').trim();
        if (valor && alEncontrar) {
          stats.lecturas++;
          alEncontrar(valor);
        }
      }
      if (corriendo) programar(video, bucle);
    }).catch(function () {
      /* Un cuadro que el detector no pudo procesar no apaga el escáner. Se
       * marca actividad igual: el bucle sigue vivo. */
      stats.ultimoCuadroEn = Date.now();
      if (corriendo) programar(video, bucle);
    });
  }

  function arrancarVigia() {
    if (vigia != null) clearInterval(vigia);
    vigia = setInterval(function () {
      if (!corriendo) return;
      if (Date.now() - stats.ultimoCuadroEn < VIGIA_MS) return;

      /* El bucle dejó de procesar cuadros. Se lo levanta desde cero. */
      stats.reinicios++;
      stats.ultimoCuadroEn = Date.now();
      cancelarProgramado();
      videoActual = null;
      bucle();
    }, VIGIA_MS);
  }

  window.imagineLector = {
    /** ¿Este navegador trae decodificador nativo? */
    disponible: function () {
      return soportado();
    },

    /**
     * Enciende el lector y devuelve el número de sesión.
     *
     * Devuelve 0 si el navegador no lo soporta; ahí la app sigue con ZXing.
     * El número hay que guardarlo: es lo único que autoriza a apagarlo después.
     */
    iniciar: function (callback) {
      if (!soportado()) {
        stats.motor = 'zxing';
        return 0;
      }

      if (!detector) {
        try {
          detector = new window.BarcodeDetector({ formats: ['qr_code'] });
        } catch (e) {
          stats.motor = 'zxing';
          return 0;
        }
      }

      /* El callback se registra SIEMPRE, corra o no el bucle. Esta línea es la
       * que faltaba: sin ella, una pantalla nueva heredaba el callback de la
       * anterior —ya destruida— y los códigos se descartaban en silencio. */
      alEncontrar = callback;
      sesion++;
      stats.sesion = sesion;
      stats.motor = 'nativo';
      stats.ultimoCuadroEn = Date.now();

      if (!corriendo) {
        corriendo = true;
        stats.cuadros = 0;
        stats.lecturas = 0;
        ultimoCuadro = 0;
        videoActual = null;
        bucle();
      }
      arrancarVigia();
      return sesion;
    },

    /**
     * Apaga el lector, pero SOLO si quien pide es el dueño de la sesión actual.
     *
     * Al navegar entre pantallas, Flutter monta la nueva antes de destruir la
     * vieja. Sin esta comprobación, el `dispose` de la vieja apagaba el lector
     * que la nueva acababa de encender, y el escáner quedaba muerto hasta
     * recargar la app.
     */
    detener: function (id) {
      if (id && id !== sesion) return false;
      corriendo = false;
      alEncontrar = null;
      videoActual = null;
      cancelarProgramado();
      if (vigia != null) { clearInterval(vigia); vigia = null; }
      return true;
    },

    /** Telemetría, para poder responder "¿está leyendo?" con un número. */
    estado: function () {
      var desde = stats.ultimoCuadroEn ? Date.now() - stats.ultimoCuadroEn : -1;
      return JSON.stringify({
        motor: stats.motor,
        sesion: stats.sesion,
        cuadros: stats.cuadros,
        lecturas: stats.lecturas,
        ultimoMs: stats.ultimoMs,
        reinicios: stats.reinicios,
        /* Milisegundos desde el último cuadro. Si crece, está colgado. */
        inactivoMs: desde,
        vivo: corriendo && desde >= 0 && desde < VIGIA_MS,
      });
    },
  };
})();
