import 'package:web/web.dart' as web;

/// Host desde el que se está sirviendo la app.
///
/// La PWA se sirve desde varios subdominios que apuntan al MISMO build:
/// `imaginecloud.digital` y `super-admin.imaginecloud.digital`. El bundle es
/// idéntico; lo único que cambia es dónde aterriza el usuario.
String get hostActual => web.window.location.hostname.toLowerCase();

/// `true` si se entró por el subdominio del panel de super-admin.
///
/// Esto NO es un control de acceso: quien entre por ahí sin el rol va a rebotar
/// igual, por el guard del router y por `is_superadmin()` en la base. Es solo
/// para no obligar al super-admin a navegar hasta el panel cada vez.
bool get esHostSuperAdmin => hostActual.startsWith('super-admin.');
