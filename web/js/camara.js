/* Mejora la cámara del escáner.
 *
 * mobile_scanner 7.2.0 pide a getUserMedia únicamente `facingMode`: ni
 * resolución ni modo de enfoque. Su opción `cameraResolution` existe en la API
 * del controlador pero la implementación web la ignora — verificado leyendo
 * `mobile_scanner_web.dart`, que construye el constraint con `facingMode` y
 * nada más.
 *
 * Consecuencia en la puerta: el navegador entrega el modo por defecto, que en
 * muchos Android es 640x480 con enfoque fijo. Un QR impreso a media cuadra de
 * distancia entra borroso y de baja resolución, y no se lee.
 *
 * Acá se toma la pista de video que ya creó el plugin y se le aplican mejores
 * restricciones por encima. No se toca el plugin: cuando lo arreglen río
 * arriba, esto queda redundante pero inofensivo.
 */
(function () {
  'use strict';

  var INTENTOS = 20;      // ~6 s esperando a que el plugin monte el <video>
  var ESPERA_MS = 300;

  function pistaDeVideo() {
    var videos = document.getElementsByTagName('video');
    for (var i = 0; i < videos.length; i++) {
      var flujo = videos[i].srcObject;
      if (!flujo || !flujo.getVideoTracks) continue;
      var pistas = flujo.getVideoTracks();
      if (pistas && pistas.length) return pistas[0];
    }
    return null;
  }

  /**
   * Aplica las restricciones de a una y no todas juntas.
   *
   * `applyConstraints` es todo o nada: si el navegador no soporta UNA de las
   * propiedades, rechaza el lote completo y no se aplica ninguna. Pidiendo por
   * separado, un teléfono que no sabe enfocar igual sube la resolución.
   */
  function aplicar(pista) {
    var capacidades = {};
    try {
      capacidades = pista.getCapabilities ? pista.getCapabilities() : {};
    } catch (e) {
      capacidades = {};
    }

    var lotes = [];

    // Resolución. Se pide como `ideal` y no `exact`: con `exact`, una cámara
    // que no llega a 1280 falla en vez de dar lo mejor que tenga.
    lotes.push({
      width: { ideal: 1280 },
      height: { ideal: 720 },
    });

    // Enfoque continuo. Es lo que corrige el foco fijo.
    if (capacidades.focusMode && capacidades.focusMode.indexOf('continuous') >= 0) {
      lotes.push({ focusMode: 'continuous' });
      lotes.push({ advanced: [{ focusMode: 'continuous' }] });
    } else {
      // Algunos navegadores no declaran la capacidad pero igual la aceptan.
      lotes.push({ advanced: [{ focusMode: 'continuous' }] });
    }

    // Distancia de enfoque al mínimo: un QR se lee de cerca, y dejar que la
    // cámara enfoque al infinito es lo que produce la imagen borrosa.
    if (capacidades.focusDistance && typeof capacidades.focusDistance.min === 'number') {
      lotes.push({ advanced: [{ focusDistance: capacidades.focusDistance.min }] });
    }

    var aplicadas = [];
    var cadena = Promise.resolve();
    lotes.forEach(function (lote, i) {
      cadena = cadena
        .then(function () { return pista.applyConstraints(lote); })
        .then(function () { aplicadas.push(i); })
        .catch(function () { /* esta no la soporta; seguimos con la siguiente */ });
    });

    return cadena.then(function () {
      var s = {};
      try { s = pista.getSettings ? pista.getSettings() : {}; } catch (e) { /* ignorar */ }
      console.info('[camara] ' + aplicadas.length + '/' + lotes.length +
        ' restricciones aplicadas — ' + (s.width || '?') + 'x' + (s.height || '?') +
        ', enfoque: ' + (s.focusMode || 'desconocido'));
      return s;
    });
  }

  window.imagineCamara = {
    /**
     * Espera a que el plugin monte su <video> y mejora la pista.
     *
     * Lo llama la pantalla del escáner al abrirse. Reintenta porque el
     * elemento aparece de forma asíncrona, después de que el usuario concede
     * el permiso de cámara.
     */
    mejorar: function () {
      var restantes = INTENTOS;
      return new Promise(function (resolve) {
        (function intentar() {
          var pista = pistaDeVideo();
          if (pista) {
            aplicar(pista).then(resolve);
            return;
          }
          if (--restantes <= 0) {
            console.warn('[camara] no apareció ninguna pista de video');
            resolve(null);
            return;
          }
          setTimeout(intentar, ESPERA_MS);
        })();
      });
    },
  };
})();
