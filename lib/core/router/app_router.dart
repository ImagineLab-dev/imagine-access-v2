import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_roles.dart';
import '../platform/host.dart';
import '../ui/app_shell.dart';
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

/// Dónde aterriza alguien recién autenticado.
///
/// Existe como función y no repetido en dos lados porque antes lo estaba, y las
/// dos copias no coincidían: el router mandaba al panel de super-admin cuando se
/// entraba por ese subdominio, pero `login_screen.dart` hacía
/// `context.go('/dashboard')` a secas justo después de autenticar y pisaba la
/// decisión. El comentario del router decía "se aterriza en el panel" y no era
/// cierto — el super-admin entraba por su subdominio y caía en el panel de su
/// organización, sin ninguna señal de que existía otro lugar.
///
/// Quien no sea super-admin, o entre por el dominio principal, va al panel de
/// control como siempre.
String rutaTrasIngresar(String? role) =>
    esHostSuperAdmin && AppRoles.isSuperadmin(role) ? '/super-admin' : '/dashboard';

/// Le avisa al router que el estado de sesión cambió, para que vuelva a
/// evaluar las redirecciones.
///
/// Es la pieza que permite que el router se construya UNA vez. Sin esto había
/// que reconstruirlo entero para que las redirecciones vieran la sesión nueva,
/// y reconstruirlo es justamente el problema: ver más abajo.
class _CambioDeSesion extends ChangeNotifier {
  _CambioDeSesion(Ref ref) {
    // El rol se deriva de los otros dos, pero se escucha igual: cambia solo
    // cuando `ensure_profile` sincroniza los metadatos, que es después de que
    // la sesión ya está puesta.
    ref.listen(userProvider, (_, _) => notifyListeners());
    ref.listen(userRoleProvider, (_, _) => notifyListeners());
    ref.listen(deviceProvider, (_, _) => notifyListeners());
  }
}

/// El router, construido una sola vez para toda la vida de la app.
///
/// Antes este proveedor hacía `ref.watch` de la sesión, el rol y el
/// dispositivo, y devolvía un `GoRouter` NUEVO con cada cambio. Como
/// `MaterialApp.router` lo consume con `ref.watch`, Flutter veía otro
/// `routerConfig`, desmontaba el navegador y lo volvía a montar desde
/// `initialLocation: '/welcome'`.
///
/// Eso se veía como la pantalla de inicio cargando varias veces al entrar, y
/// no era una sola: `loginEmail` guarda la sesión al autenticar y otra vez
/// después de refrescarla para leer el rol ya sincronizado, así que un login
/// normal rearmaba la navegación dos veces —aparecía la pantalla de bienvenida
/// entre medio de cada una— antes de aterrizar donde correspondía.
///
/// Ahora el router es el mismo objeto siempre y las redirecciones leen el
/// estado en el momento de correr, con `ref.read`. Lo que cambia es solo hacia
/// dónde redirige, que es lo que tenía que cambiar desde el principio.
final routerProvider = Provider<GoRouter>((ref) {
  final cambioDeSesion = _CambioDeSesion(ref);
  ref.onDispose(cambioDeSesion.dispose);

  return GoRouter(
    initialLocation: '/welcome',
    refreshListenable: cambioDeSesion,
    redirect: (context, state) {
      // Con `ref.read` y no capturado afuera: si se leyera al construir, el
      // router quedaría decidiendo para siempre con la sesión que había en el
      // arranque, que es ninguna.
      final user = ref.read(userProvider);
      final role = ref.read(userRoleProvider);
      final deviceSession = ref.read(deviceProvider);

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
        return rutaTrasIngresar(role);
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
          // `?registrar=1` abre directo el formulario de registro. Es el
          // destino de "Probar gratis" de la landing: antes ese botón caía en
          // el login, pidiéndole una contraseña a alguien que nunca tuvo
          // cuenta —el abandono más predecible del embudo—. El registro es
          // solo de admin; un dispositivo de puerta no se registra, así que
          // registrar implica la pestaña admin.
          final registrar = state.uri.queryParameters['registrar'] == '1';
          final initialTabIndex = (mode == AppRoles.door && !registrar) ? 1 : 0;
          return LoginScreen(
            initialTabIndex: initialTabIndex,
            initialRegister: registrar,
          );
        },
      ),
      // --- Pantallas CON armazón (cabecera global + barra inferior) ---
      //
      // Son los destinos a los que se vuelve todo el tiempo durante un evento.
      // Van dentro de un ShellRoute para que la cabecera y la barra inferior se
      // construyan UNA vez y no se desmonten al cambiar de destino: si cada
      // pantalla las dibujara por su cuenta, al tocar la barra se vería
      // parpadear la propia barra.
      //
      // Lo que queda AFUERA es lo que se abre encima y se cierra: el asistente
      // de ticket, crear evento, las estadísticas y los enlaces profundos.
      // Esas traen su propia barra con el botón de volver, que es lo que
      // corresponde a una pantalla de la que se sale.
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(ubicacion: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/events',
            builder: (context, state) => const EventSelectorScreen(),
          ),
          GoRoute(
            path: '/scanner',
            builder: (context, state) => const ScannerScreen(),
          ),
          GoRoute(
            path: '/tickets',
            builder: (context, state) => const TicketListScreen(),
          ),
          GoRoute(
            path: '/document_search',
            builder: (context, state) => const DocumentSearchScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/subscription',
            builder: (context, state) => const SubscriptionScreen(),
          ),
          GoRoute(
            path: '/super-admin',
            builder: (context, state) => const SuperAdminScreen(),
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
        path: '/create_ticket',
        builder: (context, state) => const CreateTicketWizard(),
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
    ],
  );
});
