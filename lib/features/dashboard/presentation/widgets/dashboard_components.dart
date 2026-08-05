import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:imagine_access/core/ui/responsive.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/glass_card.dart';

/// Métrica compacta: un número y qué significa.
///
/// El número va en la grotesca y la etiqueta en mono, porque en un tablero lo
/// que se compara de un vistazo es la columna de números — y para eso tienen
/// que tener todos el mismo ancho de dígito.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.delay,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final int delay;

  @override
  Widget build(BuildContext context) {
    // Ícono al costado, no arriba.
    //
    // Antes era una Column con `spaceBetween`: el ícono se iba al borde de
    // arriba, el número al de abajo, y entre los dos quedaba un hueco vacío que
    // era la mitad de la tarjeta. Con nueve métricas eso son varias pantallas
    // de desplazamiento para leer nueve números. En fila, el mismo contenido
    // entra en poco más de la mitad del alto y la etiqueta gana el ancho que
    // antes le robaba el ícono, así que "INGRESO INVITADOS" ya no se corta.
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: AppTheme.titular(context, size: 19),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.dato(
                    context,
                    size: 9,
                    color: AppTheme.textoSecundario(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fade(delay: delay.ms);
  }
}

/// Métrica destacada: número grande, una línea de detalle y una barra de
/// avance. Es la tarjeta del diseño para las dos o tres cifras que mandan.
class EliteMetricCard extends StatelessWidget {
  const EliteMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.subValue,
    required this.icon,
    required this.delay,
    this.color,
    this.progress,
    this.progressColor,
  });

  final String title;
  final String value;
  final String subValue;
  final IconData icon;
  final int delay;

  /// Ignorado. En esta tarjeta el ícono va siempre apagado —lo que tiene que
  /// saltar es el número, no la ilustración de al lado—. Se conserva para no
  /// romper las llamadas que todavía lo pasan.
  final Color? color;
  final double? progress;
  final Color? progressColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.etiqueta(
                    context,
                    size: 9.5,
                    color: AppTheme.acentoTexto(context),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // El ícono va apagado: en esta tarjeta lo que tiene que saltar es
              // el número, no la ilustración de al lado.
              Icon(icon, color: AppTheme.textoApagado(context), size: 17),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: AppTheme.titular(context, size: 27),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.dato(
                  context,
                  size: 10.5,
                  color: AppTheme.textoSecundario(context),
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: 10),
                // Barra recta y fina, como un indicador de nivel. Sin esquinas
                // redondeadas: es el mismo criterio que el resto del sistema.
                SizedBox(
                  height: 4,
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0.0, 1.0),
                    backgroundColor: AppTheme.campo(context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        progressColor ?? AppTheme.lima),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ).animate().fade(delay: delay.ms);
  }
}

class ActionItem {
  const ActionItem(
    this.text,
    this.icon,
    this.route, {
    this.color,
    this.isPrimary = false,
  });

  final String text;
  final IconData icon;
  final String route;
  final Color? color;
  final bool isPrimary;
}

class QuickActions extends StatelessWidget {
  const QuickActions({
    super.key,
    required this.actions,
    this.onActionBeforeNavigate,
  });

  final List<ActionItem> actions;
  final bool Function(ActionItem action)? onActionBeforeNavigate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Sin acciones no hay sección: un título sobre una grilla vacía ocupa
    // lugar para decir que no hay nada que hacer.
    if (actions.isEmpty) return const SizedBox.shrink();

    // Nunca más columnas que tarjetas.
    //
    // La grilla pedía 3 columnas fijas, así que cuatro acciones se acomodaban
    // 3 + 1 y la última quedaba sola con dos huecos al lado; y una sola acción
    // ocupaba un tercio de la fila con el resto vacío. Ahora el ancho se
    // reparte entre las que hay.
    final columnas = Responsive.columnas(context, anchoObjetivo: 340, maximo: 3)
        .clamp(1, actions.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.quickActions.toUpperCase(),
          style: AppTheme.titular(context, size: 16),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnas,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            // Un ícono y una etiqueta: 110px de alto alcanzan de sobra.
            childAspectRatio: Responsive.proporcionTarjeta(context,
                alturaObjetivo: 110, anchoObjetivo: 340, maximo: columnas),
          ),
          itemCount: actions.length,
          itemBuilder: (context, index) => ActionCard(
            action: actions[index],
            onBeforeNavigate: onActionBeforeNavigate,
          ),
        ),
      ],
    );
  }
}

class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.action,
    this.onBeforeNavigate,
  });

  final ActionItem action;
  final bool Function(ActionItem action)? onBeforeNavigate;

  @override
  Widget build(BuildContext context) {
    // La acción principal se marca con el borde lima, no con un degradado de
    // relleno. Un borde es más barato de dibujar y se lee igual de rápido.
    return GlassCard(
      padding: EdgeInsets.zero,
      acentuado: action.isPrimary,
      onTap: () {
        final puedeNavegar = onBeforeNavigate?.call(action) ?? true;
        if (!puedeNavegar) return;
        if (action.route.isEmpty || action.route == '#') return;
        context.push(action.route);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            action.icon,
            size: 22,
            color: action.isPrimary
                ? AppTheme.acentoTexto(context)
                : (action.color ?? AppTheme.textoSecundario(context)),
          ),
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              action.text.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.etiqueta(
                context,
                size: 10.5,
                color: AppTheme.texto(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
