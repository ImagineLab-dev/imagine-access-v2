import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/platform/camara.dart';
import '../../../core/platform/lector.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/veredicto_acceso.dart';
import '../data/scanner_repository.dart';
import '../../events/presentation/event_state.dart';
import '../../../core/utils/device_id_service.dart';
import '../../../core/ui/loading_overlay.dart';
import 'package:imagine_access/features/tickets/presentation/ticket_list_screen.dart';
import 'package:imagine_access/features/dashboard/data/dashboard_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/offline/offline_queue_service.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  late MobileScannerController _cameraController;
  bool _isProcessing = false;

  /// Instante en que el escáner quedó listo para leer el código siguiente.
  /// Es el punto cero de la medición: lo que se mide es lo que espera la
  /// persona parada en la puerta, no el tiempo interno del decodificador.
  DateTime? _detectionWindowStart;

  /// Latencias medidas en esta sesión, en milisegundos.
  final List<int> _detectionLatencies = <int>[];

  /// Número de sesión del lector nativo, o 0 si no hay.
  ///
  /// **Hay que guardarlo.** Es lo único que autoriza a apagarlo al destruir esta
  /// pantalla. Sin esto, `dispose` apagaba el lector que la pantalla SIGUIENTE
  /// acababa de encender —Flutter monta la nueva antes de destruir la vieja— y
  /// el escáner quedaba muerto hasta cerrar y reabrir la app.
  int _sesionLector = 0;

  /// Telemetría del lector, refrescada una vez por segundo para el testigo.
  Map<String, dynamic> _estadoLector = const {};
  Timer? _relojTestigo;

  /// ¿El cartel del veredicto está REALMENTE en pantalla?
  ///
  /// No alcanza con saber que hubo un resultado: desde que el cartel se
  /// presenta como diálogo, "hubo respuesta" y "hay algo que el operario puede
  /// tocar" dejaron de ser lo mismo. El vigía antitrabas necesita lo segundo,
  /// así que esto se marca dentro del constructor de la ruta —cuando el
  /// diálogo realmente se construyó— y no al pedirlo.
  bool _veredictoEnPantalla = false;

  /// Instante en que el escáner se marcó como ocupado.
  ///
  /// Existe para el vigía: un escaneo tarda menos de dos segundos, así que si
  /// sigue ocupado mucho después es que se colgó y hay que liberarlo.
  DateTime? _ocupadoDesde;

  /// Cuánto se tolera un escáner ocupado antes de liberarlo por la fuerza.
  ///
  /// Generoso a propósito: una validación con la red lenta puede tardar. Pero
  /// pasado esto ya no hay explicación honesta, y un escáner trabado en la
  /// puerta es peor que uno que reintenta.
  static const _toleranciaOcupado = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      // Solo QR. Vacío significa "buscá los quince formatos de código de barras
      // en cada cuadro", y en web eso lo resuelve ZXing por software: el
      // trabajo por cuadro se multiplica y la lectura se vuelve lenta e
      // intermitente justo cuando hay una fila esperando en la puerta.
      formats: const [BarcodeFormat.qrCode],
      // La implementación web del plugin ignora esta opción —construye el
      // constraint solo con facingMode— pero queda correcta para el día que se
      // compile a móvil. En web la resolución la sube `mejorarCamara()`.
      cameraResolution: const Size(1280, 720),
    );
    WidgetsBinding.instance.addObserver(this);
    _detectionWindowStart = DateTime.now();

    // El plugin pide la cámara sin resolución ni modo de enfoque, así que el
    // navegador entrega su modo por defecto: en muchos Android, 640x480 con
    // foco fijo. Un QR impreso entra borroso y no se lee. Esto ajusta la pista
    // de video una vez que el plugin la creó.
    _arrancarTestigo();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // El lector nativo arranca PRIMERO y no espera a `mejorarCamara()`.
      //
      // Mejorar la cámara reintenta hasta seis segundos si el plugin todavía no
      // montó el video. Encadenarlo antes del lector significaba que en el peor
      // caso el escáner no empezaba a mirar hasta seis segundos después de
      // abrir la pantalla — con alguien esperando en la puerta. El lector tiene
      // su propia espera por el video, así que puede arrancar ya.
      _encenderLectorNativo();
      await mejorarCamara();
    });
  }

  /// Enciende el decodificador nativo del navegador, si lo hay.
  ///
  /// Corre EN PARALELO con ZXing sobre el mismo elemento de video: no le saca
  /// la cámara al plugin ni lo reemplaza. El primero que reconoce el código
  /// gana, y `_isProcessing` impide que se procese dos veces.
  ///
  /// En Chromium el nativo gana siempre por varios cuerpos —está respaldado por
  /// el motor de códigos del sistema—. En Safari de iPhone no existe y esto
  /// devuelve false, con lo que queda ZXing solo, igual que antes.
  void _encenderLectorNativo() {
    final sesion = iniciarLectorNativo((codigo) {
      if (!mounted || _isProcessing) return;
      final limpio = codigo.trim();
      if (limpio.isEmpty) return;

      _isProcessing = true;
      _ocupadoDesde = DateTime.now();
      _registrarLatencia();
      _processCode(limpio);
    });
    if (!mounted) {
      // La pantalla se fue mientras se encendía: se apaga lo que se prendió,
      // si no queda un lector corriendo sin nadie escuchándolo.
      detenerLectorNativo(sesion);
      return;
    }
    setState(() => _sesionLector = sesion);
  }

  /// Refresca el testigo. Una vez por segundo alcanza: es un indicador para
  /// mirar, no un gráfico.
  void _arrancarTestigo() {
    _relojTestigo?.cancel();
    _relojTestigo = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _vigilarTrabado();
      try {
        final crudo = estadoDelLector();
        final datos = jsonDecode(crudo);
        if (datos is Map<String, dynamic>) {
          setState(() => _estadoLector = datos);
        }
      } catch (_) {
        // Un estado que no se puede leer no debe romper el escáner.
      }
    });
  }

  /// Anota cuánto esperó la persona parada en la puerta desde que el escáner
  /// quedó listo hasta que reconoció su código.
  void _registrarLatencia() {
    final start = _detectionWindowStart;
    if (start == null) return;
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    _detectionLatencies.add(elapsed);
    _detectionWindowStart = null;
    if (kDebugMode) {
      dev.log('Detección en ${elapsed}ms (n=${_detectionLatencies.length})',
          name: 'ScannerLatency');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _relojTestigo?.cancel();
    // Con el número de sesión: si mientras tanto otra pantalla encendió el
    // lector, esto no la apaga.
    detenerLectorNativo(_sesionLector);
    _cameraController.dispose();
    super.dispose();
  }

  // Handle Lifecycle changes to stop/start camera
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // El lector nativo se maneja SIEMPRE, mire lo que mire la cámara.
    //
    // Antes esto arrancaba con `if (!_cameraController.value.isInitialized)
    // return;`, así que un cambio de app en el momento justo —cuando el plugin
    // todavía no había inicializado— se saltaba tanto el apagado como el
    // encendido. Se volvía sin lector y sin nada que lo volviera a prender.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      detenerLectorNativo(_sesionLector);
      _sesionLector = 0;
      if (_cameraController.value.isInitialized) _cameraController.stop();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (_cameraController.value.isInitialized) _cameraController.start();
      // Se vuelve a encender aunque ya creyéramos tenerlo: `iniciar()` registra
      // el callback de nuevo y devuelve una sesión nueva, así que reencender de
      // más es inofensivo y reencender de menos deja el escáner muerto.
      _encenderLectorNativo();

      // Volver de segundo plano es también el momento donde puede haber quedado
      // un proceso a medias: si el escáner estaba marcado como ocupado pero no
      // hay ningún resultado en pantalla, nadie lo va a liberar.
      if (_isProcessing && !_veredictoEnPantalla) _resetScanner();
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    // El código se busca ANTES de marcar el escáner como ocupado.
    //
    // Antes se marcaba ocupado en la primera línea y solo se liberaba dentro
    // del camino que encuentra un código. ZXing puede reportar una detección
    // sin texto decodificado, o una lista vacía; cuando eso pasaba una sola
    // vez, `_isProcessing` quedaba en true para siempre y TODAS las lecturas
    // siguientes salían por el return de arriba. La cámara seguía andando y el
    // escáner quedaba muerto sin ninguna señal — el operador en la puerta
    // apunta al QR y no pasa nada.
    String? codigo;
    for (final barcode in capture.barcodes) {
      // Recortado: algunos lectores devuelven el texto con un salto de línea
      // al final, y eso hace fallar la comparación de la firma en el servidor.
      final valor = barcode.rawValue?.trim();
      if (valor != null && valor.isNotEmpty) {
        codigo = valor;
        break; // Solo el primero
      }
    }
    if (codigo == null) return;

    _isProcessing = true; // Antes del hueco asíncrono
    _ocupadoDesde = DateTime.now();
    _registrarLatencia();
    _processCode(codigo);
  }

  Future<void> _processCode(String code) async {
    final l10n = AppLocalizations.of(context);

    // Se toma el notificador ANTES del primer await y se guarda.
    //
    // El velo de "procesando" es global, no de esta pantalla. El `finally`
    // lo apagaba con `if (mounted)`, así que si la pantalla se destruía con una
    // validación en vuelo —el operador sale, la red tarda— el velo quedaba
    // encendido tapando la app entera, y la única salida era cerrarla y
    // abrirla. Teniendo el notificador en una variable se puede apagar aunque
    // el widget ya no exista.
    final velo = ref.read(loadingProvider.notifier);

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      velo.state = true;
      final session = ref.read(deviceProvider);
      final fallbackDeviceId = await ref.read(deviceIdProvider.future);
      final deviceId = session?.deviceId ?? fallbackDeviceId;
      final selectedEvent = ref.read(selectedEventProvider);

      if (selectedEvent == null) {
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.pleaseSelectEvent)));
          context.pop();
        }
        return;
      }

      final result = await ref
          .read(scannerRepositoryProvider)
          .validateQr(code, deviceId, session?.pin, selectedEvent['id'] as String);

      if (mounted) {
        // Refresh Ticket List & Dashboard
        ref.invalidate(ticketsProvider);
        ref.invalidate(dashboardMetricsProvider);
        ref.invalidate(recentActivityProvider);

        // Check if ticket was expired
        if (result['expired'] == true) {
          // El escáner NO se libera acá: si se libera antes del diálogo, la
          // cámara sigue leyendo por detrás y valida el siguiente ticket
          // mientras el operador todavía está leyendo el rechazo. Se libera al
          // cerrarlo.
          HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          HapticFeedback.heavyImpact();
          if (!mounted) return;
          final l10nDialog = AppLocalizations.of(context);
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              // El borde va en rojo y no en el lima del tema: este diálogo
              // siempre trae un rechazo.
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                side: const BorderSide(color: AppTheme.accentOrange),
              ),
              icon: Icon(Icons.cancel,
                  color: AppTheme.peligroTexto(ctx), size: 44),
              title: Text(
                l10nDialog.invalidEntry.toUpperCase(),
                textAlign: TextAlign.center,
                style: AppTheme.titular(ctx,
                    size: 19, color: AppTheme.peligroTexto(ctx)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10nDialog.entryNoLongerValid,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                      height: 1.5,
                      color: AppTheme.textoSecundario(ctx),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.campo(ctx),
                      border: Border(
                        left: BorderSide(
                            color: AppTheme.peligroTexto(ctx), width: 4),
                        top: BorderSide(color: AppTheme.borde(ctx)),
                        right: BorderSide(color: AppTheme.borde(ctx)),
                        bottom: BorderSide(color: AppTheme.borde(ctx)),
                      ),
                    ),
                    child: Text(
                      l10nDialog
                          .validOnlyUntil(result['valid_until']?.toString() ?? '-'),
                      textAlign: TextAlign.center,
                      style: AppTheme.dato(ctx, size: 12.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10nDialog.ticketMarkedVoid,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 11.5,
                      color: AppTheme.textoApagado(ctx),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    l10nDialog.closeAction.toUpperCase(),
                    style: TextStyle(color: AppTheme.peligroTexto(ctx)),
                  ),
                ),
              ],
            ),
          ).then((_) {
            // Recién acá vuelve a escanear, y se reinicia también el punto
            // cero de la medición de latencia.
            if (mounted) _resetScanner();
          });
          return;
        }

        _mostrarVeredicto(result);

        final allowed = result['allowed'] == true;
        if (allowed) {
          HapticFeedback.heavyImpact();
        } else {
          HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          HapticFeedback.heavyImpact();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        final message =
            e is OfflineQueuedException ? l10n.offlineValidationQueued : l10n.scanError;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      // Sin `if (mounted)`: apagar el velo es obligatorio pase lo que pase.
      velo.state = false;
    }
  }

  /// Muestra el veredicto POR ENCIMA del armazón.
  ///
  /// Antes el cartel era lo que devolvía `build`, y como `/scanner` vive dentro
  /// del `ShellRoute`, quedaba encajado entre la cabecera de 56px y la barra
  /// inferior de 62px. Dos consecuencias, las dos malas:
  ///
  ///   - El color no llegaba a los bordes. En un teléfono, más del 20% de la
  ///     altura era cromo de navegación restándole superficie a lo único que
  ///     importa. El "a sangre" que el diseño promete no ocurría.
  ///   - La barra inferior seguía viva y tocable DETRÁS del veredicto. Un toque
  ///     en la zona del pulgar sacaba al operario del escáner en plena
  ///     validación.
  ///
  /// La salida obvia era mover `/scanner` fuera del `ShellRoute`, y es la
  /// equivocada: el escáner perdería la barra, que es justamente por donde el
  /// personal llega a la búsqueda por documento cuando un QR falla. Se resuelve
  /// con `useRootNavigator`, que dibuja encima de todo el armazón sin tocar la
  /// estructura de rutas.
  void _mostrarVeredicto(Map<String, dynamic> resultado) {
    // Dos pedidos encimados no pueden apilar dos carteles.
    if (_veredictoEnPantalla) return;

    try {
      showGeneralDialog(
        context: context,
        useRootNavigator: true,
        // El cartel se cierra solo, con sus propias reglas: tiempo mínimo en
        // pantalla, y botón explícito cuando es un rechazo. Que el sistema lo
        // cierre por atrás —tocando la barrera o con el botón de volver—
        // saltearía las dos cosas.
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        // Sin transición de ruta. El cartel ya entra con su propia animación
        // —el ícono escala en 220ms, el titular funde en 180ms— y encimarle un
        // fundido de ruta solo retrasa el instante en que el operario ve el
        // color. Antes de presentarse como diálogo, el veredicto aparecía en el
        // cuadro siguiente; esto lo devuelve a eso.
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) {
          // Se marca acá y no antes de pedir el diálogo: esto corre cuando la
          // ruta REALMENTE se construyó. Es la diferencia entre "pedí que se
          // abriera" y "está en pantalla", y de esa diferencia depende que el
          // vigía sepa si tiene que rescatar el escáner.
          _veredictoEnPantalla = true;
          return PopScope(
            canPop: false,
            child: VeredictoAcceso(
              resultado: resultado,
              onDismiss: () {
                // Se re-arma ACÁ, antes de cerrar. `whenComplete` corre recién
                // cuando termina la animación de salida de la ruta, y esperar
                // eso le sumaba más de 100ms a cada escaneo — con una fila
                // esperando, eso se paga por persona. `_resetScanner` es
                // idempotente, así que el de `whenComplete` sigue siendo la red
                // de seguridad sin costar nada.
                _resetScanner();
                Navigator.of(context, rootNavigator: true).pop();
              },
            ),
          );
        },
      ).whenComplete(() {
        // Se re-arma el escáner acá y no en `onDismiss`: esto corre cuando la
        // ruta se fue, sin importar CÓMO se fue. Si algún día algo cierra el
        // cartel por un camino que no previmos, el escáner vuelve igual.
        _veredictoEnPantalla = false;
        if (mounted) _resetScanner();
      });
    } catch (e) {
      // Si el diálogo no se pudo ni pedir, el escáner NO puede quedar ocupado
      // esperando un cartel que no existe: eso es el bug de "tengo que cerrar
      // y abrir la app para que lea", con otra ropa.
      _veredictoEnPantalla = false;
      if (kDebugMode) {
        dev.log('No se pudo mostrar el veredicto: $e', name: 'ScannerVeredicto');
      }
      _resetScanner();
    }
  }

  void _resetScanner() {
    setState(() {
      _isProcessing = false;
      _ocupadoDesde = null;
      _detectionWindowStart = DateTime.now();
    });
  }

  /// Libera el escáner si quedó ocupado sin nada en pantalla.
  ///
  /// Esta es la red de seguridad para el síntoma "tengo que cerrar y abrir la
  /// app para que lea". Las causas conocidas ya están arregladas —la sesión del
  /// lector, el velo global, el ciclo de vida— pero un escáner en una puerta no
  /// puede depender de que estén TODAS. Si quedó trabado, se destraba solo.
  ///
  /// No toca nada si el cartel está EN PANTALLA: ahí está ocupado a propósito,
  /// esperando que alguien lea el veredicto y toque para seguir.
  ///
  /// La condición mira si el cartel está EN PANTALLA, no si hubo resultado.
  /// Hasta que el veredicto se presentó como diálogo eran lo mismo, porque
  /// `build` devolvía el cartel y era imposible tener uno sin lo otro. Ya no:
  /// si el diálogo no llegara a abrirse, la condición vieja haría que el vigía
  /// se abstenga de rescatar justo en el caso en que hace falta —escáner
  /// ocupado, pantalla vacía—, que es exactamente el síntoma de "tengo que
  /// cerrar y abrir la app para que lea".
  void _vigilarTrabado() {
    if (!_isProcessing || _veredictoEnPantalla) return;
    final desde = _ocupadoDesde;
    if (desde == null) return;
    if (DateTime.now().difference(desde) < _toleranciaOcupado) return;

    if (kDebugMode) {
      dev.log('Escáner trabado ${_toleranciaOcupado.inSeconds}s: se libera',
          name: 'ScannerVigia');
    }
    _resetScanner();
    // Y se vuelve a encender el lector, por si lo que se cayó fue el bucle.
    _encenderLectorNativo();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // El veredicto ya NO se devuelve desde acá: lo presenta `_mostrarVeredicto`
    // por encima del armazón, así el color llega a los cuatro bordes y la
    // barra inferior deja de estar tocable detrás.

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        children: [
          MobileScanner(
            controller: _cameraController,
            onDetect: _onDetect,
          ),

          // Sin botón de volver propio: la cabecera del armazón ya lo trae, y
          // la barra de abajo permite salir a cualquier destino. Dos formas de
          // volver en la misma pantalla es una de más.

          // Testigo de sistema activo. El punto que late es la única señal de
          // que la cámara está leyendo: sin él, un encuadre que no encuentra
          // nada y un escáner colgado se ven exactamente igual.
          //
          // El texto dice el NOMBRE DEL EVENTO, no "listo para escanear". Esta
          // pantalla era la única del producto que no decía contra qué evento
          // valida: la búsqueda por documento lo muestra, el panel también, y
          // el escáner —donde equivocarse tiene consecuencia inmediata— no.
          // Que el veredicto `wrong_event` exista prueba que el escenario es
          // real: un local con dos salas, o dos fiestas el mismo sábado. El
          // diseño lo detectaba después en vez de prevenirlo antes.
          //
          // "Listo para escanear" era redundante: el punto que late ya dice
          // que está listo, y lo dice mejor porque se mueve.
          Positioned(
            top: 12,
            right: 12,
            left: 12,
            child: Align(
              alignment: Alignment.topRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.darkCardElevated.withValues(alpha: 0.9),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 7, height: 7, color: AppTheme.lima)
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .fade(begin: 0.25, end: 1, duration: 900.ms),
                    const SizedBox(width: 8),
                    // `Flexible` porque un nombre de evento real se pasa de
                    // largo: "FIESTA DE FIN DE AÑO — CLUB SOCIAL Y DEPORTIVO".
                    Flexible(
                      child: Text(
                        (ref.watch(selectedEventProvider)?['name'] ??
                                l10n.readyToScan)
                            .toString()
                            .toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppTheme.darkText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Sin botón de linterna: en web mobile_scanner devuelve hasTorch:false
          // de forma fija (barcode_reader.dart:73-75), así que el control nunca
          // podría encender nada.

          // Mira: cuatro escuadras y una línea de barrido. Antes era un marco
          // cerrado con esquinas redondeadas que latía entero; la escuadra
          // abierta deja ver el QR mientras se encuadra, que es para lo que
          // sirve una mira.
          const Center(child: _Mira()),

          // Instrucción al pie
          Positioned(
            bottom: 16,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.darkCardElevated.withValues(alpha: 0.9),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Text(
                  l10n.alignQrInFrame.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppTheme.darkText,
                  ),
                ),
              ),
            ),
          ),

          // Testigo del decodificador.
          //
          // Antes acá había un panel de latencias que solo se compilaba fuera
          // de release, o sea que en el teléfono de la puerta —el único lugar
          // donde importa— no existía. Cuando alguien reportaba "no lee", no
          // había forma de saber si el escáner estaba procesando cuadros o
          // estaba muerto.
          //
          // Esto queda SIEMPRE, en chico y en una esquina: dice qué motor
          // atiende la cámara y cuánto tardó la última lectura. Es la
          // diferencia entre "no anda" y "usa ZXing y tarda 1.800 ms".
          Positioned(
            left: 12,
            bottom: 12,
            child: _TestigoDeLector(
              estado: _estadoLector,
              latencias: _detectionLatencies,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mira del escáner: cuatro escuadras y una línea de barrido.
class _Mira extends StatelessWidget {
  const _Mira();

  static const double _lado = 268;
  static const double _escuadra = 44;
  static const double _grosor = 4;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _lado,
      height: _lado,
      child: Stack(
        children: [
          const Positioned(top: 0, left: 0, child: _Escuadra(arriba: true, izquierda: true)),
          const Positioned(top: 0, right: 0, child: _Escuadra(arriba: true, izquierda: false)),
          const Positioned(bottom: 0, left: 0, child: _Escuadra(arriba: false, izquierda: true)),
          const Positioned(bottom: 0, right: 0, child: _Escuadra(arriba: false, izquierda: false)),

          // Barrido. Recorre el encuadre de arriba a abajo: dice "estoy
          // mirando" sin tapar el código, que es lo que hacía el marco cerrado.
          Positioned(
            left: _escuadra * 0.35,
            right: _escuadra * 0.35,
            top: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: AppTheme.lima,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.lima.withValues(alpha: 0.55),
                    blurRadius: 10,
                  ),
                ],
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: 6, end: _lado - 8, duration: 2200.ms, curve: Curves.easeInOut),
          ),
        ],
      ),
    );
  }
}

