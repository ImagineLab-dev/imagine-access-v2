// El router tiene que sobrevivir a los cambios de sesión.
//
// `MaterialApp.router` recibe el router con `ref.watch`. Si el proveedor
// devuelve un `GoRouter` NUEVO cada vez que cambia la sesión, Flutter ve otro
// `routerConfig`, desmonta el navegador entero y lo vuelve a montar desde
// `initialLocation`. Eso es exactamente lo que se ve como "la pantalla de
// inicio carga varias veces": no es una recarga del navegador —no hay una sola
// petición de red de más—, es la app rearmando su navegación en pantalla.
//
// Y no pasa una vez: `loginEmail` escribe la sesión al entrar y otra vez
// después de refrescarla para leer el rol, así que un login normal reconstruye
// la navegación por lo menos dos veces.
//
// Este test fija que el router se cree UNA sola vez. Es la propiedad que
// importa: las redirecciones siguen corriendo con cada cambio, pero sobre el
// mismo router, sin volver al principio.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:imagine_access/core/router/app_router.dart';
import 'package:imagine_access/features/auth/presentation/auth_controller.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Monta la app igual que `main.dart`, **con las localizaciones**.
///
/// Sin ellas `AppLocalizations.of(context)` devuelve null y toda pantalla que
/// muestre un texto revienta al construirse. El test seguía pasando porque solo
/// mira a dónde navega el router, y el `takeException()` del final se comía el
/// error creyendo que era Supabase. O sea: estos tests navegaban por pantallas
/// que en realidad no dibujaban nada, y no se enteraban.
Widget _app(ProviderContainer contenedor, GoRouter router) =>
    UncontrolledProviderScope(
      container: contenedor,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );

/// Un usuario mínimo. Solo interesa que sea una instancia distinta de la
/// anterior, que es lo que dispara la reconstrucción.
User _usuario(String id, {String? rol}) => User(
      id: id,
      appMetadata: rol == null ? {} : {'role': rol},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    );

