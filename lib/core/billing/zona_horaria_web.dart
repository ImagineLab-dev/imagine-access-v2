import 'dart:js_interop';

@JS('Intl.DateTimeFormat')
extension type _DateTimeFormat._(JSObject _) implements JSObject {
  external factory _DateTimeFormat();
  external _OpcionesResueltas resolvedOptions();
}

extension type _OpcionesResueltas._(JSObject _) implements JSObject {
  external String? get timeZone;
}

/// Zona horaria configurada en el dispositivo, según el navegador.
String? zonaHorariaDelDispositivo() {
  try {
    return _DateTimeFormat().resolvedOptions().timeZone;
  } catch (_) {
    return null;
  }
}