class _Escuadra extends StatelessWidget {
  const _Escuadra({required this.arriba, required this.izquierda});

  final bool arriba;
  final bool izquierda;

  @override
  Widget build(BuildContext context) {
    const lado = BorderSide(color: AppTheme.lima, width: _Mira._grosor);

    return SizedBox(
      width: _Mira._escuadra,
      height: _Mira._escuadra,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: arriba ? lado : BorderSide.none,
            bottom: arriba ? BorderSide.none : lado,
            left: izquierda ? lado : BorderSide.none,
            right: izquierda ? BorderSide.none : lado,
          ),
        ),
      ),
    );
  }
}

/// Hora de la primera entrada, legible por una persona en la puerta.
///
/// El servidor devuelve un timestamp ISO en UTC. Se imprimía tal cual, así que
/// el operador veía "2026-07-28T22:46:22.202+00:00" y tenía que descifrarlo
/// con gente esperando delante. Ahora ve la hora local, y la fecha solo si la
/// entrada no fue hoy.

class _TestigoDeLector extends StatelessWidget {
  const _TestigoDeLector({required this.estado, required this.latencias});

  final Map<String, dynamic> estado;
  final List<int> latencias;

  @override
  Widget build(BuildContext context) {
    final motor = (estado['motor'] as String?) ?? 'zxing';
    final nativo = motor == 'nativo';
    final vivo = estado['vivo'] == true;
    final cuadros = (estado['cuadros'] as num?)?.toInt() ?? 0;
    final reinicios = (estado['reinicios'] as num?)?.toInt() ?? 0;

    final partes = <String>[motor.toUpperCase()];
    if (nativo) partes.add('${cuadros}c');
    if (latencias.isNotEmpty) partes.add('${latencias.last}ms');
    // Los reinicios del vigía son la señal de que algo se está rompiendo por
    // debajo. Solo aparecen si pasaron.
    if (reinicios > 0) partes.add('r$reinicios');

    final color = nativo
        ? (vivo ? AppTheme.lima : AppTheme.accentYellow)
        : AppTheme.darkTextDisabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.darkCardElevated.withValues(alpha: 0.82),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Late mientras se procesan cuadros. Es lo primero que hay que mirar.
          Container(width: 6, height: 6, color: color)
              .animate(
                target: vivo ? 1 : 0,
                onPlay: (c) => c.repeat(reverse: true),
              )
              .fade(begin: 0.25, end: 1, duration: 700.ms),
          const SizedBox(width: 7),
          Text(
            partes.join('  '),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 9,
              height: 1.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
