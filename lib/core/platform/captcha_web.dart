import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? get _api =>
    globalContext.getProperty<JSObject?>('imagineCaptcha'.toJS);

/// Implementación real, sobre el widget de `web/js/turnstile.js`.
Future<String?> tokenCaptcha() async {
  final api = _api;
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

void mostrarCaptcha(bool visible) {
  try {
    _api?.callMethod<JSAny?>('visible'.toJS, visible.toJS);
  } catch (_) {
    // Que no se pueda mostrar el widget no es motivo para romper la pantalla.
  }
}
