import 'package:web/web.dart' as web;

/// Abre una URL en una pestaña nueva.
///
/// `noopener` corta el acceso de la página destino a `window.opener`: sin eso,
/// el sitio abierto puede redirigir al nuestro desde su propia pestaña.
void abrirEnPestanaNueva(String url) {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
