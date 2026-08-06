import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Puente con `web/js/lector.js`.
///
/// El lector nativo corre SOBRE el mismo elemento de video que ya creó
/// mobile_scanner, así que no compite con él ni le saca la cámara: son dos
/// decodificadores mirando el mismo cuadro. El primero que encuentra el código
/// gana, y el guard `_isProcessing` del escáner impide procesarlo dos veces.

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

/// Enciende el lector y devuelve el número de sesión, o 0 si no se pudo.
///
/// **Hay que guardar ese número**: es lo único que autoriza a apagarlo después.
/// Sin él, la pantalla que se está destruyendo apaga el lector que la pantalla
/// nueva acaba de encender —Flutter monta la nueva antes de destruir la vieja—
/// y el escáner queda muerto hasta recargar la app.
int iniciarLectorNativo(void Function(String codigo) alEncontrar) {
  final api = _api;
  if (api == null) return 0;
  try {
    final callback = (JSString codigo) {
      alEncontrar(codigo.toDart);
    }.toJS;
    return api.callMethod<JSNumber>('iniciar'.toJS, callback).toDartInt;
  } catch (_) {
    return 0;
  }
}

/// Apaga el lector, solo si [sesion] sigue siendo la vigente.
void detenerLectorNativo(int sesion) {
  if (sesion == 0) return;
  try {
    _api?.callMethod<JSAny?>('detener'.toJS, sesion.toJS);
  } catch (_) {
    // Detener algo que no arrancó no es un error.
  }
}

/// Telemetría en JSON: motor, sesión, cuadros procesados, lecturas, reinicios
/// del vigía y milisegundos desde el último cuadro. Sirve para responder
/// "¿está leyendo?" con un número en vez de una sensación.
String estadoDelLector() {
  final api = _api;
  if (api == null) return '{}';
  try {
    return api.callMethod<JSString>('estado'.toJS).toDart;
  } catch (_) {
    return '{}';
  }
}
