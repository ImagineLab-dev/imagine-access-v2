import 'host_stub.dart' if (dart.library.js_interop) 'host_web.dart';

/// Host desde el que se está sirviendo la app.
///
/// La PWA se sirve desde varios subdominios que apuntan al MISMO build:
/// `imaginecloud.digital` y `super-admin.imaginecloud.digital`. El bundle es
/// idéntico; lo único que cambia es dónde aterriza el usuario.
///
/// El import es CONDICIONAL, como en `captcha.dart`, `camara.dart`, `meta.dart`,
/// `pwa.dart` y `abrir_url.dart`. Este archivo importaba `package:web` directo,
/// y eso vuelve intesteable en la VM de Dart a todo lo que lo alcance. El
/// 29/07/2026 el problema se agravó: `login_screen.dart` pasó a importar
/// `app_router.dart`, que importa esto, así que el router y la pantalla de login
/// quedaron fuera del alcance de cualquier test unitario. Los 116 tests pasaban
/// solo porque ninguno los tocaba — un test nuevo habría fallado con un error de
/// compilación difícil de relacionar con la causa.
String get hostActual => zonaHostActual();

/// `true` si se entró por el subdominio del panel de super-admin.
///
/// Esto NO es un control de acceso: quien entre por ahí sin el rol va a rebotar
/// igual, por el guard del router y por `is_superadmin()` en la base. Es solo
/// para no obligar al super-admin a navegar hasta el panel cada vez.
bool get esHostSuperAdmin => hostActual.startsWith('super-admin.');
