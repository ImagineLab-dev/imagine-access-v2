import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// El cartel a pantalla completa que decide si alguien entra.
///
/// POR QUÉ ESTO VIVE EN `core/ui/` Y NO EN LA PANTALLA DEL ESCÁNER
///
/// La persona de puerta tiene DOS caminos para validar a alguien: escanear el
/// QR, y —cuando el QR falla— buscarlo por documento. Hasta el 07/08/2026 cada
/// camino tenía su propio cartel de veredicto, escritos por manos distintas:
///
///     escáner                        búsqueda por documento
///     tres estados                   dos estados
///     lima / gris / casi negro       verde / rojo
///     Space Grotesk 44px             TextStyle crudo 24px (caía en Chivo)
///     datos en mono bajo una regla   GlassCard flotando sobre el color
///     tinta con contraste medido     blanco sobre lima: 1,70:1, ilegible
///
/// Que sean distintos no es un problema estético. La búsqueda por documento es
/// justo el camino al que se recurre cuando ya hay fricción y alguien
/// esperando: el peor momento posible para cambiarle a alguien el idioma
/// visual. Ahora hay UN solo cartel y los dos caminos lo usan.
///
/// CÓMO SE LEE SIN LEERLO
///
/// Quien está en la puerta no lee el cartel: lo ve de reojo, de noche,
/// mientras mira a la persona. Por eso los tres estados se separan en tres
/// canales que sobreviven a esa situación, y ninguno de los tres es el tono:
///
///   1. BRILLO — lima (L 0,566), gris (L 0,035) y casi negro (L 0,019).
///      Entre ADELANTE y NO PASA hay 10,43:1. Antes había 1,00:1: eran la
///      misma pantalla en escala de grises. Ver [AppTheme.peligroProfundo].
///   2. SILUETA — círculo, triángulo y octógono. La silueta se reconoce antes
///      que el glifo que tiene adentro.
///   3. PRIMERA PALABRA — "ADELANTE", "NO PASA", "YA USADO". Antes las dos
///      primeras eran "ACCESO ..." y la diferencia estaba en la segunda
///      palabra, que a esa velocidad nadie lee.
class VeredictoAcceso extends StatefulWidget {
  /// Respuesta cruda de la validación. Se aceptan las dos formas que devuelven
  /// los dos caminos: `allowed` (escáner) y `success` (búsqueda por documento).
  final Map<String, dynamic> resultado;

  /// Qué hacer cuando se descarta el cartel.
  final VoidCallback onDismiss;

  /// Línea al pie, opcional. La búsqueda por documento la usa para avisar que
  /// la validación manual queda auditada, que es información que el operario
  /// necesita ver en el momento de hacerla, no después.
  final String? nota;

  const VeredictoAcceso({
    super.key,
    required this.resultado,
    required this.onDismiss,
    this.nota,
  });

  /// Lo que el cartel tiene que estar en pantalla antes de aceptar que lo
  /// cierren, cuando la persona PASA.
  ///
  /// Sin ningún mínimo, el dedo que ya venía bajando —o la palma al devolver el
  /// teléfono— cerraba el veredicto antes de que nadie lo leyera, y no había
  /// forma de volver a verlo.
  ///
  /// Es corto a propósito. Un gesto que ya estaba en curso tarda unos 200ms en
  /// llegar; con esto no cierra. Y como el 90% de los escaneos de una noche son
  /// este caso, cada milisegundo acá se multiplica por cuatrocientos: medio
  /// segundo por persona son más de tres minutos de fila.
  static const Duration minimoAlPasar = Duration(milliseconds: 250);

  /// Lo mismo cuando la persona NO pasa, o su entrada ya se usó.
  ///
  /// Acá sí hay algo que leer —la hora del primer ingreso, el evento al que
  /// pertenece el ticket— y el operario va a tener que decir algo en voz alta.
  /// Que el cartel no se pueda cerrar todavía es lo que le da ese momento.
  static const Duration minimoAlRechazar = Duration(milliseconds: 600);

  /// Llave del botón que cierra un rechazo. Existe para poder afirmar en un
  /// test que un toque en cualquier otro lado NO cierra el cartel, que es la
  /// conducta que separa esta versión de la anterior.
  static const Key llaveBotonCerrar = Key('veredicto-cerrar');

  @override
  State<VeredictoAcceso> createState() => _VeredictoAccesoState();
}

