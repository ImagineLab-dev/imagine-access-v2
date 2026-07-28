import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Token de Turnstile para adjuntar a una llamada de autenticación.
///
/// El widget vive en `web/js/turnstile.js` — Turnstile se dibuja en un iframe
/// propio y Flutter pinta sobre un canvas, así que no hay forma de montarlo
/// dentro del árbol de widgets sin platform views.
///
/// Devuelve `null` cuando el captcha no está disponible: la API de Cloudflare
/// bloqueada por una extensión, sin red, o el widget todavía cargando. En ese
/// caso la llamada de auth sale sin token y el servidor la rechaza con un
/// mensaje claro. Es deliberado: preferimos un error entendible a colgar el
/// login esperando algo que quizá nunca llegue.
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
