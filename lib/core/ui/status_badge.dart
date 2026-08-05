import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum BadgeStatus { success, warning, error, neutral }

/// Etiqueta de estado: un bloque recto con el texto en monoespaciada.
///
/// Antes era una píldora redondeada con el color al 10% de opacidad, borde al
/// 30% y una sombra del mismo color: tres capas translúcidas para decir una
/// palabra, y encima pedía la fuente `'Inter'`, que no está empaquetada —así
/// que caía en la de sistema y desentonaba con el resto—.
///
/// Ahora es un bloque macizo, que es como se lee un estado de un vistazo en la
/// puerta de un evento con poca luz.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.text,
    this.status = BadgeStatus.neutral,
    this.icon,
    this.solido = true,
  });

  final String text;
  final BadgeStatus status;
  final IconData? icon;

  /// Bloque macizo. En `false` queda solo el contorno, para cuando hay muchos
  /// juntos en una lista y el macizo sería demasiado ruido.
  final bool solido;

  @override
  Widget build(BuildContext context) {
    final (Color relleno, Color tinta) = switch (status) {
      BadgeStatus.success => (AppTheme.lima, AppTheme.limaTinta),
      BadgeStatus.warning => (AppTheme.accentYellow, const Color(0xFF3A2A00)),
      BadgeStatus.error => (AppTheme.accentOrange, Colors.white),
      BadgeStatus.neutral => (
          AppTheme.hover(context),
          AppTheme.textoSecundario(context)
        ),
    };

    final Color fondo;
    final Color texto;
    final Color borde;

    if (solido && status != BadgeStatus.neutral) {
      fondo = relleno;
      texto = tinta;
      borde = relleno;
    } else {
      fondo = status == BadgeStatus.neutral
          ? AppTheme.hover(context)
          : Colors.transparent;
      // En modo claro el lima puro como texto no se lee; [acentoTexto] y
      // [peligroTexto] devuelven la variante que sí contrasta.
      texto = switch (status) {
        BadgeStatus.success => AppTheme.acentoTexto(context),
        BadgeStatus.error => AppTheme.peligroTexto(context),
        BadgeStatus.warning => AppTheme.esOscuro(context)
            ? AppTheme.accentYellow
            : const Color(0xFF8A5A00),
        BadgeStatus.neutral => AppTheme.textoSecundario(context),
      };
      borde = status == BadgeStatus.neutral ? AppTheme.borde(context) : texto;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        border: Border.all(color: borde, width: AppTheme.bordeAncho),
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: texto),
            const SizedBox(width: 5),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              height: 1.2,
              color: texto,
            ),
          ),
        ],
      ),
    );
  }
}
