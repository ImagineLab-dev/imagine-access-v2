import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../features/billing/data/subscription_repository.dart';

/// Aviso del estado de la suscripción.
///
/// Solo aparece cuando hay algo que decir: prueba por terminar, suscripción
/// vencida o cuenta suspendida. Una organización al día no ve nada — un cartel
/// permanente que dice "todo bien" se vuelve invisible y le roba el lugar al
/// que sí importa.
class SubscriptionBanner extends ConsumerWidget {
  const SubscriptionBanner({super.key});

  /// Faltando más de esto, no se avisa nada: recordarle a alguien todos los
  /// días que le quedan 12 de prueba es ruido, no ayuda.
  static const _avisarDesdeDias = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sub = ref.watch(subscriptionProvider).valueOrNull;

    if (sub == null || sub.sinVencimiento) return const SizedBox.shrink();

    final (mensaje, color, icono) = switch (sub) {
      _ when sub.suspendida => (
          l10n.organizationSuspended,
          const Color(0xFFEF4444),
          Icons.block_outlined,
        ),
      _ when sub.vencida => (
          l10n.subscriptionExpired,
          const Color(0xFFEF4444),
          Icons.error_outline,
        ),
      _ when sub.enPrueba && (sub.daysLeft ?? 99) <= 0 => (
          l10n.trialEndsToday,
          const Color(0xFFF59E0B),
          Icons.schedule_outlined,
        ),
      _ when sub.enPrueba && (sub.daysLeft ?? 99) <= _avisarDesdeDias => (
          l10n.trialDaysLeft(sub.daysLeft!),
          const Color(0xFFF59E0B),
          Icons.schedule_outlined,
        ),
      _ => (null, Colors.transparent, Icons.info_outline),
    };

    if (mensaje == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ),
          // La suspensión manual no se resuelve pagando: la levanta el
          // super-admin. Ofrecer "activar suscripción" ahí mandaría a alguien a
          // pagar algo que no le va a devolver el acceso.
          if (!sub.suspendida) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _mostrarPlanes(context, l10n),
              child: Text(l10n.subscribeNow,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  /// Precios, mientras el cobro automático por dLocal no esté conectado.
  void _mostrarPlanes(BuildContext context, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.subscribeNow),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(l10n.planMonthlyPrice),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(l10n.planAnnualPrice),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}
