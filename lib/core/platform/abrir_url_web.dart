import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Pestaña reservada antes de una operación asíncrona.
///
/// Los navegadores solo permiten `window.open` durante el gesto que lo
/// disparó. Si primero se consulta al servidor y después se intenta abrir, el
/// gesto ya venció y la pestaña se bloquea SIN AVISO: para el usuario, tocar el
/// botón simplemente no hace nada.
///
/// Por eso la pestaña se reserva vacía en el mismo instante del toque y se le
/// pone la dirección cuando llega.
class PestanaReservada {
  PestanaReservada._(this._ventana);

  final JSObject? _ventana;

  /// La lleva a la dirección final.
  ///
  /// Si el navegador igual bloqueó la reserva —hay bloqueadores que lo hacen
  /// siempre— se navega en la pestaña actual. Salir de la app es peor que
  /// abrir al lado, pero es infinitamente mejor que un botón que no responde.
  void navegarA(String url) {
    final v = _ventana;
    if (v == null) {
      globalContext.setProperty('location'.toJS, url.toJS);
      return;
    }

    // `opener = null` ANTES de navegar, no `noopener` al abrir.
    //
    // Las dos cosas protegen igual —le cortan a la página destino el acceso a
    // la ventana que la abrió— pero `noopener` hace que `window.open` devuelva
    // null por especificación, y sin ese control no se puede llevar la pestaña
    // reservada a ninguna parte. Acá todavía está en about:blank y es del mismo
    // origen, así que se le puede escribir; después de navegar ya no.
    try {
      v.setProperty('opener'.toJS, null);
    } catch (_) {
      // Si el navegador no lo permite, se sigue igual: perder el corte del
      // opener es un riesgo menor que dejar al usuario sin poder pagar.
    }
    v.setProperty('location'.toJS, url.toJS);
  }

  /// Cierra la pestaña reservada. Se usa cuando la operación falló y quedaría
  /// una pestaña en blanco abierta sin explicación.
  void cerrar() {
    try {
      _ventana?.callMethod<JSAny?>('close'.toJS);
    } catch (_) {
      // Ya cerrada o inaccesible.
    }
  }
}

PestanaReservada reservarPestana() {
  try {
    // Sin `noopener`: haría que esto devuelva null y la reserva no serviría de
    // nada. El corte se hace en `navegarA`, con `opener = null`.
    final v = globalContext.callMethod<JSObject?>(
        'open'.toJS, ''.toJS, '_blank'.toJS);
    return PestanaReservada._(v);
  } catch (_) {
    return PestanaReservada._(null);
  }
}

/// Abre una URL en una pestaña nueva, para cuando NO hay operación asíncrona
/// de por medio y el gesto sigue vigente.
void abrirEnPestanaNueva(String url) {
  globalContext.callMethod<JSAny?>(
      'open'.toJS, url.toJS, '_blank'.toJS, 'noopener,noreferrer'.toJS);
}
