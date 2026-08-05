import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Botón de acción: un bloque macizo de color, recto y en mayúsculas.
///
/// Se sigue llamando `NeonButton` porque lo importan 8 pantallas, pero ya no
/// tiene nada de neón. Le saqué las tres cosas que lo delataban como plantilla:
/// la sombra de color difuminada debajo, el *shimmer* que le barría un brillo
/// en bucle cada 1,8 s, y la esquina redondeada de 12.
///
/// El brillo en bucle además era un problema real de accesibilidad: una
/// animación infinita que nadie pidió, corriendo en todos los botones de la
/// pantalla a la vez. Ahora el único movimiento es la respuesta al dedo.
class NeonButton extends StatefulWidget {
  const NeonButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.color,
    this.isLoading = false,
    this.isSecondary = false,
    this.anchoCompleto = true,
  });

  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Color del bloque. Por defecto el lima de la marca. Se pasa distinto solo
  /// para acciones destructivas.
  final Color? color;

  final bool isLoading;

  /// Solo contorno, sin relleno. Para la acción de al lado, nunca para la
  /// principal.
  final bool isSecondary;

  final bool anchoCompleto;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _presionado = false;

  /// Tinta legible encima del bloque. Sobre el lima va la tinta lima oscura
  /// (el blanco daría 1,9:1 y sería ilegible); sobre un color oscuro, blanco.
  Color _tintaSobre(Color fondo) {
    if (fondo == AppTheme.lima || fondo == AppTheme.limaVivo) {
      return AppTheme.limaTinta;
    }
    return fondo.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final habilitado = widget.onPressed != null && !widget.isLoading;
    final base = widget.color ?? AppTheme.lima;

    final Color relleno;
    final Color tinta;
    final BoxBorder? borde;

    if (widget.isSecondary) {
      relleno = _presionado ? AppTheme.hover(context) : Colors.transparent;
      tinta = habilitado
          ? AppTheme.texto(context)
          : AppTheme.textoApagado(context);
      borde = Border.all(
        color: habilitado ? AppTheme.texto(context) : AppTheme.borde(context),
      );
    } else if (!habilitado) {
      relleno = AppTheme.borde(context);
      tinta = AppTheme.textoApagado(context);
      borde = null;
    } else {
      // Al presionar sube al lima encendido, igual que el hover del diseño.
      relleno = _presionado && base == AppTheme.lima ? AppTheme.limaVivo : base;
      tinta = _tintaSobre(base);
      borde = null;
    }

    final contenido = widget.isLoading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: tinta),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 17, color: tinta),
                const SizedBox(width: 9),
              ],
              Flexible(
                child: Text(
                  widget.text.toUpperCase(),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 1.2,
                    color: tinta,
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: habilitado,
      label: widget.text,
      child: GestureDetector(
        onTapDown: habilitado ? (_) => setState(() => _presionado = true) : null,
        onTapUp: habilitado ? (_) => setState(() => _presionado = false) : null,
        onTapCancel:
            habilitado ? () => setState(() => _presionado = false) : null,
        onTap: habilitado
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: MouseRegion(
          cursor: habilitado
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: widget.anchoCompleto ? double.infinity : null,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: relleno,
              border: borde,
              borderRadius: BorderRadius.circular(AppTheme.radiusField),
            ),
            child: contenido,
          ),
        ),
      ),
    );
  }
}
