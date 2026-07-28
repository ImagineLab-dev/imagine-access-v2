import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Resultado de buscar una versión nueva de la app.
enum ResultadoActualizacion { nueva, alDia, sinSoporte }

/// Le pide al service worker que compruebe si hay una versión nueva.
///
/// El chequeo automático es horario y solo corre con la app abierta. En iPhone
/// eso alcanza menos todavía: el sistema suspende la aplicación instalada y el
/// temporizador deja de correr, así que sin una vía manual alguien puede pasar
/// días sin enterarse de que hay algo nuevo.
Future<ResultadoActualizacion> buscarActualizacion() async {
  final api = globalContext.getProperty<JSObject?>('imaginePWA'.toJS);
  if (api == null) return ResultadoActualizacion.sinSoporte;
  try {
    final r = await api
        .callMethod<JSPromise<JSAny?>>('buscarActualizacion'.toJS)
        .toDart;
    return switch ((r as JSString?)?.toDart) {
      'nueva' => ResultadoActualizacion.nueva,
      'al-dia' => ResultadoActualizacion.alDia,
      _ => ResultadoActualizacion.sinSoporte,
    };
  } catch (_) {
    return ResultadoActualizacion.sinSoporte;
  }
}