class _VeredictoAccesoState extends State<VeredictoAcceso> {
  bool _sePuedeCerrar = false;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    // El mínimo depende del veredicto: quien pasa no tiene nada que leer, y
    // quien no pasa sí. Se calcula acá y no en `build` porque el reloj arranca
    // una sola vez.
    final permitido = (widget.resultado['allowed'] as bool?) ??
        (widget.resultado['success'] as bool?) ??
        false;
    _reloj = Timer(
      permitido
          ? VeredictoAcceso.minimoAlPasar
          : VeredictoAcceso.minimoAlRechazar,
      () {
        if (mounted) setState(() => _sePuedeCerrar = true);
      },
    );
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  void _cerrar() {
    if (!_sePuedeCerrar) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final resultado = widget.resultado;
    final nota = widget.nota;
    final l10n = AppLocalizations.of(context);
    final permitido = (resultado['allowed'] as bool?) ??
        (resultado['success'] as bool?) ??
        false;
    final ticket = resultado['ticket'];
    final codigo = resultado['result']?.toString();

    // Los códigos internos no son veredictos de la puerta: son situaciones del
    // sistema —falta elegir evento, no hay señal, se cayó la red— que antes se
    // comunicaban con un SnackBar. Una tira gris de tres segundos, abajo del
    // todo, mientras el operario mira a la persona y no al teléfono.
    //
    // El escáner tiene un canal excelente para hablar, que es la pantalla
    // entera de color, y lo usaba SOLO cuando todo salía bien. Cuando algo
    // fallaba, susurraba. Para quien prueba el producto por primera vez eso es
    // exactamente "escaneé y no pasó nada", y se va pensando que está roto.
    final veredicto = switch (codigo) {
      'sin_evento' => Veredicto.sinEvento,
      'encolado' => Veredicto.pendiente,
      'error_red' => Veredicto.error,
      _ => permitido
          ? Veredicto.validado
          : (codigo == 'already_used'
              ? Veredicto.yaUsado
              : Veredicto.denegado),
    };

    // fondo, tinta, borde. El borde solo lo usa "ya usado": al ir sobre
    // oscuro necesita un marco que lo haga inconfundible desde lejos.
    final (Color fondo, Color tinta, Color? marco) = switch (veredicto) {
      Veredicto.validado => (AppTheme.lima, AppTheme.limaTinta, null),
      Veredicto.denegado => (
          AppTheme.peligroProfundo,
          AppTheme.peligroSuave,
          null
        ),
      Veredicto.yaUsado => (
          AppTheme.darkBorderSoft,
          AppTheme.accentYellow,
          AppTheme.accentYellow
        ),
      // Los tres de sistema comparten el fondo de la app y se distinguen por
      // la tinta. Es a propósito: no son decisiones sobre la persona que está
      // enfrente, y no tienen que competir en fuerza con las que sí lo son.
      Veredicto.sinEvento => (AppTheme.darkBg, AppTheme.lima, AppTheme.lima),
      Veredicto.pendiente => (
          AppTheme.darkBg,
          AppTheme.accentYellow,
          AppTheme.accentYellow
        ),
      Veredicto.error => (
          AppTheme.darkBg,
          AppTheme.peligroSuave,
          AppTheme.peligroSuave
        ),
    };

    final icono = switch (veredicto) {
      Veredicto.validado => Icons.check_circle,
      Veredicto.denegado => Icons.dangerous,
      Veredicto.yaUsado => Icons.warning_rounded,
      Veredicto.sinEvento => Icons.event_outlined,
      Veredicto.pendiente => Icons.cloud_off_outlined,
      Veredicto.error => Icons.wifi_tethering_off_outlined,
    };

    final titulo = codigo == 'wrong_event'
        ? l10n.wrongEvent
        : (resultado['message']?.toString() ??
            switch (veredicto) {
              Veredicto.validado => l10n.accessGranted,
              Veredicto.denegado => l10n.accessDenied,
              Veredicto.yaUsado => l10n.alreadyUsed,
              Veredicto.sinEvento => l10n.pleaseSelectEvent,
              Veredicto.pendiente => l10n.offlineValidationQueued,
              Veredicto.error => l10n.scanError,
            });

    // Datos del ticket, en mono y bajo una regla: es la "letra chica" del
    // pase. Antes iban en una tarjeta blanca redondeada flotando sobre el
    // color, que partía la pantalla en dos y le robaba fuerza al veredicto.
    final lineas = <(String, String)>[
      if ((ticket?['buyer_name']) != null)
        (l10n.name.toUpperCase(), ticket['buyer_name'].toString()),
      if ((ticket?['type']) != null)
        (l10n.ticketType.toUpperCase(), ticket['type'].toString()),
      if (codigo == 'wrong_event')
        (
          l10n.ticketBelongsTo,
          (resultado['event_name'] ?? l10n.unknown).toString()
        ),
      if (codigo == 'already_used')
        (l10n.firstEntry, horaLegible(ticket?['scanned_at'], l10n)),
    ];

    // Cómo se cierra cada uno.
    //
    // Los tres se cerraban con un toque en cualquier parte, sin tiempo mínimo.
    // Para NO PASA eso está mal: es la decisión más cara del producto y era la
    // única que se cerraba por accidente. Ahora exige apuntar a un botón, que
    // es un gesto que no ocurre al devolver el teléfono ni al rozar la
    // pantalla. Los otros dos siguen con toque libre porque la fila avanza y
    // hacer que el operario apunte 400 veces por noche sería peor.
    final exigeBoton = veredicto == Veredicto.denegado;

    return Scaffold(
      backgroundColor: fondo,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: exigeBoton ? null : _cerrar,
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
                if (nota != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    nota,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 10,
                      letterSpacing: 0.6,
                      color: tinta.withValues(alpha: 0.7),
                    ),
                  ),
                ],
                const SizedBox(height: 34),
                // El pie aparece recién cuando el cartel se puede cerrar. Que
                // no esté es la señal de "todavía no": no hay que explicarla.
                AnimatedOpacity(
                  opacity: _sePuedeCerrar ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: exigeBoton
                      ? _BotonCerrar(
                          key: VeredictoAcceso.llaveBotonCerrar,
                          etiqueta: l10n.closeAction.toUpperCase(),
                          tinta: tinta,
                          fondo: fondo,
                          onPressed: _cerrar,
                        )
                      : Text(
                          '[ ${l10n.tapToDismiss.toUpperCase()} ]',
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 11,
                            letterSpacing: 0.8,
                            color: tinta.withValues(alpha: 0.65),
                          ),
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

/// El botón que cierra un rechazo.
///
/// No usa `NeonButton` a propósito: ese pinta en lima, y acá el lima significa
/// "pasa". Un botón lima dentro del cartel de NO PASA sería la única mancha del
/// color equivocado en la pantalla que menos ambigüedad tolera. Va en la tinta
/// del propio cartel, que ya tiene 10,47:1 contra el fondo.
class _BotonCerrar extends StatelessWidget {
  final String etiqueta;
  final Color tinta;
  final Color fondo;
  final VoidCallback onPressed;

  const _BotonCerrar({
    super.key,
    required this.etiqueta,
    required this.tinta,
    required this.fondo,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: etiqueta,
      child: InkWell(
        onTap: onPressed,
        // 56 de alto y 200 de ancho: se apunta con el pulgar, de noche, con
        // una mano. El mínimo de accesibilidad es 44.
        child: Container(
          height: 56,
          constraints: const BoxConstraints(minWidth: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tinta,
            border: Border.all(color: tinta, width: 2),
          ),
          child: Text(
            etiqueta,
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: fondo,
            ),
          ),
        ),
      ),
    );
  }
}

/// Los tres veredictos posibles en la puerta.
///
/// Antes eran dos —pasa o no pasa— y "ya usado" se pintaba igual que un código
/// falso. No son lo mismo: un código falso es alguien que no tiene entrada, y
/// uno ya usado es alguien que SÍ la tenía y entró antes. Quien está en la
/// puerta resuelve cada caso distinto, así que tienen que verse distinto.
enum Veredicto {
  /// Adelante. Lima a sangre.
  validado,

