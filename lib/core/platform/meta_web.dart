import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Eventos del pixel de Meta desde el navegador.
///
/// Reparto deliberado para que NO haya duplicados:
///   - Navegador → PageView e InitiateCheckout
///   - Servidor  → Purchase, desde el webhook de dLocal
///
/// `Purchase` NO se manda desde acá: el pago termina en el dominio de dLocal,
/// donde este código ya no corre. Si algún día se mandara desde los dos lados,
/// habría que darles el mismo event_id o Meta lo contaría dos veces.
void eventoMeta(String nombre, {double? valor, String moneda = 'USD'}) {
  try {
    final fbq = globalContext.getProperty<JSFunction?>('fbq'.toJS);
    if (fbq == null) return; // Bloqueado por una extensión, o todavía cargando.

    if (valor == null) {
      fbq.callAsFunction(null, 'track'.toJS, nombre.toJS);
      return;
    }

    final datos = JSObject();
    datos.setProperty('value'.toJS, valor.toJS);
    datos.setProperty('currency'.toJS, moneda.toJS);
    fbq.callAsFunction(null, 'track'.toJS, nombre.toJS, datos);
  } catch (_) {
    // La analítica nunca puede romper una pantalla.
  }
}
