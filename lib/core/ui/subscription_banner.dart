import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../features/billing/data/subscription_repository.dart';
import '../platform/abrir_url.dart';

/// Aviso del estado de la suscripción.
///
/// Solo aparece cuando hay algo que decir: prueba por terminar, suscripción
/// vencida o cuenta suspendida. Una organización al día no ve nada — un cartel
/// permanente que dice "todo bien" se vuelve invisible y le roba el lugar al
/// que sí importa.
class SubscriptionBanner extends ConsumerWidget {
  const SubscriptionBanner({super.key});

  /// Quedando más que esto, no se avisa nada: recordarle a alguien que todavía
  /// tiene 14 tickets gratis es ruido, no ayuda.
  static const _avisarDesdeTickets = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sub = ref.watch(subscriptionProvider).valueOrNull;

    // Nada que decir: ni vence, ni tiene cupo que se esté agotando.
    if (sub == null) return const SizedBox.shrink();
    if (sub.sinVencimiento && sub.freeTicketsLeft == null) {
      return const SizedBox.shrink();
    }

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
      _ when sub.cupoAgotado => (
          l10n.freeTicketsExhausted,
          const Color(0xFFEF4444),
          Icons.confirmation_number_outlined,
        ),
      _ when (sub.freeTicketsLeft ?? 99) <= _avisarDesdeTickets => (
          l10n.freeTicketsLeft(sub.freeTicketsLeft!),
          const Color(0xFFF59E0B),
          Icons.confirmation_number_outlined,
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
              onPressed: () => _mostrarPlanes(context, ref, l10n),
              child: Text(l10n.subscribeNow,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  /// Elegir plan y salir al checkout de dLocal.
  void _mostrarPlanes(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text(l10n.subscribeNow),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(l10n.planMonthlyPrice),
              contentPadding: EdgeInsets.zero,
              onTap: () => _irAlPago(dialogo, ref, l10n, 'monthly'),
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(l10n.planAnnualPrice),
              contentPadding: EdgeInsets.zero,
              onTap: () => _irAlPago(dialogo, ref, l10n, 'annual'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _irAlPago(BuildContext dialogo, WidgetRef ref,
      AppLocalizations l10n, String plan) async {
    final navegador = Navigator.of(dialogo);
    final mensajero = ScaffoldMessenger.of(dialogo);

    // Reservada dentro del gesto: después del await el navegador ya no la deja
    // abrir y el botón queda sin efecto visible.
    final pestana = reservarPestana();

    try {
      final url = await ref
          .read(subscriptionRepositoryProvider)
          .enlaceDePago(plan: plan);
      navegador.pop();
      pestana.navegarA(url);
    } catch (e) {
      pestana.cerrar();
      navegador.pop();
      mensajero.showSnackBar(
        SnackBar(content: Text(l10n.subscriptionLinkFailed)),
      );
    }
  }
}
