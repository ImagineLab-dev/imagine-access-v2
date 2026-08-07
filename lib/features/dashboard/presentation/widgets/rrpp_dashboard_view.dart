import 'package:flutter/material.dart';
import 'package:imagine_access/core/ui/responsive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
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

    // Los TRES cupos del RRPP. Antes el panel mostraba solo standard y VIP
    // (guest): el cupo de invitación se asignaba en la pantalla de equipo pero
    // no se veía acá, porque la RPC `get_staff_dashboard` no lo devolvía. Los
    // nombres van unificados con esa pantalla —Standard / Invitación / VIP—.
    final int quotaStd = metrics['quota_standard'] ?? 0;
    final int quotaStdUsed = metrics['quota_standard_used'] ?? 0;
    final int quotaStdRem = metrics['remaining_standard'] ?? 0;

    final int quotaInv = metrics['quota_invitation'] ?? 0;
    final int quotaInvUsed = metrics['quota_invitation_used'] ?? 0;
    final int quotaInvRem = metrics['remaining_invitation'] ?? 0;

    final int quotaVip = metrics['quota_guest'] ?? 0;
    final int quotaVipUsed = metrics['quota_guest_used'] ?? 0;
    final int quotaVipRem = metrics['remaining_guest'] ?? 0;

    final int totalEntered = metrics['total_scanned'] ?? 0;
    final int toEnter = totalIssued - totalEntered;

    // Progress calculations
    final double stdProgress = quotaStd > 0 ? (quotaStdUsed / quotaStd) : 0.0;
    final double invProgress = quotaInv > 0 ? (quotaInvUsed / quotaInv) : 0.0;
    final double vipProgress = quotaVip > 0 ? (quotaVipUsed / quotaVip) : 0.0;

    // Entered percentage
    final String enteredPercent = totalIssued > 0
        ? "${((totalEntered / totalIssued) * 100).toStringAsFixed(1)}%"
        : "0%";

    // Sin sección de acciones rápidas: "Nuevo ticket" y "Ver tickets" viven en
    // la barra de abajo (Ver tickets ES la pestaña Tickets), así que repetirlas
    // acá era ocupar media pantalla con lo que ya está a un dedo.
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: Responsive.columnas(context),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      // Estas tarjetas llevan una barra de progreso además del número.
      // 122 y no 150: seis tarjetas a 150 ocupaban casi toda la pantalla en
      // el teléfono. El contenido —etiqueta, número, detalle y barra— entra en
      // 113, así que 122 deja aire sin estirar.
      childAspectRatio:
          Responsive.proporcionTarjeta(context, alturaObjetivo: 122),
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
          title: l10n.cupoStandard.toUpperCase(),
          value: "$quotaStdUsed / $quotaStd",
          subValue: "${l10n.remaining}: $quotaStdRem",
          icon: Icons.people_outline,
          progress: stdProgress,
          delay: 200,
        ),
        EliteMetricCard(
          title: l10n.cupoInvitacion.toUpperCase(),
          value: "$quotaInvUsed / $quotaInv",
          subValue: "${l10n.remaining}: $quotaInvRem",
          icon: Icons.mail_outline,
          progress: invProgress,
          delay: 300,
        ),
        EliteMetricCard(
          title: l10n.cupoVip.toUpperCase(),
          value: "$quotaVipUsed / $quotaVip",
          subValue: "${l10n.remaining}: $quotaVipRem",
          icon: Icons.star_border,
          progress: vipProgress,
          delay: 400,
        ),
        EliteMetricCard(
          title: l10n.entered.toUpperCase(),
          value: totalEntered.toString(),
          subValue: enteredPercent,
          icon: Icons.qr_code_scanner,
          color: AppTheme.textoApagado(context),
          delay: 500,
        ),
        EliteMetricCard(
          title: l10n.toEnterTitle.toUpperCase(),
          value: toEnter.toString(),
          subValue: "${l10n.remaining}: $toEnter",
          icon: Icons.hourglass_empty_rounded,
          color: AppTheme.textoApagado(context),
          delay: 600,
        ),
      ],
    );
  }
}