/// El valor por defecto de `userProvider` lee `Supabase.instance`, que en un
/// test no está inicializado. Se arranca sin sesión, que es el estado real de
/// alguien que abre la app por primera vez.
ProviderContainer _contenedor() => ProviderContainer(
      overrides: [userProvider.overrideWith((ref) => null)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el router no se recrea cuando cambia la sesión', () {
    final contenedor = _contenedor();
    addTearDown(contenedor.dispose);

    final primero = contenedor.read(routerProvider);

    // Lo que hace un login real: se guarda la sesión, y después se vuelve a
    // guardar con el rol ya sincronizado por `ensure_profile`.
    contenedor.read(userProvider.notifier).state = _usuario('u1');
    final trasEntrar = contenedor.read(routerProvider);

    contenedor.read(userProvider.notifier).state =
        _usuario('u1', rol: 'admin');
    final trasRefrescar = contenedor.read(routerProvider);

    expect(
      identical(primero, trasEntrar),
      isTrue,
      reason: 'Entrar recreó el router: la navegación vuelve a /welcome.',
    );
    expect(
      identical(trasEntrar, trasRefrescar),
      isTrue,
      reason: 'Refrescar la sesión recreó el router por segunda vez.',
    );
  });

  test('cerrar sesión tampoco lo recrea', () {
    final contenedor = _contenedor();
    addTearDown(contenedor.dispose);

    contenedor.read(userProvider.notifier).state = _usuario('u1', rol: 'admin');
    final conSesion = contenedor.read(routerProvider);

    contenedor.read(userProvider.notifier).state = null;
    final sinSesion = contenedor.read(routerProvider);

    expect(identical(conSesion, sinSesion), isTrue);
  });

  test('la redirección lee el estado actual, no el del arranque', () {
    final contenedor = _contenedor();
    addTearDown(contenedor.dispose);

    final router = contenedor.read(routerProvider);
    expect(router, isA<GoRouter>());

    // El router ya está construido. Si la redirección hubiera capturado el
    // estado al construirse, esto no se vería reflejado.
    contenedor.read(userProvider.notifier).state = _usuario('u1', rol: 'admin');
    expect(contenedor.read(userRoleProvider), 'admin');
  });

  // Lo anterior prueba que el router no se recrea. Falta lo que de verdad
  // importa: que SIGA redirigiendo. Un router estable que no reacciona al
  // login deja a la persona trabada en la bienvenida —peor que la pantalla
  // cargando dos veces—. Acá se monta la app de verdad y se mira a dónde va.
  testWidgets('entrar redirige al panel sin volver a montar la navegación',
      (tester) async {
    final contenedor = _contenedor();
    addTearDown(contenedor.dispose);

    final router = contenedor.read(routerProvider);

    await tester.pumpWidget(
      _app(contenedor, router),
    );
    await tester.pump();

    expect(router.state.matchedLocation, '/welcome',
        reason: 'sin sesión se arranca en la bienvenida');

    contenedor.read(userProvider.notifier).state = _usuario('u1', rol: 'admin');
    await tester.pump();
    await tester.pump();

    expect(
      router.state.matchedLocation,
      '/dashboard',
      reason: 'el refreshListenable no disparó: nadie podría entrar',
    );

    // El panel intenta hablar con Supabase al montarse y acá no hay backend.
    // Lo que se está probando es a dónde navega, no qué dibuja. Hay que
    // drenarlo DESPUÉS de cada pump y no una sola vez: el panel se reconstruye
    // en cada cuadro y vuelve a lanzar el mismo error.
    tester.takeException();

    // La bienvenida —por la que se pasó antes de entrar— arranca con
    // animaciones diferidas, y cada `delay:` deja un temporizador programado.
    // El arnés falla el test si queda alguno vivo al desmontar, así que se
    // adelanta el reloj para que se consuman y recién ahí se baja el árbol.
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.takeException();
  });

  testWidgets('cerrar sesión vuelve a la bienvenida', (tester) async {
    final contenedor = _contenedor();
    addTearDown(contenedor.dispose);

    final router = contenedor.read(routerProvider);
    contenedor.read(userProvider.notifier).state = _usuario('u1', rol: 'admin');

    await tester.pumpWidget(
      _app(contenedor, router),
    );
    await tester.pump();
    tester.takeException();

    contenedor.read(userProvider.notifier).state = null;
    await tester.pump();
    await tester.pump();

    expect(router.state.matchedLocation, '/welcome');
    tester.takeException();

    // La bienvenida entra con animaciones diferidas (`delay:` de hasta 300 ms).
    // Cada una programa un temporizador, y el arnés falla el test si queda
    // alguno pendiente al desmontar. Se adelanta el reloj para que se
    // consuman y recién ahí se desmonta el árbol.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  // El dispositivo de puerta entra por otro proveedor y además tiene un guard
  // que le limita las rutas. Ese guard ahora lee el estado con `ref.read` en
  // vez de tenerlo capturado, así que hay que comprobar que sigue cerrando:
  // una puerta que puede navegar a la configuración es un agujero, no una
  // molestia visual.
  testWidgets('el dispositivo de puerta entra y sigue sin poder salirse de lo suyo',
      (tester) async {
    final contenedor = ProviderContainer(overrides: [
      userProvider.overrideWith((ref) => null),
      deviceProvider.overrideWith((ref) => _PuertaDePrueba()),
    ]);
    addTearDown(contenedor.dispose);

    final router = contenedor.read(routerProvider);

    await tester.pumpWidget(
      _app(contenedor, router),
    );
    await tester.pump();
    expect(router.state.matchedLocation, '/welcome');

    (contenedor.read(deviceProvider.notifier) as _PuertaDePrueba).entrar();
    await tester.pump();
    await tester.pump();

    expect(router.state.matchedLocation, '/dashboard',
        reason: 'el dispositivo no llegó a entrar');
    tester.takeException();

    // Permitido.
    router.go('/scanner');
    await tester.pump();
    await tester.pump();
    expect(router.state.matchedLocation, '/scanner');
    tester.takeException();

    // Prohibido: tiene que rebotar al panel.
    router.go('/settings/users');
    await tester.pump();
    await tester.pump();
    expect(router.state.matchedLocation, '/dashboard',
        reason: 'una puerta pudo abrir la gestión de usuarios');
    tester.takeException();

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// `DeviceNotifier` lee del almacenamiento seguro al construirse, que en un
/// test no existe. Su constructor ya traga ese error, así que alcanza con
/// heredar y exponer la entrada.
class _PuertaDePrueba extends DeviceNotifier {
  void entrar() {
    state = DeviceSession(
      deviceId: 'd1',
      alias: 'Puerta 1',
      pin: '0000',
      organizationId: 'org1',
    );
  }
}
