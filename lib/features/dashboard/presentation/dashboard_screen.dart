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
import '../../profile/data/profile_repository.dart';
import 'widgets/admin_dashboard_view.dart';
import 'widgets/rrpp_dashboard_view.dart';
import 'widgets/door_dashboard_view.dart';
import 'widgets/recent_activity_list.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
      appBar: AppBar(
        title: Text(l10n.dashboard),
        centerTitle: false,
      ),
      drawer: _buildDrawer(context, ref, isDark),
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
              _SelectorDeEvento(isDark: isDark),
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
                    l10n.recentActivity,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
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

  Widget _buildDrawer(BuildContext context, WidgetRef ref, bool isDark) {
    final l10n = AppLocalizations.of(context);
    final role = ref.watch(userRoleProvider);
    final isDevice = ref.watch(deviceProvider) != null;
    final isDoor = isDevice || role == AppRoles.door;

    return Drawer(
      backgroundColor: isDark ? const Color(0xFF0B1220) : Colors.white,
      child: Column(
        children: [
          DrawerHeader(
            decoration:
                BoxDecoration(color: AppTheme.neonBlue.withValues(alpha: 0.1)),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Foto del usuario si la cargó; si no, el rayo de la marca.
                  // Los dispositivos de puerta entran con alias y PIN, sin
                  // cuenta de usuario, así que nunca tienen foto.
                  Consumer(
                    builder: (context, ref, _) {
                      final avatar = ref
                          .watch(profileProvider)
                          .valueOrNull
                          ?.avatarUrl;

                      if (avatar == null || avatar.isEmpty) {
                        return const Icon(Icons.flash_on,
                            size: 48, color: AppTheme.neonBlue);
                      }

                      return GestureDetector(
                        onTap: () {
                          context.pop();
                          context.push('/profile');
                        },
                        child: CircleAvatar(
                          radius: 30,
                          backgroundColor:
                              AppTheme.neonBlue.withValues(alpha: 0.2),
                          backgroundImage: NetworkImage(avatar),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Consumer(
                    builder: (context, ref, _) {
                      final org = ref.watch(userOrganizationProvider);
                      if (org == null) return const SizedBox.shrink();
                      return Text(
                        org.name,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.dashboard,
                color: isDark ? Colors.white70 : Colors.black87),
            title: Text(l10n.dashboard,
                style:
                    TextStyle(color: isDark ? Colors.white : Colors.black87)),
            onTap: () => context.pop(),
          ),
          if (!isDoor) ...[
            // Solo para superadmin: administra el conjunto de organizaciones,
            // no una en particular.
            if (AppRoles.isSuperadmin(role))
              ListTile(
                leading: Icon(Icons.admin_panel_settings_outlined,
                    color: AppTheme.neonBlue),
                title: Text(l10n.superAdmin,
                    style: TextStyle(
                        color: AppTheme.neonBlue,
                        fontWeight: FontWeight.bold)),
                onTap: () {
                  context.pop();
                  context.push('/super-admin');
                },
              ),
            ListTile(
              leading: Icon(Icons.person_outline,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: Text(l10n.profile,
                  style:
                      TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                context.pop();
                context.push('/profile');
              },
            ),
            ListTile(
              leading: Icon(Icons.credit_card_outlined,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: Text(l10n.subscription,
                  style:
                      TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                context.pop();
                context.push('/subscription');
              },
            ),
            ListTile(
              leading: Icon(Icons.event,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: Text(l10n.events,
                  style:
                      TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                context.pop();
                context.push('/events');
              },
            ),
            ListTile(
              leading: Icon(Icons.settings,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: Text(l10n.settings,
                  style:
                      TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                context.pop();
                context.push('/settings');
              },
            ),
          ],
          const Spacer(),
          const Divider(),
          ListTile(
            leading:
                Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text(l10n.logout,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/welcome');
            },
          ),
          const SizedBox(height: 16),
        ],
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
          Text(error, style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
          style: const TextStyle(color: Colors.red)),
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
  const _SelectorDeEvento({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

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
    final acento = theme.colorScheme.primary;
    final colorTexto =
        hayEvento ? acento : (isDark ? Colors.white70 : Colors.black54);

    return Material(
      color: hayEvento
          ? acento.withValues(alpha: 0.08)
          : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/events'),
        child: Container(
          // 48 px de alto: fila fina, pero por encima del objetivo táctil.
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hayEvento
                  ? acento.withValues(alpha: 0.45)
                  : (isDark ? Colors.white24 : Colors.black12),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 17, color: colorTexto),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  selectedEvent?['name'] ?? l10n.selectEvent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorTexto,
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
              ),
              // Indica que se toca para cambiar. Sin esto la fila se lee como
              // una etiqueta y no como un control.
              Icon(Icons.unfold_more, size: 18, color: colorTexto.withValues(alpha: .7)),
            ],
          ),
        ),
      ),
    );
  }
}
