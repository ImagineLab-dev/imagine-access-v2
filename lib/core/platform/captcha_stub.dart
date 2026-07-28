/// Sin captcha fuera del navegador.
///
/// La app es solo web, pero los tests corren sobre la VM de Dart, donde
/// `dart:js_interop` no existe. Sin este reemplazo, cualquier suite que llegue
/// a la pantalla de login deja de compilar y desaparece de la corrida — que es
/// peor que no tenerla, porque nadie se entera.
Future<String?> tokenCaptcha() async => null;
