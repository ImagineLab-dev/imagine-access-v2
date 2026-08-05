import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Puente con `web/js/lector.js`.
///
/// El lector nativo corre SOBRE el mismo elemento de video que ya creó
/// mobile_scanner, así que no compite con él ni le saca la cámara: son dos
/// decodificadores mirando el mismo cuadro. El primero que encuentra el código
/// gana, y el guard `_isProcessing` del escáner impide que se procese dos veces.

JSObject? get _api => globalContext.getProperty<JSObject?>('imagineLector'.toJS);

/// ¿El navegador trae decodificador nativo? Chromium sí; Safari en iPhone
/// todavía no, y ahí se sigue con ZXing.
bool get lectorNativoDisponible {
  final api = _api;
  if (api == null) return false;
  try {
    return api.callMethod<JSBoolean>('disponible'.toJS).toDart;
  } catch (_) {
    return false;
  }
}

/// Arranca el lector rápido. Devuelve false si no se pudo, y en ese caso la app
/// sigue con ZXing exactamente como antes.
bool iniciarLectorNativo(void Function(String codigo) alEncontrar) {
  final api = _api;
  if (api == null) return false;
  try {
    final callback = (JSString codigo) {
      alEncontrar(codigo.toDart);
    }.toJS;
    return api.callMethod<JSBoolean>('iniciar'.toJS, callback).toDart;
  } catch (_) {
    return false;
  }
}

void detenerLectorNativo() {
  try {
    _api?.callMethod<JSAny?>('detener'.toJS);
  } catch (_) {
    // Detener algo que no arrancó no es un error.
  }
}

/// Telemetría en JSON: motor en uso, cuadros procesados, lecturas y milisegundos
/// del último cuadro. Sirve para responder "¿está leyendo?" con un número.
String estadoDelLector() {
  final api = _api;
  if (api == null) return '{}';
  try {
    return api.callMethod<JSString>('estado'.toJS).toDart;
  } catch (_) {
    return '{}';
  }
}
