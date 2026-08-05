import 'package:flutter/material.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/subscription_banner.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_roles.dart';
import '../../events/presentation/event_state.dart';
import '../../events/data/event_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/dashboard_repository.dart';
import 'widgets/admin_dashboard_view.dart';
import 'widgets/rrpp_dashboard_view.dart';
import 'widgets/door_dashboard_view.dart';
import 'widgets/recent_activity_list.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final role = ref.watch(userRoleProvider);
    final isDevice = ref.watch(deviceProvider) != null;
    final displayRole = isDevice ? AppRoles.door : role;

    // Start Realtime Listeners
    ref.watch(dashboardRealtimeProvider);

    return GlassScaffold(
      // El selector de evento ya NO va en la barra superior.
      //
      // Ahí competía por el ancho con el título y ganaba: "Panel de Control"
      // se cortaba en "Panel de Co...". Y el nombre del evento tampoco entraba
      // completo, porque el chip tenía un ancho fijo de 160 px. Dos textos
      // truncados para no ocupar una línea propia.
      //
      // Ahora el título tiene la barra entera y el selector baja al cuerpo,
      // como una tarjeta fina de borde a borde: se lee el nombre completo del
      // evento y se toca más fácil.
      titulo: l10n.navPanel,
      body: RefreshIndicator(
        onRefresh: () async {
          final refresh = ref.refresh(dashboardMetricsProvider.future);
          ref.invalidate(recentActivityProvider);
          await refresh;
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          // El tope de ancho lo aplica GlassScaffold para todas las pantallas.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selector de evento, de borde a borde.
              const _SelectorDeEvento(),
              const SizedBox(height: 16),

              // Aviso de suscripción. Se dibuja solo si hay algo que decir
              // (prueba por vencer, vencida o suspendida); si no, ocupa cero.
              const SubscriptionBanner(),

              // ROLE-BASED DASHBOARD CONTENT
              Consumer(
                builder: (context, ref, _) {
                  final metricsAsync = ref.watch(dashboardMetricsProvider);

                  return metricsAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (err, _) => _ErrorView(
                      error: l10n.error,
                      onRetry: () => ref.refresh(dashboardMetricsProvider),
                    ),
                    data: (metrics) {
                      if (metrics['error'] != null) {
                        return _ErrorBanner(message: metrics['error']);
                      }

                      // `superadmin` tiene que ver la vista de admin.
                      //
                      // Sin este caso caía en el `_` y le tocaba la vista de
                      // PUERTA: el dueño de la plataforma entraba a su propia
                      // organización y veía la pantalla de un escáner. Es el
                      // mismo descuido que tenía `is_admin()` en la base —el
                      // rol se agregó después y los repartos por rol nunca lo
                      // contemplaron.
                      return switch (displayRole) {
                        AppRoles.admin ||
                        AppRoles.superadmin =>
                          AdminDashboardView(metrics: metrics),
                        AppRoles.rrpp => RrppDashboardView(metrics: metrics),
                        _ => DoorDashboardView(metrics: metrics),
                      };
                    },
                  );
                },
              ),
              const SizedBox(height: 32),
              // RECENT ACTIVITY
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.recentActivity.toUpperCase(),
                    style: AppTheme.titular(context, size: 16),
                  ),
                  const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 8),
              const RecentActivityList(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Column(
        children: [
          Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.error, size: 40),
          const SizedBox(height: 8),
          Text(l10n.error),
          Text(error, style: const TextStyle(fontSize: 10, color: AppTheme.accentPurple)),
          TextButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(message.isNotEmpty ? message : l10n.error,
          style: const TextStyle(color: AppTheme.accentOrange)),
    );
  }
}

/// Selector de evento del panel, de borde a borde.
///
/// Vivía como `ActionChip` dentro de `actions:` de la barra superior. Ahí el
/// título y el nombre del evento se peleaban el mismo renglón y los dos
/// perdían: el título quedaba en "Panel de Co..." y el evento estaba encerrado
/// en un `SizedBox(width: 160)` que cortaba cualquier nombre medianamente
/// largo. Acá abajo tiene el ancho completo, así que ambos se leen enteros.
///
/// Sigue siendo una fila fina —una línea de alto— para no robarle espacio a las
/// métricas, que son lo que se viene a mirar.
class _SelectorDeEvento extends ConsumerWidget {
  const _SelectorDeEvento();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    ref.watch(eventsProvider); // Dispara la carga de eventos.
    final selectedEvent = ref.watch(selectedEventProvider);

    // Si el evento elegido ya no está en la lista, se descarta la selección.
    ref.listen<AsyncValue<List<Map<String, dynamic>>>>(
      eventsProvider,
      (prev, next) {
        if (next.hasValue && next.value != null) {
          ref.read(selectedEventProvider.notifier).validate(next.value!);
        }
      },
    );

    final hayEvento = selectedEvent != null;

    // Selector de evento: la caja recta con chevron del diseño. El nombre va
    // en mono porque es el dato sobre el que opera todo el resto del panel, y
    // sin evento elegido el borde queda apagado para que se note que falta.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.selectEvent.toUpperCase(),
          style: AppTheme.etiqueta(context, size: 10),
        ),
        const SizedBox(height: 6),
        Material(
          color: AppTheme.panel(context),
          child: InkWell(
            onTap: () => context.push('/events'),
            splashFactory: NoSplash.splashFactory,
            highlightColor: AppTheme.hover(context),
            child: Container(
              // 48 px de alto: fila fina, pero por encima del objetivo táctil.
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: hayEvento
                      ? AppTheme.borde(context)
                      : AppTheme.bordeSuave(context),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 15,
                      color: hayEvento
                          ? AppTheme.acentoTexto(context)
                          : AppTheme.textoApagado(context)),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      selectedEvent?['name'] ?? l10n.selectEvent,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.dato(
                        context,
                        size: 13,
                        color: hayEvento
                            ? AppTheme.texto(context)
                            : AppTheme.textoApagado(context),
                      ),
                    ),
                  ),
                  // Indica que se toca para cambiar. Sin esto la fila se lee
                  // como una etiqueta y no como un control.
                  Icon(Icons.expand_more,
                      size: 18, color: AppTheme.textoSecundario(context)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
