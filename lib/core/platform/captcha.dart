/// Token de Turnstile para adjuntar a una llamada de autenticación.
///
/// El widget vive en `web/js/turnstile.js` — Turnstile se dibuja en un iframe
/// propio y Flutter pinta sobre un canvas, así que no hay forma de montarlo
/// dentro del árbol de widgets sin platform views.
///
/// `tokenCaptcha()` devuelve `null` cuando el captcha no está disponible: la
/// API de Cloudflare bloqueada por una extensión, sin red, o el widget todavía
/// cargando. En ese caso la llamada de auth sale sin token y el servidor la
/// rechaza con un mensaje claro. Es deliberado: preferimos un error entendible
/// a colgar el login esperando algo que quizá nunca llegue.
///
/// El import condicional existe por los tests: corren sobre la VM de Dart,
/// donde `dart:js_interop` no existe, y sin el reemplazo cualquier suite que
/// llegue a la pantalla de login deja de compilar y desaparece de la corrida.
library;

export 'captcha_stub.dart' if (dart.library.js_interop) 'captcha_web.dart';
