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
  Map<String, dynamic>? _scanResult; // To show overlay

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
      if (_isProcessing && _scanResult == null) _resetScanner();
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

        setState(() {
          _scanResult = result;
        });

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

  void _resetScanner() {
    setState(() {
      _scanResult = null;
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
  /// No toca nada si hay un resultado en pantalla: ahí está ocupado a propósito,
  /// esperando que alguien lea el veredicto y toque para seguir.
  void _vigilarTrabado() {
    if (!_isProcessing || _scanResult != null) return;
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
    // If we have a result, show the Full Screen Result Overlay
    if (_scanResult != null) {
      return _ResultOverlay(scanResult: _scanResult!, onDismiss: _resetScanner);
    }

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
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                  Text(
                    l10n.readyToScan.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppTheme.darkText,
                    ),
                  ),
                ],
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
String _horaLegible(dynamic valor, AppLocalizations l10n) {
  if (valor == null) return l10n.unknown;
  final fecha = DateTime.tryParse(valor.toString())?.toLocal();
  if (fecha == null) return l10n.unknown;

  final hh = fecha.hour.toString().padLeft(2, '0');
  final mm = fecha.minute.toString().padLeft(2, '0');

  final ahora = DateTime.now();
  final mismoDia = fecha.year == ahora.year &&
      fecha.month == ahora.month &&
      fecha.day == ahora.day;
  if (mismoDia) return '$hh:$mm';

  final dd = fecha.day.toString().padLeft(2, '0');
  final mo = fecha.month.toString().padLeft(2, '0');
  return '$dd/$mo  $hh:$mm';
}

/// Los tres veredictos posibles en la puerta.
///
/// Antes eran dos —pasa o no pasa— y "ya usado" se pintaba igual que un código
/// falso. No son lo mismo: un código falso es alguien que no tiene entrada, y
/// uno ya usado es alguien que SÍ la tenía y entró antes. Quien está en la
/// puerta resuelve cada caso distinto, así que tienen que verse distinto.
enum _Veredicto {
  /// Adelante. Lima a sangre.
  validado,

  /// No pasa. Salmón a sangre.
  denegado,

  /// Ojo: esta entrada ya se usó. Ámbar sobre oscuro, para que no se confunda
  /// con las otras dos ni de reojo.
  yaUsado,
}

class _ResultOverlay extends StatelessWidget {
  final Map<String, dynamic> scanResult;
  final VoidCallback onDismiss;

  const _ResultOverlay({required this.scanResult, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allowed = (scanResult['allowed'] as bool?) ??
        (scanResult['success'] as bool?) ??
        false;
    final ticket = scanResult['ticket'];
    final resultCode = scanResult['result']?.toString();

    final veredicto = allowed
        ? _Veredicto.validado
        : (resultCode == 'already_used'
            ? _Veredicto.yaUsado
            : _Veredicto.denegado);

    // fondo, tinta, borde. El borde solo lo usa "ya usado": al ir sobre
    // oscuro necesita un marco que lo haga inconfundible desde lejos.
    final (Color fondo, Color tinta, Color? marco) = switch (veredicto) {
      _Veredicto.validado => (AppTheme.lima, AppTheme.limaTinta, null),
      _Veredicto.denegado => (AppTheme.peligroSuave, AppTheme.peligroTinta, null),
      _Veredicto.yaUsado => (
          AppTheme.darkBorderSoft,
          AppTheme.accentYellow,
          AppTheme.accentYellow
        ),
    };

    final icono = switch (veredicto) {
      _Veredicto.validado => Icons.check_circle,
      _Veredicto.denegado => Icons.cancel,
      _Veredicto.yaUsado => Icons.warning_rounded,
    };

    final titulo = resultCode == 'wrong_event'
        ? l10n.wrongEvent
        : (scanResult['message']?.toString() ??
            switch (veredicto) {
              _Veredicto.validado => l10n.accessGranted,
              _Veredicto.denegado => l10n.accessDenied,
              _Veredicto.yaUsado => l10n.alreadyUsed,
            });

    // Datos del ticket, en mono y bajo una regla: es la "letra chica" del
    // pase. Antes iban en una tarjeta blanca redondeada flotando sobre el
    // color, que partía la pantalla en dos y le robaba fuerza al veredicto.
    final lineas = <(String, String)>[
      if ((ticket?['buyer_name']) != null)
        (l10n.name.toUpperCase(), ticket['buyer_name'].toString()),
      if ((ticket?['type']) != null)
        (l10n.ticketType.toUpperCase(), ticket['type'].toString()),
      if (resultCode == 'wrong_event')
        (
          l10n.ticketBelongsTo,
          (scanResult['event_name'] ?? l10n.unknown).toString()
        ),
      if (resultCode == 'already_used')
        (l10n.firstEntry, _horaLegible(ticket?['scanned_at'], l10n)),
    ];

    return Scaffold(
      backgroundColor: fondo,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: Container(
            width: double.infinity,
            decoration: marco == null
                ? null
                : BoxDecoration(border: Border.all(color: marco, width: 8)),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icono, size: 108, color: tinta)
                    .animate()
                    .scale(duration: 220.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 18),
                Text(
                  titulo.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.4,
                    height: 1.0,
                    color: tinta,
                  ),
                ).animate().fade(duration: 180.ms),
                if (lineas.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Container(
                      padding: const EdgeInsets.only(top: 14),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: tinta, width: 2)),
                      ),
                      child: Column(
                        children: [
                          for (final (etiqueta, valor) in lineas)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                children: [
                                  Text(
                                    etiqueta,
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontDisplay,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                      color: tinta.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    valor,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontMono,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: tinta,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ).animate().fade(delay: 90.ms),
                ],
                const SizedBox(height: 34),
                Text(
                  '[ ${l10n.tapToDismiss.toUpperCase()} ]',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11,
                    letterSpacing: 0.8,
                    color: tinta.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Testigo del escáner: dice si está leyendo, y con qué.
///
/// Antes acá había un panel de latencias que solo se compilaba fuera de
/// release, o sea que en el teléfono de la puerta —el único lugar donde
/// importa— no existía. Cuando alguien reportaba "no lee", no había forma de
/// saber si el escáner estaba procesando cuadros o estaba muerto.
///
/// Lo importante no es el motor sino el **punto**: si late, el lector está
/// procesando cuadros ahora mismo. Si se queda apagado, está colgado — y eso se
/// ve de un vistazo sin leer nada.
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
