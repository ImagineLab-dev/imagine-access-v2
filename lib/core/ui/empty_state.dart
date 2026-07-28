import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Estado vacío con una acción.
///
/// Los estados vacíos del proyecto eran una línea de texto suelta —"No se
/// encontraron eventos"— sin explicar qué hacer ni ofrecer cómo hacerlo. Para
/// alguien que entra por primera vez eso es un callejón: la app tiene un orden
/// obligatorio (evento → equipo → tickets → escanear) que nunca enseña.
///
/// Un vacío es el mejor momento para guiar: no hay nada que leer y toda la
/// atención está disponible.
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
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: ConstrainedBox(
          // Sin tope, en un monitor el texto explicativo se estira en una sola
          // línea larguísima y deja de leerse.
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 56,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.25)),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (body != null) ...[
                const SizedBox(height: 10),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon ?? Icons.add, size: 18),
                  label: Text(actionLabel!),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
