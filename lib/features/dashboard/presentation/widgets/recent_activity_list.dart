import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/glass_card.dart';
import '../../data/dashboard_repository.dart';

/// Últimos escaneos.
///
/// Es un registro de sistema, así que se ve como uno: la hora primero y en
/// mono, una barra de color al costado que dice si pasó o no, y el nombre al
/// lado. Antes cada fila abría con un círculo de color, la hora quedaba al
/// final y las horas no alineaban entre sí porque iban en tipografía de texto.
class RecentActivityList extends ConsumerWidget {
  const RecentActivityList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activityAsync = ref.watch(recentActivityProvider);

    Widget aviso(String texto) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            texto,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.textoSecundario(context),
            ),
          ),
        );

    return activityAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: LinearProgressIndicator(minHeight: 3),
      ),
      error: (_, _) => aviso(l10n.couldNotLoadActivity),
      data: (activities) {
        if (activities.isEmpty) return aviso(l10n.noRecentScans);

        final ultimos = activities.take(3).toList();

        return GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < ultimos.length; i++)
                _FilaDeEscaneo(
                  actividad: ultimos[i],
                  primero: i == 0,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FilaDeEscaneo extends StatelessWidget {
  const _FilaDeEscaneo({required this.actividad, required this.primero});

  final Map<String, dynamic> actividad;
  final bool primero;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final ticket = actividad['tickets'];
    final comprador =
        ticket != null ? ticket['buyer_name'] ?? l10n.unknown : l10n.unknown;
    final resultado = ((actividad['result'] as String?) ?? '').toLowerCase();
    final aprobado = resultado == 'allowed' ||
        resultado == 'valid' ||
        resultado == 'granted';

    final marca = actividad['scanned_at'] as String?;
    final hora =
        marca != null ? DateTime.parse(marca).toLocal() : DateTime.now();
    final horaTexto = '${hora.hour.toString().padLeft(2, '0')}:'
        '${hora.minute.toString().padLeft(2, '0')}';

    final color = aprobado
        ? AppTheme.acentoTexto(context)
        : AppTheme.peligroTexto(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          top: primero
              ? BorderSide.none
              : BorderSide(color: AppTheme.bordeSuave(context)),
          // La barra izquierda dice el veredicto sin gastar una palabra.
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(horaTexto, style: AppTheme.dato(context, size: 12.5)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comprador,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.texto(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.activityMethodLine(
                    (actividad['method'] as String? ?? l10n.scanned)
                        .toUpperCase(),
                    ticket?['users_profile']?['display_name'] ??
                        l10n.systemUser,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.dato(
                    context,
                    size: 10,
                    peso: FontWeight.w400,
                    color: AppTheme.textoApagado(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(aprobado ? Icons.check : Icons.close, size: 15, color: color),
        ],
      ),
    );
  }
}
