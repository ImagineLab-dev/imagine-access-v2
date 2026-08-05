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
 * está respaldado por el motor de códigos del sistema (el mismo de la cámara
 * nativa), acelerado por hardware. Es entre uno y dos órdenes de magnitud más
 * rápido que el port JS y mucho más tolerante al ángulo, al desenfoque y a la
 * poca luz.
 *
 * Este módulo NO reemplaza a mobile_scanner: se monta sobre el MISMO elemento
 * <video> que el plugin ya creó y decodifica en paralelo. Si el navegador no
 * tiene `BarcodeDetector` —Safari en iPhone, hoy no lo tiene— este módulo se
 * apaga solo y queda funcionando ZXing como hasta ahora. Nunca hay una pantalla
 * sin escáner.
 *
 * TRES DECISIONES QUE HACEN LA DIFERENCIA
 *
 * 1. Se decodifica SOLO el cuadrado central, no la imagen entera. Es donde la
 *    mira le pide a la persona que ponga el código. Recortar baja los píxeles a
 *    analizar a menos de la mitad y, sobre todo, saca del cuadro la ropa, el
 *    piso y las luces del local, que es de donde salen los cuadros perdidos.
 *
 * 2. Se usa `requestVideoFrameCallback` cuando existe: entrega un aviso por
 *    cuadro REAL de la cámara, en vez de adivinar con un temporizador. Sin él,
 *    o se decodifica el mismo cuadro dos veces o se saltean cuadros buenos.
 *
 * 3. Hay un techo de cuadros por segundo. Decodificar a 60 fps no lee más
 *    rápido —la cámara no entrega tanto código nuevo— y en cambio calienta el
 *    teléfono y le come la batería a un dispositivo que pasa toda la noche
 *    enchufado a la puerta.
 */
(function () {
  'use strict';

  var MAX_FPS = 15;
  var MIN_MS_ENTRE_CUADROS = 1000 / MAX_FPS;

  /* Proporción del lado más corto del video que se recorta.
   * 0.7 deja un margen cómodo alrededor de la mira: si se recortara justo, un
   * código apenas fuera del encuadre se perdería aunque la persona lo vea
   * dentro del marco. */
  var RECORTE = 0.7;

  var detector = null;
  var lienzo = null;
  var contexto = null;
  var corriendo = false;
  var alEncontrar = null;
  var ultimoCuadro = 0;
  var handle = null;
  var videoActual = null;

  /* Telemetría, para poder responder "¿está leyendo?" con un número y no con
   * una sensación. La lee la app y la muestra en el panel de diagnóstico. */
  var stats = { motor: 'ninguno', cuadros: 0, lecturas: 0, ultimoMs: 0 };

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
      // `willReadFrequently` evita que el navegador suba el lienzo a la GPU:
      // acá se lee en cada cuadro, y el viaje de vuelta desde la GPU es más
      // caro que dibujar en memoria.
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

  function siguienteCuadro(video, tarea) {
    if (video.requestVideoFrameCallback) {
      handle = video.requestVideoFrameCallback(tarea);
    } else {
      handle = requestAnimationFrame(tarea);
    }
  }

  function bucle() {
    if (!corriendo) return;

    var video = videoActual && videoActual.videoWidth > 0 ? videoActual : pistaDeVideo();
    if (!video) {
      // Todavía no hay video: se reintenta sin quemar CPU.
      handle = setTimeout(bucle, 250);
      return;
    }
    videoActual = video;

    var ahora = performance.now();
    if (ahora - ultimoCuadro < MIN_MS_ENTRE_CUADROS) {
      siguienteCuadro(video, bucle);
      return;
    }
    ultimoCuadro = ahora;

    var recorte = recortar(video);
    if (!recorte) {
      siguienteCuadro(video, bucle);
      return;
    }

    detector.detect(recorte).then(function (codigos) {
      stats.cuadros++;
      stats.ultimoMs = Math.round(performance.now() - ahora);
      if (corriendo && codigos && codigos.length) {
        var valor = (codigos[0].rawValue || '').trim();
        if (valor && alEncontrar) {
          stats.lecturas++;
          alEncontrar(valor);
        }
      }
      if (corriendo) siguienteCuadro(video, bucle);
    }).catch(function () {
      // Un cuadro que el detector no pudo procesar no es motivo para apagar el
      // escáner: se sigue con el siguiente.
      if (corriendo) siguienteCuadro(video, bucle);
    });
  }

  window.imagineLector = {
    /** ¿Este navegador tiene decodificador nativo? */
    disponible: function () {
      return soportado();
    },

    /** Arranca el lector rápido. Devuelve false si el navegador no lo soporta,
     *  y en ese caso la app sigue con ZXing sin cambiar nada. */
    iniciar: function (callback) {
      if (!soportado()) {
        stats.motor = 'zxing';
        return false;
      }
      if (corriendo) return true;

      try {
        detector = new window.BarcodeDetector({ formats: ['qr_code'] });
      } catch (e) {
        stats.motor = 'zxing';
        return false;
      }

      alEncontrar = callback;
      corriendo = true;
      stats.motor = 'nativo';
      stats.cuadros = 0;
      stats.lecturas = 0;
      ultimoCuadro = 0;
      videoActual = null;
      bucle();
      return true;
    },

    detener: function () {
      corriendo = false;
      alEncontrar = null;
      videoActual = null;
      if (handle != null) {
        // No se sabe con cuál de los tres se programó, así que se cancelan los
        // tres. Cancelar un handle que no corresponde es inofensivo.
        try { clearTimeout(handle); } catch (e) {}
        try { cancelAnimationFrame(handle); } catch (e) {}
        handle = null;
      }
    },

    /** Para el panel de diagnóstico del escáner. */
    estado: function () {
      return JSON.stringify(stats);
    },
  };
})();
