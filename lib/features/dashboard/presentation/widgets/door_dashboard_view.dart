import 'package:flutter/material.dart';
import 'package:imagine_access/core/ui/responsive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import 'dashboard_components.dart';

class DoorDashboardView extends ConsumerWidget {
  final Map<String, dynamic> metrics;

  const DoorDashboardView({super.key, required this.metrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: Responsive.columnas(context),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: Responsive.proporcionTarjeta(context),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            MetricCard(
              title: l10n.totalTickets,
              value: (metrics['total_sold'] ?? 0).toString(),
              icon: Icons.confirmation_number_outlined,
              color: AppTheme.textoApagado(context),
              delay: 0,
            ),
            MetricCard(
              title: l10n.scanned.toUpperCase(),
              value: (metrics['scanned'] ?? 0).toString(),
              icon: Icons.qr_code_scanner,
              color: AppTheme.textoApagado(context),
              delay: 100,
            ),
            MetricCard(
              title: l10n.manualUpper,
              value: (metrics['scanned_manual'] ?? 0).toString(),
              icon: Icons.back_hand,
              color: AppTheme.textoApagado(context),
              delay: 150,
            ),
            MetricCard(
              title: l10n.toEnter.toUpperCase(),
              value: (metrics['valid'] ?? 0).toString(),
              icon: Icons.hourglass_empty_rounded,
              color: AppTheme.textoApagado(context),
              delay: 200,
            ),
            MetricCard(
              title: l10n.guestEntry.toUpperCase(),
              value:
                  "${metrics['invitations_scanned'] ?? 0} / ${metrics['invitations_total'] ?? 0}",
              icon: Icons.people_outline_rounded,
              color: AppTheme.textoApagado(context),
              delay: 300,
            ),
            MetricCard(
              title: l10n.staff.toUpperCase(),
              value:
                  "${metrics['staff_entered'] ?? 0} / ${metrics['staff_created'] ?? 0}",
              icon: Icons.badge_outlined,
              color: AppTheme.textoApagado(context),
              delay: 400,
            ),
            MetricCard(
              title: l10n.guests.toUpperCase(),
              value:
                  "${metrics['guest_entered'] ?? 0} / ${metrics['guest_created'] ?? 0}",
              icon: Icons.star_border,
              color: AppTheme.textoApagado(context),
              delay: 500,
            ),
            MetricCard(
              title: l10n.normal.toUpperCase(),
              value:
                  "${metrics['standard_entered'] ?? 0} / ${metrics['standard_created'] ?? 0}",
              icon: Icons.people_outline,
              color: AppTheme.textoApagado(context),
              delay: 600,
            ),
            MetricCard(
              title: 'PROMO',
              value:
                  "${metrics['promo_entered'] ?? 0} / ${metrics['promo_created'] ?? 0}",
              icon: Icons.local_offer,
              color: AppTheme.textoApagado(context),
              delay: 700,
            ),
          ],
        ),
        // Sin acciones rápidas.
        //
        // Las dos que había —escanear y buscar por documento— son exactamente
        // los dos destinos que el dispositivo de puerta tiene en su barra de
        // abajo, con el dedo encima. Repetirlas acá le hacía leer cuatro
        // botones para elegir entre dos.
      ],
    );
  }
}