  /// No pasa. Casi negro a sangre, con la tinta en salmón.
  denegado,

  /// Ojo: esta entrada ya se usó. Ámbar sobre oscuro, para que no se confunda
  /// con las otras dos ni de reojo.
  yaUsado,

  /// Falta elegir el evento contra el cual validar.
  ///
  /// No es un veredicto sobre la persona: es el sistema pidiendo un dato. Antes
  /// salía por un SnackBar y además sacaba al operario de la pantalla, así que
  /// para alguien que probaba el producto por primera vez el escaneo
  /// simplemente "no hacía nada".
  sinEvento,

  /// Sin señal: la validación quedó encolada y se sincroniza sola.
  ///
  /// Es el estado más delicado de todos, porque la persona YA pasó y el
  /// operario tiene que saber que esa entrada todavía no está confirmada.
  /// Comunicarlo con la tira gris de menor jerarquía del sistema era pedir que
  /// no se enterara.
  pendiente,

  /// No se pudo verificar: la red falló o el servidor no contestó a tiempo.
  ///
  /// Distinto de un rechazo, y la diferencia importa: en un rechazo la persona
  /// no entra, acá no se sabe. El operario tiene que volver a intentar, no
  /// tomar una decisión.
  error,
}

/// Convierte una marca de tiempo en algo que se pueda decir en voz alta.
///
/// Es la diferencia entre discutir a ciegas y terminar la discusión: el
/// operario no muestra `2026-07-28T22:46:22.202+00:00`, dice "esta entrada se
/// usó a las 23:14". Si fue otro día se antepone la fecha, porque a las tres
/// de la mañana "23:14" a secas se lee como "hoy".
String horaLegible(dynamic valor, AppLocalizations l10n) {
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
