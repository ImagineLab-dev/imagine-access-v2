import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_roles.dart';
import '../platform/host.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/tickets/presentation/create_ticket_wizard.dart';
import '../../features/scanner/presentation/scanner_screen.dart';
import '../../features/tickets/presentation/ticket_list_screen.dart';
import '../../features/events/presentation/event_selector_screen.dart';
import '../../features/events/presentation/create_event_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/billing/presentation/subscription_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/superadmin/presentation/super_admin_screen.dart';
import '../../features/settings/presentation/user_management_screen.dart';
import '../../features/settings/presentation/device_management_screen.dart';
import '../../features/settings/presentation/event_staff_screen.dart';
import '../../features/settings/presentation/legal_screen.dart';
import '../../features/scanner/presentation/document_search_screen.dart';
import '../../features/dashboard/presentation/stats_screen.dart';
import '../../features/tickets/presentation/ticket_deep_link_screen.dart';
import '../../features/events/presentation/event_deep_link_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final user = ref.watch(userProvider);
  final role = ref.watch(userRoleProvider);
  final deviceSession = ref.watch(deviceProvider);

  return GoRouter(
    initialLocation: '/welcome',
    redirect: (context, state) {
      final isPublicEntry = state.matchedLocation == '/login' ||
          state.matchedLocation == '/welcome' ||
          state.matchedLocation == '/verify-email' ||
          state.matchedLocation == '/reset-password';
      final isAuth = user != null || deviceSession != null;

      if (!isAuth && !isPublicEntry) return '/welcome';
      if (isAuth && isPublicEntry) {
        // Entrando por super-admin.imaginecloud.digital se aterriza en el
        // panel en vez del dashboard. Es comodidad, no seguridad: sin el rol
        // el guard de más abajo lo manda igual al dashboard.
        return esHostSuperAdmin && AppRoles.isSuperadmin(role)
            ? '/super-admin'
            : '/dashboard';
      }

      // Role Guards
      final path = state.matchedLocation;

      // El panel de super-admin es el unico nivel por encima de las
      // organizaciones. Se bloquea en el router ademas de en la base: las RPC
      // verifican is_superadmin() del lado del servidor, pero dejar la ruta
      // accesible mostraria una pantalla rota en vez de un rechazo claro.
      if (path.startsWith('/super-admin') &&
          !AppRoles.isSuperadmin(role)) {
        return '/dashboard';
      }

      // Admin only routes (Sub-settings and Create Event)
      final isAdminRoute = path.startsWith('/settings/users') ||
          path.startsWith('/create_event') ||
          path.startsWith('/settings/devices') ||
          path.startsWith('/event_staff') ||
          path.startsWith('/stats');

      if (isAdminRoute && !AppRoles.isAdmin(role)) {
        return '/dashboard'; // Redirect non-admins to dashboard
      }

      // Door/Scanner restricted routes
      if (deviceSession != null) {
        // Devices (Door Access) can see dashboard, scanner, document search and events
        final allowedForDevice = path == '/dashboard' ||
            path == '/scanner' ||
            path == '/document_search' ||
            path == '/events';
        if (!allowedForDevice) return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          final initialTabIndex = mode == AppRoles.door ? 1 : 0;
          return LoginScreen(initialTabIndex: initialTabIndex);
        },
      ),
      GoRoute(
        path: '/subscription',
        builder: (context, state) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          if (extra == null ||
              extra['email'] == null ||
              extra['displayName'] == null ||
              extra['organizationName'] == null) {
            return const LoginScreen();
          }
          return VerifyEmailScreen(
            email: extra['email'] as String,
            displayName: extra['displayName'] as String,
            organizationName: extra['organizationName'] as String,
            country: extra['country'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/events',
        builder: (context, state) => const EventSelectorScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/create_ticket',
        builder: (context, state) => const CreateTicketWizard(),
      ),
      GoRoute(
        path: '/scanner',
        builder: (context, state) => const ScannerScreen(),
      ),
      GoRoute(
        path: '/document_search',
        builder: (context, state) => const DocumentSearchScreen(),
      ),
      GoRoute(
        path: '/tickets',
        builder: (context, state) => const TicketListScreen(),
      ),
      GoRoute(
        path: '/ticket/:ticketId',
        builder: (context, state) => TicketDeepLinkScreen(
          ticketId: state.pathParameters['ticketId']!,
        ),
      ),
      GoRoute(
        path: '/event/:slug',
        builder: (context, state) => EventDeepLinkScreen(
          slug: state.pathParameters['slug']!,
        ),
      ),
      GoRoute(
        path: '/stats/:eventId',
        builder: (context, state) => StatsScreen(
          eventId: state.pathParameters['eventId']!,
        ),
      ),
      GoRoute(
        path: '/create_event',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CreateEventScreen(
            eventId: extra?['id'],
            initialData: extra,
          );
        },
      ),
      GoRoute(
        path: '/event_staff',
        builder: (context, state) => const EventStaffScreen(),
      ),
      GoRoute(
        path: '/super-admin',
        builder: (context, state) => const SuperAdminScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'users',
            builder: (context, state) => const UserManagementScreen(),
          ),
          GoRoute(
            path: 'devices',
            builder: (context, state) => const DeviceManagementScreen(),
          ),
          GoRoute(
            path: 'legal',
            builder: (context, state) => const LegalScreen(),
          ),
        ],
      ),
    ],
  );
});
