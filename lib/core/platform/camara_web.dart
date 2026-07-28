import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Mejora la cámara del escáner: resolución y enfoque continuo.
///
/// La implementación está en `web/js/camara.js`. Va en JS porque hay que tomar
/// la pista de video que creó mobile_scanner y aplicarle restricciones, y el
/// plugin no la expone a Dart.
Future<void> mejorarCamara() async {
  final api = globalContext.getProperty<JSObject?>('imagineCamara'.toJS);
  if (api == null) return;
  try {
    await api.callMethod<JSPromise<JSAny?>>('mejorar'.toJS).toDart;
  } catch (_) {
    // Que no se pueda mejorar la cámara no debe impedir escanear: el escáner
    // sigue funcionando con lo que el navegador haya entregado por defecto.
  }
}
