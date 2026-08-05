import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'neon_button.dart';

/// Estado vacío con una acción.
///
/// Los estados vacíos del proyecto eran una línea de texto suelta —"No se
/// encontraron eventos"— sin explicar qué hacer ni ofrecer cómo hacerlo. Para
/// alguien que entra por primera vez eso es un callejón: la app tiene un orden
/// obligatorio (evento → equipo → tickets → escanear) que nunca enseña.
///
/// Un vacío es el mejor momento para guiar: no hay nada que leer y toda la
/// atención está disponible.
///
/// Visualmente es un panel con borde punteado, el mismo gesto que usa la zona
/// de "cargar archivo": dice "acá va algo que todavía no está" sin necesidad
/// de escribirlo.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  final IconData icon;
  final String title;

  /// Explica por qué importa lo que falta, no solo que falta.
  final String? body;

  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: ConstrainedBox(
          // Sin tope, en un monitor el texto explicativo se estira en una sola
          // línea larguísima y deja de leerse.
          constraints: const BoxConstraints(maxWidth: 420),
          child: CustomPaint(
            painter: _BordePunteado(color: AppTheme.borde(context)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 40, color: AppTheme.textoApagado(context)),
                  const SizedBox(height: 18),
                  Text(
                    title.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: AppTheme.titular(context, size: 17),
                  ),
                  if (body != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      body!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        height: 1.55,
                        color: AppTheme.textoSecundario(context),
                      ),
                    ),
                  ],
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 24),
                    NeonButton(
                      text: actionLabel!,
                      icon: actionIcon ?? Icons.add,
                      onPressed: onAction,
                      anchoCompleto: false,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Borde punteado rectangular. Flutter no trae uno, y `DashedBorder` de
/// paquete sería una dependencia entera para cuatro líneas.
class _BordePunteado extends CustomPainter {
  const _BordePunteado({required this.color});

  final Color color;

  static const double _trazo = 5;
  static const double _hueco = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    void linea(Offset desde, Offset hasta) {
      final total = (hasta - desde).distance;
      if (total <= 0) return;
      final paso = (hasta - desde) / total;
      double avance = 0;
      while (avance < total) {
        final fin = (avance + _trazo).clamp(0.0, total);
        canvas.drawLine(
          desde + paso * avance,
          desde + paso * fin,
          pincel,
        );
        avance = fin + _hueco;
      }
    }

    linea(Offset.zero, Offset(size.width, 0));
    linea(Offset(size.width, 0), Offset(size.width, size.height));
    linea(Offset(size.width, size.height), Offset(0, size.height));
    linea(Offset(0, size.height), Offset.zero);
  }

  @override
  bool shouldRepaint(_BordePunteado anterior) => anterior.color != color;
}
