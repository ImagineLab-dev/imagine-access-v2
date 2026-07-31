import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/platform/host.dart';
import 'package:imagine_access/core/router/app_router.dart';

/// Este test existe sobre todo para PROBAR QUE SE PUEDE ESCRIBIR.
///
/// Hasta el 29/07/2026 `host.dart` importaba `package:web` sin stub, y con eso el
/// router entero quedaba fuera del alcance de la VM de Dart: cualquier test que
/// lo importara fallaba al compilar. El problema se agravó ese mismo día cuando
/// `login_screen.dart` pasó a importar `app_router.dart`. Los 116 tests pasaban
/// únicamente porque ninguno tocaba esa cadena.
///
/// Con el import condicional en su lugar, en la VM se usa el stub y `hostActual`
/// devuelve cadena vacía. Si alguien vuelve a poner un import directo de
/// `package:web` ahí, este archivo deja de compilar y el problema aparece acá, no
/// meses después y disfrazado de otra cosa.
void main() {
  test('fuera del navegador el host queda vacio y no es el de super-admin', () {
    expect(hostActual, '');
    expect(esHostSuperAdmin, isFalse);
  });

  test('sin el subdominio de super-admin, todos los roles van al panel', () {
    for (final rol in <String?>[null, '', 'rrpp', 'door', 'admin', 'superadmin']) {
      expect(
        rutaTrasIngresar(rol),
        '/dashboard',
        reason: 'el rol $rol no deberia cambiar el destino fuera del subdominio',
      );
    }
  });
}
