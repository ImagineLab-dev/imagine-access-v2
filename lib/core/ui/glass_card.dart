import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Panel técnico: un rectángulo con borde de un píxel.
///
/// Se sigue llamando `GlassCard` porque lo importan 23 pantallas, pero de
/// vidrio ya no tiene nada. El *glassmorphism* —fondo borroso, blanco al 5%,
/// esquina redondeada de 16— es la firma más reconocible de la plantilla
/// generada por IA, y encima costaba caro: cada `BackdropFilter` obliga al
/// motor a recomponer lo que hay detrás, y había hasta veinte por pantalla.
///
/// Lo que queda es lo que usa un plano técnico: fondo plano, borde recto,
/// ángulo vivo. Más barato de dibujar y con carácter propio.
///
/// El gesto que le da personalidad es [etiqueta]: el nombre de la sección se
/// monta SOBRE el borde superior, tapándolo, como la leyenda de un esquema.
///
/// ```dart
/// GlassCard(
///   etiqueta: 'PARÁMETROS DE OPERACIÓN',
///   child: ...,
/// )
/// ```
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.blur = 10,
    this.opacity = 0.05,
    this.color,
    this.borderRadius,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.border = true,
    this.height,
    this.width,
    this.etiqueta,
    this.acentuado = false,
    this.elevado = false,
  });

  final Widget child;

  /// Ignorado. Se conserva para no romper las 23 pantallas que lo pasan; el
  /// panel ya no difumina nada.
  final double blur;

  /// Ignorado, igual que [blur].
  final double opacity;

  final Color? color;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final bool border;
  final double? height;
  final double? width;

  /// Leyenda montada sobre el borde superior, como en un plano. Va en
  /// mayúsculas y color acento.
  final String? etiqueta;

  /// Borde en color acento: marca el panel que importa en la pantalla.
  /// Uno por pantalla como mucho — si todos gritan, ninguno se oye.
  final bool acentuado;

  /// Fondo un escalón más claro. Para paneles que van encima de otro panel.
  final bool elevado;

  @override
  Widget build(BuildContext context) {
    final radio = borderRadius ?? BorderRadius.circular(AppTheme.radiusCard);
    final fondo = color ??
        (elevado ? AppTheme.panelElevado(context) : AppTheme.panel(context));
    final colorBorde =
        acentuado ? AppTheme.lima : AppTheme.borde(context);

    Widget panel = Container(
      height: height,
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: radio,
        border: border
            ? Border.all(
                color: colorBorde,
                width: acentuado ? 1.4 : AppTheme.bordeAncho,
              )
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      panel = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radio,
          // Sin onda expansiva: el feedback es el bloque de color, al instante.
          splashFactory: NoSplash.splashFactory,
          hoverColor: AppTheme.hover(context).withValues(alpha: 0.6),
          highlightColor: AppTheme.hover(context),
          child: panel,
        ),
      );
    }

    if (etiqueta == null) {
      return Container(margin: margin, child: panel);
    }

    // La leyenda tapa el borde superior. Necesita el color de fondo de LA
    // PANTALLA, no el del panel, para que el corte del borde sea limpio.
    return Container(
      margin: margin,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(padding: const EdgeInsets.only(top: 7), child: panel),
          Positioned(
            top: 0,
            left: 12,
            child: Container(
              color: AppTheme.fondo(context),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                etiqueta!.toUpperCase(),
                style: AppTheme.etiqueta(
                  context,
                  color: AppTheme.acentoTexto(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de dato: etiqueta a la izquierda, valor mono a la derecha.
///
/// Es el ladrillo que más se repite en la app (detalles de sesión, resumen de
/// evento, desglose de ticket, ficha de dispositivo). Tenerlo acá evita que
/// cada pantalla lo reinvente con paddings distintos y que las columnas de
/// valores no lleguen a alinearse entre sí.
class FilaDato extends StatelessWidget {
  const FilaDato({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.acentuado = false,
    this.separador = true,
  });

  final String etiqueta;
  final String valor;

  /// Pinta el valor con el acento: para el dato que la fila viene a contar.
  final bool acentuado;

  /// Línea inferior. Se apaga en el último de una lista.
  final bool separador;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: separador
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.bordeSuave(context)),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textoSecundario(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: AppTheme.dato(
                context,
                size: 12.5,
                color: acentuado ? AppTheme.acentoTexto(context) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
