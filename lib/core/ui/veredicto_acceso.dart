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
class VeredictoAcceso extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final permitido = (resultado['allowed'] as bool?) ??
        (resultado['success'] as bool?) ??
        false;
    final ticket = resultado['ticket'];
    final codigo = resultado['result']?.toString();

    final veredicto = permitido
        ? Veredicto.validado
        : (codigo == 'already_used' ? Veredicto.yaUsado : Veredicto.denegado);

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
    };

    final icono = switch (veredicto) {
      Veredicto.validado => Icons.check_circle,
      Veredicto.denegado => Icons.dangerous,
      Veredicto.yaUsado => Icons.warning_rounded,
    };

    final titulo = codigo == 'wrong_event'
        ? l10n.wrongEvent
        : (resultado['message']?.toString() ??
            switch (veredicto) {
              Veredicto.validado => l10n.accessGranted,
              Veredicto.denegado => l10n.accessDenied,
              Veredicto.yaUsado => l10n.alreadyUsed,
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
                if (nota != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    nota!,
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
