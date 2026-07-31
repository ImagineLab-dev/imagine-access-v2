/// Token de Turnstile para adjuntar a una llamada de autenticación.
///
/// El widget vive en `web/js/turnstile.js` — Turnstile se dibuja en un iframe
/// propio y Flutter pinta sobre un canvas, así que no hay forma de montarlo
/// dentro del árbol de widgets sin platform views.
///
/// `tokenCaptcha()` devuelve `null` cuando el captcha no está disponible: la
/// API de Cloudflare bloqueada por una extensión, sin red, o el widget todavía
/// cargando. En ese caso la llamada de auth sale sin token, y sale igual: es
/// deliberado, preferimos dejar entrar a alguien con una extensión rara antes
/// que colgar el login esperando algo que quizá nunca llegue.
///
/// OJO: hoy el token no lo valida nadie. GoTrue en el servidor no tiene el
/// captcha habilitado —no existe `GOTRUE_SECURITY_CAPTCHA_ENABLED` ni el
/// secreto— así que acepta la llamada con token, sin token o con uno
/// inventado. Comprobado el 31/07/2026 contra producción.
///
/// O sea que el widget hoy es decorativo: no frena registros automatizados.
/// Encenderlo del lado del servidor es una decisión con filo, porque si el
/// secreto está mal TODOS los registros dejan de funcionar. Antes de activarlo
/// hay que probar el par clave/secreto contra el dominio real.
///
/// El import condicional existe por los tests: corren sobre la VM de Dart,
/// donde `dart:js_interop` no existe, y sin el reemplazo cualquier suite que
/// llegue a la pantalla de login deja de compilar y desaparece de la corrida.
library;

export 'captcha_stub.dart' if (dart.library.js_interop) 'captcha_web.dart';
