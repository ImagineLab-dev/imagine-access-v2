import 'package:flutter/material.dart';
import 'package:imagine_access/core/ui/responsive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../events/presentation/event_state.dart';
import 'dashboard_components.dart';

class RrppDashboardView extends ConsumerWidget {
  final Map<String, dynamic> metrics;

  const RrppDashboardView({super.key, required this.metrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // EXTRACT METRICS
    final int paidCount = metrics['paid_tickets_count'] ?? 0;
    final int paidToday = metrics['paid_tickets_today'] ?? 0;
    final int totalIssued = metrics['total_issued'] ?? 0;
    final int invitesCount = metrics['invitations_count'] ?? 0;

    final int quotaStd = metrics['quota_standard'] ?? 0;
    final int quotaStdUsed = metrics['quota_standard_used'] ?? 0;
    final int quotaStdRem = metrics['remaining_standard'] ?? 0;

    final int quotaGuest = metrics['quota_guest'] ?? 0;
    final int quotaGuestUsed = metrics['quota_guest_used'] ?? 0;
    final int quotaGuestRem = metrics['remaining_guest'] ?? 0;

    final int totalEntered = metrics['total_scanned'] ?? 0;
    final int toEnter = totalIssued - totalEntered;

    // Progress calculations
    final double stdProgress = quotaStd > 0 ? (quotaStdUsed / quotaStd) : 0.0;
    final double guestProgress = quotaGuest > 0 ? (quotaGuestUsed / quotaGuest) : 0.0;

    // Entered percentage
    final String enteredPercent = totalIssued > 0
        ? "${((totalEntered / totalIssued) * 100).toStringAsFixed(1)}%"
        : "0%";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: Responsive.columnas(context),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          // Estas tarjetas llevan una barra de progreso además del número.
          childAspectRatio:
              Responsive.proporcionTarjeta(context, alturaObjetivo: 150),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            EliteMetricCard(
              title: l10n.salesTitle.toUpperCase(),
              value: paidCount.toString(),
              subValue: "${l10n.today}: $paidToday",
              icon: Icons.confirmation_number_outlined,
              color: AppTheme.textoApagado(context),
              delay: 0,
            ),
            EliteMetricCard(
              title: l10n.totalIssued.toUpperCase(),
              value: totalIssued.toString(),
              subValue: "${l10n.paidShort}: $paidCount ${l10n.inviteShort}: $invitesCount",
              icon: Icons.all_inbox,
              color: AppTheme.textoApagado(context),
              delay: 100,
            ),
            EliteMetricCard(
              title: l10n.invitationsStandard.toUpperCase(),
              value: "$quotaStdUsed / $quotaStd",
              subValue: "${l10n.remaining}: $quotaStdRem",
              icon: Icons.people_outline,
              progress: stdProgress,
              delay: 200,
            ),
            EliteMetricCard(
              title: l10n.invitationsGuest.toUpperCase(),
              value: "$quotaGuestUsed / $quotaGuest",
              subValue: "${l10n.remaining}: $quotaGuestRem",
              icon: Icons.star_border,
              progress: guestProgress,
              delay: 300,
            ),
            EliteMetricCard(
              title: l10n.entered.toUpperCase(),
              value: totalEntered.toString(),
              subValue: enteredPercent,
              icon: Icons.qr_code_scanner,
              color: AppTheme.textoApagado(context),
              delay: 400,
            ),
            EliteMetricCard(
              title: l10n.toEnterTitle.toUpperCase(),
              value: toEnter.toString(),
              subValue: "${l10n.remaining}: $toEnter",
              icon: Icons.hourglass_empty_rounded,
              color: AppTheme.textoApagado(context),
              delay: 500,
            ),
          ],
        ),
        const SizedBox(height: 32),
        QuickActions(
          actions: [
            // "Ver todos los tickets" salió: es el cuarto botón de la barra
            // de abajo. Emitir es lo único que la barra no puede hacer.
            ActionItem(
              l10n.newTicketInvitation.toUpperCase(),
              Icons.confirmation_number,
              '/create_ticket',
              isPrimary: true,
            ),
          ],
          onActionBeforeNavigate: (action) =>
              _checkEventSelected(context, ref, action.route),
        ),
      ],
    );
  }

  bool _checkEventSelected(BuildContext context, WidgetRef ref, String route) {
    if (route == '/tickets') {
      return true;
    }

    final selectedEvent = ref.read(selectedEventProvider);
    if (selectedEvent == null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseSelectEvent)),
      );
      return false;
    }

    return true;
  }
}
