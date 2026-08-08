/**
 * Invitación a instalar la app en la pantalla de inicio.
 *
 * Hay dos caminos y no son intercambiables:
 *
 *  - Android / Chrome de escritorio disparan `beforeinstallprompt`, que se
 *    puede guardar y usar después para abrir el diálogo nativo de instalación.
 *
 *  - iOS NO lo dispara nunca, en NINGÚN navegador. Chrome, Edge y Firefox en
 *    iPhone son Safari por dentro (WebKit obligatorio), así que todos exigen el
 *    mismo gesto manual: Compartir → Añadir a pantalla de inicio. Por eso la
 *    detección es por sistema operativo y no por marca de navegador: mirar si
 *    "es Chrome" daría un falso positivo en iPhone y el usuario esperaría un
 *    botón que nunca va a aparecer.
 *
 * Instalar importa más que la comodidad: una PWA agregada a la pantalla de
 * inicio en iOS queda exenta del borrado de datos a los 7 días de inactividad
 * que Safari aplica a los sitios normales. Sin instalar, la cola de
 * validaciones offline puede desaparecer sola entre un evento y el siguiente.
 */
'use strict';

(function () {
  var CLAVE_DESCARTE = 'pwa-install-dismissed';
  var ID = 'pwa-install-banner';
  // Antes eran 14 días: un "Ahora no" dejaba la app sin ofrecerse dos semanas.
  // Para gente que DEBE instalarla (sirve offline en la puerta) eso es
  // demasiado. Se baja a 3, y además el ítem de Ajustes queda disponible
  // siempre que no esté instalada, como camino permanente.
  var DIAS_SILENCIO = 3;

  // --------------------------------------------------------------------------
  // Textos
  // --------------------------------------------------------------------------
  // Este archivo vive fuera de Flutter, así que no puede usar AppLocalizations.
  // Se resuelve el idioma con el del navegador, cayendo a español, que es el
  // idioma principal del negocio.
  var TEXTOS = {
    es: {
      titulo: 'Instalá Imagine Access',
      motivo: 'Funciona sin conexión y arranca más rápido.',
      instalar: 'Instalar',
      ahoraNo: 'Ahora no',
      // Se aclara "del navegador" a propósito: sin eso, mucha gente busca un
      // botón de compartir dentro de la app y no lo encuentra.
      iosPaso1: 'Tocá el botón Compartir del navegador',
      iosPaso2: 'y elegí «Añadir a pantalla de inicio».',
      compartir: 'Compartir',
      generico: 'Abrí el menú de tu navegador y elegí «Instalar app» o «Añadir a pantalla de inicio».',
    },
    en: {
      titulo: 'Install Imagine Access',
      motivo: 'Works offline and starts faster.',
      instalar: 'Install',
      ahoraNo: 'Not now',
      iosPaso1: "Tap your browser's Share button",
      iosPaso2: 'and choose "Add to Home Screen".',
      compartir: 'Share',
      generico: 'Open your browser menu and choose "Install app" or "Add to Home Screen".',
    },
    pt: {
      titulo: 'Instale o Imagine Access',
      motivo: 'Funciona sem conexão e abre mais rápido.',
      instalar: 'Instalar',
      ahoraNo: 'Agora não',
      iosPaso1: 'Toque no botão Compartilhar do navegador',
      iosPaso2: 'e escolha "Adicionar à Tela de Início".',
      compartir: 'Compartilhar',
      generico: 'Abra o menu do navegador e escolha «Instalar app» ou «Adicionar à Tela de Início».',
    },
  };

  function textos() {
    var idioma = (navigator.language || 'es').slice(0, 2).toLowerCase();
    return TEXTOS[idioma] || TEXTOS.es;
  }

  // --------------------------------------------------------------------------
  // Detección
  // --------------------------------------------------------------------------
  function esIOS() {
    var ua = navigator.userAgent;
    if (/iphone|ipod|ipad/i.test(ua)) return true;
    // iPadOS 13+ se presenta como Mac. La pantalla táctil lo delata.
    return navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
  }

  function yaInstalada() {
    // `standalone` es propio de iOS; `display-mode` cubre al resto.
    return window.navigator.standalone === true ||
           window.matchMedia('(display-mode: standalone)').matches ||
           window.matchMedia('(display-mode: minimal-ui)').matches;
  }

  function silenciado() {
    try {
      var hasta = parseInt(localStorage.getItem(CLAVE_DESCARTE) || '0', 10);
      return hasta > Date.now();
    } catch (_) {
      return false;
    }
  }

  function silenciar() {
    try {
      localStorage.setItem(
        CLAVE_DESCARTE,
        String(Date.now() + DIAS_SILENCIO * 24 * 60 * 60 * 1000),
      );
    } catch (_) { /* modo privado: se vuelve a ofrecer, es aceptable */ }
  }

  // --------------------------------------------------------------------------
  // Interfaz
  // --------------------------------------------------------------------------
  function crearBanner() {
    var caja = document.createElement('div');
    caja.id = ID;
    caja.setAttribute('role', 'dialog');
    caja.style.cssText = [
      'position:fixed', 'left:12px', 'right:12px', 'bottom:12px',
      'z-index:2147483646', 'max-width:520px', 'margin:0 auto',
      'padding:16px 18px', 'border-radius:14px',
      'background:#141416', 'color:#fff',
      'border:1px solid rgba(255,255,255,.12)',
      'border-top:3px solid #AED500',
      'box-shadow:0 12px 40px rgba(0,0,0,.55)',
      'font:400 14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif',
      'animation:pwa-install-in 260ms ease-out',
    ].join(';');

    var estilo = document.createElement('style');
    estilo.textContent =
      '@keyframes pwa-install-in{from{opacity:0;transform:translateY(16px)}' +
      'to{opacity:1;transform:none}}' +
      '@media (prefers-reduced-motion: reduce){#' + ID + '{animation:none}}';
    caja.appendChild(estilo);

    return caja;
  }

  function encabezado(t) {
    var fila = document.createElement('div');
    fila.style.cssText = 'display:flex;align-items:center;gap:12px;margin-bottom:10px';

    var icono = document.createElement('img');
    icono.src = 'icons/Icon-192.png';
    icono.alt = '';
    icono.style.cssText = 'width:40px;height:40px;border-radius:10px;flex:0 0 auto';

    var textoCaja = document.createElement('div');
    var titulo = document.createElement('div');
    titulo.textContent = t.titulo;
    titulo.style.cssText = 'font-weight:600;font-size:15px';
    var motivo = document.createElement('div');
    motivo.textContent = t.motivo;
    motivo.style.cssText = 'color:rgba(255,255,255,.65);font-size:13px;margin-top:2px';

    textoCaja.appendChild(titulo);
    textoCaja.appendChild(motivo);
    fila.appendChild(icono);
    fila.appendChild(textoCaja);
    return fila;
  }

  function botonSecundario(t, alCerrar) {
    var b = document.createElement('button');
    b.type = 'button';
    b.textContent = t.ahoraNo;
    b.style.cssText = [
      'padding:10px 14px', 'border:0', 'background:transparent', 'cursor:pointer',
      'color:rgba(255,255,255,.6)', 'border-radius:10px',
      'font:400 13px/1 system-ui,-apple-system,Segoe UI,Roboto,sans-serif',
    ].join(';');
    b.addEventListener('click', alCerrar);
    return b;
  }

  function cerrar() {
    var el = document.getElementById(ID);
    if (el && el.parentNode) el.parentNode.removeChild(el);
  }

  // --------------------------------------------------------------------------
  // Camino A: Android y escritorio, con diálogo nativo
  // --------------------------------------------------------------------------
  var eventoGuardado = null;

  window.addEventListener('beforeinstallprompt', function (e) {
    // Sin esto el navegador muestra su propia barra, que no explica por qué
    // conviene instalar ni respeta el diseño de la app.
    e.preventDefault();
    eventoGuardado = e;
    if (!silenciado() && !yaInstalada()) mostrarNativo();
  });

  function mostrarNativo() {
    if (document.getElementById(ID)) return;
    var t = textos();
    var caja = crearBanner();
    caja.appendChild(encabezado(t));

    var acciones = document.createElement('div');
    acciones.style.cssText = 'display:flex;gap:8px;justify-content:flex-end;align-items:center';

    var instalar = document.createElement('button');
    instalar.type = 'button';
    instalar.textContent = t.instalar;
    instalar.style.cssText = [
      'padding:10px 22px', 'border:0', 'border-radius:10px', 'cursor:pointer',
      'background:#AED500', 'color:#0A0A0B',
      'font:600 14px/1 system-ui,-apple-system,Segoe UI,Roboto,sans-serif',
    ].join(';');

    instalar.addEventListener('click', function () {
      cerrar();
      if (!eventoGuardado) return;
      eventoGuardado.prompt();
      eventoGuardado.userChoice.then(function (r) {
        // Si lo rechazó, no insistir enseguida.
        if (r && r.outcome !== 'accepted') silenciar();
        eventoGuardado = null;
      });
    });

    acciones.appendChild(botonSecundario(t, function () { silenciar(); cerrar(); }));
    acciones.appendChild(instalar);
    caja.appendChild(acciones);
    document.body.appendChild(caja);
  }

  // --------------------------------------------------------------------------
  // Camino B: iOS, con instrucciones
  // --------------------------------------------------------------------------
  function mostrarInstruccionesIOS() {
    if (document.getElementById(ID)) return;
    var t = textos();
    var caja = crearBanner();
    caja.appendChild(encabezado(t));

    var pasos = document.createElement('div');
    pasos.style.cssText =
      'display:flex;align-items:center;flex-wrap:wrap;gap:6px;' +
      'padding:10px 12px;border-radius:10px;background:rgba(255,255,255,.06);' +
      'color:rgba(255,255,255,.85);font-size:13px';

    var antes = document.createElement('span');
    antes.textContent = t.iosPaso1;

    // Ícono de compartir de iOS dibujado en SVG: usar un emoji da resultados
    // distintos según la versión y no se parece al botón real.
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('width', '17');
    svg.setAttribute('height', '17');
    svg.setAttribute('aria-label', t.compartir);
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', '#AED500');
    svg.setAttribute('stroke-width', '1.8');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    svg.style.cssText = 'vertical-align:-3px;flex:0 0 auto';
    svg.innerHTML =
      '<path d="M12 15V3"/><path d="m8 7 4-4 4 4"/>' +
      '<path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/>';

    var despues = document.createElement('span');
    despues.textContent = t.iosPaso2;

    pasos.appendChild(antes);
    pasos.appendChild(svg);
    pasos.appendChild(despues);
    caja.appendChild(pasos);

    var acciones = document.createElement('div');
    acciones.style.cssText = 'display:flex;justify-content:flex-end;margin-top:8px';
    acciones.appendChild(botonSecundario(t, function () { silenciar(); cerrar(); }));
    caja.appendChild(acciones);

    document.body.appendChild(caja);
  }

  // --------------------------------------------------------------------------
  // Camino C: cualquier otro navegador, con instrucciones genéricas
  // --------------------------------------------------------------------------
  // Firefox y Safari de escritorio NUNCA disparan `beforeinstallprompt`, y en
  // Chromium a veces tarda o no llega. Sin este camino, esos navegadores no
  // mostraban NADA: la opción de instalar quedaba invisible pese a no estar
  // instalada. Acá siempre hay algo que mostrar.
  function mostrarInstruccionesGenericas() {
    if (document.getElementById(ID)) return;
    var t = textos();
    var caja = crearBanner();
    caja.appendChild(encabezado(t));

    var pasos = document.createElement('div');
    pasos.style.cssText =
      'padding:10px 12px;border-radius:10px;background:rgba(255,255,255,.06);' +
      'color:rgba(255,255,255,.85);font-size:13px;line-height:1.5';
    pasos.textContent = t.generico;
    caja.appendChild(pasos);

    var acciones = document.createElement('div');
    acciones.style.cssText = 'display:flex;justify-content:flex-end;margin-top:8px';
    acciones.appendChild(botonSecundario(t, function () { silenciar(); cerrar(); }));
    caja.appendChild(acciones);

    document.body.appendChild(caja);
  }

  // --------------------------------------------------------------------------
  // Arranque
  // --------------------------------------------------------------------------
  window.addEventListener('appinstalled', function () {
    silenciar();
    cerrar();
  });

  window.addEventListener('load', function () {
    if (yaInstalada() || silenciado()) return;

    // En iOS se muestra con retraso: el aviso pisando la carga inicial es
    // molesto, y conviene que el usuario vea primero de qué se trata la app.
    if (esIOS()) {
      setTimeout(mostrarInstruccionesIOS, 4000);
      return;
    }

    // En el resto se espera a `beforeinstallprompt`. Si no llegó en unos
    // segundos —Firefox y Safari de escritorio no lo disparan nunca—, se
    // muestra el banner nativo (si el evento sí apareció) o las instrucciones
    // genéricas. Así la opción NUNCA queda invisible en un dispositivo sin
    // instalar, sea cual sea el navegador.
    setTimeout(function () {
      if (yaInstalada() || silenciado() || document.getElementById(ID)) return;
      if (eventoGuardado) mostrarNativo();
      else mostrarInstruccionesGenericas();
    }, 4500);
  });

  // --------------------------------------------------------------------------
  // API para la app
  // --------------------------------------------------------------------------
  //
  // Hasta acá instalar dependía SOLO del aviso automático. Y ese aviso, si
  // alguien lo cerraba una vez, se silenciaba catorce días — con lo cual la
  // app quedaba sin ninguna forma de instalarse durante dos semanas, y la
  // persona sin manera de saber que existía la opción.
  //
  // Con esto la configuración puede ofrecerlo siempre: el aviso es el empujón,
  // la configuración es el camino permanente.
  window.imagineInstalar = {
    /** Estado, en JSON, para que la app decida qué mostrar. */
    estado: function () {
      return JSON.stringify({
        instalada: yaInstalada(),
        silenciada: silenciado(),
        // En Android y escritorio hace falta el evento del navegador; sin él no
        // se puede abrir el diálogo por más que se quiera.
        listo: !!eventoGuardado,
        ios: esIOS(),
      });
    },

    /**
     * Ofrece instalar. Devuelve qué pasó, para que la app pueda explicarlo:
     *
     *   'instalada'  ya está instalada, no hay nada que hacer
     *   'pedido'     se abrió el diálogo del navegador
     *   'ios'        se mostraron las instrucciones manuales de iPhone
     *   'no-listo'   el navegador todavía no ofreció instalar
     */
    instalar: function () {
      if (yaInstalada()) return 'instalada';

      // Pedirlo a mano borra el silencio: si alguien entra a buscarlo, es que
      // lo quiere.
      try { localStorage.removeItem(CLAVE_DESCARTE); } catch (_) {}

      if (eventoGuardado) {
        eventoGuardado.prompt();
        eventoGuardado = null;
        return 'pedido';
      }
      if (esIOS()) {
        mostrarInstruccionesIOS();
        return 'ios';
      }
      // Cualquier otro navegador: instrucciones genéricas. Antes devolvía
      // 'no-listo' y no mostraba nada, dejando al usuario sin ninguna salida.
      mostrarInstruccionesGenericas();
      return 'instrucciones';
    },
  };
})();
