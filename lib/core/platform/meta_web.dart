import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Eventos del pixel de Meta desde el navegador.
///
/// Pasa por `window.imagineMeta.evento` (definido en `web/js/meta-pixel.js`) y
/// NO por `fbq` directo. La diferencia importa: ese envoltorio le pone un
/// `event_id` al evento y manda una copia por servidor con el mismo
/// identificador, para que Meta las una y cuente una sola.
///
/// Llamar a `fbq` a secas —como se hacía antes— dejaba estos eventos sin nada
/// con qué deduplicarlos y sin copia de servidor. El diagnóstico de Meta del
/// 01/08/2026 lo mostró: solo el 13,45 % de los eventos del navegador llevaban
/// identificador, y el servidor mandaba 443 eventos menos que el píxel en siete
/// días. Eran estos.
///
/// `Purchase` sigue sin mandarse desde acá: el pago termina en el dominio de
/// dLocal, donde este código ya no corre. Lo manda el webhook, y por eso el
/// endpoint del servidor tampoco lo acepta desde el navegador — si lo hiciera,
/// cualquiera podría declarar compras que nunca ocurrieron.
void eventoMeta(String nombre, {double? valor, String moneda = 'USD'}) {
  try {
    JSObject? datos;
    if (valor != null) {
      datos = JSObject();
      datos.setProperty('value'.toJS, valor.toJS);
      datos.setProperty('currency'.toJS, moneda.toJS);
    }

    final api = globalContext.getProperty<JSObject?>('imagineMeta'.toJS);
    if (api != null) {
      final enviar = api.getProperty<JSFunction?>('evento'.toJS);
      if (enviar != null) {
        enviar.callAsFunction(api, nombre.toJS, datos);
        return;
      }
    }

    // Reserva: si el envoltorio no está —el archivo no cargó, o una extensión
    // lo bloqueó— se usa `fbq` pelado. Pierde el identificador y la copia de
    // servidor, pero es mejor que no medir nada.
    final fbq = globalContext.getProperty<JSFunction?>('fbq'.toJS);
    if (fbq == null) return;
    if (datos == null) {
      fbq.callAsFunction(null, 'track'.toJS, nombre.toJS);
    } else {
      fbq.callAsFunction(null, 'track'.toJS, nombre.toJS, datos);
    }
  } catch (_) {
    // La analítica nunca puede romper una pantalla.
  }
}
