import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Implementación real, sobre el widget de `web/js/turnstile.js`.
Future<String?> tokenCaptcha() async {
  final api = globalContext.getProperty<JSObject?>('imagineCaptcha'.toJS);
  if (api == null) return null;

  try {
    final promesa = api.callMethod<JSPromise<JSAny?>>('token'.toJS);
    final resultado = await promesa.toDart;
    if (resultado == null) return null;
    return (resultado as JSString).toDart;
  } catch (_) {
    // Cualquier fallo del lado JS se trata como "sin captcha". Que el widget
    // se rompa no debería tirar una excepción rara en la pantalla de login.
    return null;
  }
}
