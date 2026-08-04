import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../../core/platform/abrir_url.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/utils/error_handler.dart';
import '../data/subscription_repository.dart';
import '../../../core/platform/meta.dart';

/// Estado de la cuenta y contratación.
///
/// Existe como pantalla propia y no solo como aviso: el aviso aparece cuando
/// algo anda mal, así que quien quiere pagar antes de que se le acabe el cupo
/// —o solo quiere ver cuánto le queda— no tenía a dónde ir.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  /// Que ViewContent se mande una sola vez, aunque la pantalla se reconstruya.
  bool _viewContentEnviado = false;

  /// Marca a Meta que alguien miró los planes: es el paso previo a contratar.
  ///
  /// NO se dispara para un cliente que ya paga y está al día. Entra a esta
  /// pantalla a ver su estado o su fecha de renovación, no a comprar, y mandar
  /// ese evento le enseña al optimizador de la campaña a buscar gente que ya
  /// es cliente. Un trial, un vencido o un cancelado SÍ son señal: están a un
  /// paso de pagar.
  ///
  /// Va acá y no en `initState` porque el estado de la suscripción carga
  /// asíncrono: en `initState` todavía no se sabe si es cliente pago.
  void _marcarVistaDePlanes(Subscription sub) {
    if (_viewContentEnviado) return;
    _viewContentEnviado = true;

    final esClientePagoAlDia = !sub.enPrueba && sub.isActive && !sub.cancelada;
    if (esClientePagoAlDia) return;

    eventoMeta('ViewContent', valor: 25, moneda: 'USD');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final estado = ref.watch(subscriptionProvider);

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.subscription)),
      body: estado.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.errorGeneric)),
        data: (sub) {
          if (sub == null) return Center(child: Text(l10n.errorGeneric));

          // Recién acá se sabe si es cliente pago o prospecto.
          _marcarVistaDePlanes(sub);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(subscriptionProvider),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _Estado(sub: sub, l10n: l10n),
                const SizedBox(height: 16),
                if (sub.freeTicketsLimit != null && sub.enPrueba) ...[
                  _Cupo(sub: sub, l10n: l10n),
                  const SizedBox(height: 16),
                ],
                _Planes(sub: sub, l10n: l10n, ref: ref),

                // Solo con suscripción paga y vigente. No se ofrece dar de baja
                // algo que no existe, ni se repite el botón a quien ya lo usó.
                if (!sub.enPrueba && !sub.cancelada && sub.expiresAt != null) ...[
                  const SizedBox(height: 24),
                  _BajaDeSuscripcion(sub: sub, l10n: l10n, ref: ref),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({required this.sub, required this.l10n});

  final Subscription sub;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final (texto, color) = switch (sub) {
      _ when sub.suspendida => (l10n.statusSuspended, const Color(0xFFEF4444)),
      _ when sub.vencida => (l10n.statusExpired, const Color(0xFFEF4444)),
      _ when sub.cupoAgotado => (l10n.statusQuotaExhausted, const Color(0xFFEF4444)),
      _ when sub.enPrueba => (l10n.statusTrial, const Color(0xFFF59E0B)),
      // Antes de "activa": una suscripción dada de baja SIGUE vigente hasta el
      // vencimiento, así que el estado verde sería cierto y engañoso a la vez.
      // Lo que la persona necesita saber es que no se renueva.
      _ when sub.cancelada => (l10n.subscriptionCancelled, const Color(0xFFF59E0B)),
      _ => (l10n.statusActive, const Color(0xFF22C55E)),
    };

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(texto,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          if (sub.expiresAt != null) ...[
            const SizedBox(height: 12),
            // "Se renueva el X" es falso si ya pidió la baja. Mismo dato, otra
            // frase, porque significa lo contrario.
            Text(
              sub.cancelada
                  ? l10n.subscriptionCancelledUntil(_fecha(sub.expiresAt!))
                  : l10n.renewsOn(_fecha(sub.expiresAt!)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (sub.suspendedReason != null) ...[
            const SizedBox(height: 12),
            Text(sub.suspendedReason!,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  static String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _Cupo extends StatelessWidget {
  const _Cupo({required this.sub, required this.l10n});

  final Subscription sub;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final limite = sub.freeTicketsLimit!;
    final usados = sub.freeTicketsUsed.clamp(0, limite);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.freeTicketsTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: limite == 0 ? 1 : usados / limite,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(
                usados >= limite ? const Color(0xFFEF4444) : AppTheme.neonBlue,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(l10n.freeTicketsUsedOf(usados, limite),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          // Que el cupo no se recupere anulando tickets tiene que estar dicho
          // antes de que alguien lo intente y crea que el sistema falla.
          Text(l10n.freeTicketsNote,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Planes extends StatefulWidget {
  const _Planes({required this.sub, required this.l10n, required this.ref});

  final Subscription sub;
  final AppLocalizations l10n;
  final WidgetRef ref;

  @override
  State<_Planes> createState() => _PlanesState();
}

class _PlanesState extends State<_Planes> {
  String? _cargando;

  Future<void> _contratar(String plan) async {
    final l10n = widget.l10n;
    final mensajero = ScaffoldMessenger.of(context);

    // La pestaña se reserva ACÁ, todavía dentro del gesto del usuario. Pedir
    // primero el enlace al servidor y abrir después hace que el navegador la
    // bloquee sin aviso, y el botón parece no funcionar.
    final pestana = reservarPestana();

    // InitiateCheckout se manda desde acá, que es donde el usuario hace clic.
    // La compra en sí la reporta el servidor cuando dLocal confirma: el pago
    // sucede en su dominio y este código ya no corre ahí.
    eventoMeta('InitiateCheckout',
        valor: plan == 'annual' ? 250 : 25, moneda: 'USD');

    setState(() => _cargando = plan);
    try {
      final url = await widget.ref
          .read(subscriptionRepositoryProvider)
          .enlaceDePago(plan: plan);
      pestana.navegarA(url);
    } catch (_) {
      // Sin esto queda una pestaña en blanco abierta sin ninguna explicación.
      pestana.cerrar();
      mensajero.showSnackBar(
        SnackBar(content: Text(l10n.subscriptionLinkFailed)),
      );
    } finally {
      if (mounted) setState(() => _cargando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.choosePlan,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.planUnlimitedNote,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          _OpcionPlan(
            titulo: l10n.planMonthlyPrice,
            icono: Icons.calendar_month_outlined,
            cargando: _cargando == 'monthly',
            deshabilitado: _cargando != null,
            onTap: () => _contratar('monthly'),
          ),
          const SizedBox(height: 10),
          _OpcionPlan(
            titulo: l10n.planAnnualPrice,
            subtitulo: l10n.planAnnualSaving,
            icono: Icons.workspace_premium_outlined,
            destacado: true,
            cargando: _cargando == 'annual',
            deshabilitado: _cargando != null,
            onTap: () => _contratar('annual'),
          ),
          const SizedBox(height: 14),
          Text(l10n.paymentHandledBy,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _OpcionPlan extends StatelessWidget {
  const _OpcionPlan({
    required this.titulo,
    required this.icono,
    required this.onTap,
    this.subtitulo,
    this.destacado = false,
    this.cargando = false,
    this.deshabilitado = false,
  });

  final String titulo;
  final String? subtitulo;
  final IconData icono;
  final VoidCallback onTap;
  final bool destacado;
  final bool cargando;
  final bool deshabilitado;

  @override
  Widget build(BuildContext context) {
    final borde = destacado ? AppTheme.neonBlue : Colors.white24;

    return Opacity(
      opacity: deshabilitado && !cargando ? 0.5 : 1,
      child: InkWell(
        onTap: deshabilitado ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: borde, width: destacado ? 1.6 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icono, color: destacado ? AppTheme.neonBlue : null),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (subtitulo != null)
                      Text(subtitulo!,
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (cargando)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.open_in_new, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Baja del cobro recurrente.
///
/// Va al final de la pantalla y sin destacarse: es una salida, no una acción que
/// haya que empujar. Pero está a la vista y en la pantalla donde uno la busca —
/// esconderla obliga a la persona a llamar al banco a desconocer el cargo, que
/// es la misma baja pero con un contracargo y una relación rota.
class _BajaDeSuscripcion extends StatefulWidget {
  const _BajaDeSuscripcion({
    required this.sub,
    required this.l10n,
    required this.ref,
  });

  final Subscription sub;
  final AppLocalizations l10n;
  final WidgetRef ref;

  @override
  State<_BajaDeSuscripcion> createState() => _BajaDeSuscripcionState();
}

class _BajaDeSuscripcionState extends State<_BajaDeSuscripcion> {
  bool _enviando = false;

  String get _hasta => _Estado._fecha(widget.sub.expiresAt!);

  Future<void> _confirmar() async {
    final l10n = widget.l10n;

    final acepta = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cancelSubscriptionConfirm),
        content: Text(l10n.cancelSubscriptionConfirmBody(_hasta)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.cancelSubscriptionAction,
                style: const TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (acepta != true || !mounted) return;

    setState(() => _enviando = true);
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final hasta = await widget.ref
          .read(subscriptionRepositoryProvider)
          .cancelar();

      widget.ref.invalidate(subscriptionProvider);
      if (!mounted) return;
      mensajero.showSnackBar(SnackBar(
        content: Text(l10n.cancelSubscriptionDone(
            hasta == null ? _hasta : _Estado._fecha(hasta))),
      ));
    } catch (e) {
      if (!mounted) return;
      // El mensaje del servidor se muestra tal cual: distingue "no pudimos
      // cortar el cobro, tu suscripción sigue activa" de un fallo genérico, y
      // esa diferencia es justo la que la persona necesita.
      ErrorHandler.showErrorSnackBar(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.cancelSubscriptionExplain(_hasta),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _enviando ? null : _confirmar,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFEF4444),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          child: _enviando
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.cancelSubscription),
        ),
      ],
    );
  }
}
