import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Estado de la instalación de la PWA.
class EstadoInstalacion {
  const EstadoInstalacion({
    required this.instalada,
    required this.listo,
    required this.esIOS,
  });

  /// Ya está instalada y corriendo como app.
  final bool instalada;

  /// El navegador ofreció instalar (`beforeinstallprompt` llegó). En Android y
  /// escritorio sin esto no se puede abrir el diálogo por más que se quiera.
  final bool listo;

  /// iPhone: no hay diálogo, se instala a mano desde Compartir.
  final bool esIOS;

  /// Se ofrece SIEMPRE que no esté instalada, sea cual sea el navegador. Si el
  /// diálogo nativo no está disponible, `pedirInstalacion()` muestra
  /// instrucciones (iPhone o genéricas), así que la opción nunca queda sin
  /// hacer nada. Antes exigía `listo` —que el navegador hubiera disparado
  /// `beforeinstallprompt`—, y en Firefox/Safari de escritorio, o en Chromium
  /// antes de que llegara el evento, la opción de instalar quedaba invisible.
  bool get sePuedeOfrecer => !instalada;
}

JSObject? get _api =>
    globalContext.getProperty<JSObject?>('imagineInstalar'.toJS);

EstadoInstalacion estadoInstalacion() {
  final api = _api;
  if (api == null) {
    return const EstadoInstalacion(instalada: true, listo: false, esIOS: false);
  }
  try {
    final crudo = api.callMethod<JSString>('estado'.toJS).toDart;
    final d = jsonDecode(crudo) as Map<String, dynamic>;
    return EstadoInstalacion(
      instalada: d['instalada'] == true,
      listo: d['listo'] == true,
      esIOS: d['ios'] == true,
    );
  } catch (_) {
    // Si no se puede saber, no se ofrece: es preferible no mostrar una opción
    // que después no haga nada.
    return const EstadoInstalacion(instalada: true, listo: false, esIOS: false);
  }
}

/// Abre el diálogo de instalación. Devuelve `instalada`, `pedido`, `ios` o
/// `no-listo`.
Future<String> pedirInstalacion() async {
  final api = _api;
  if (api == null) return 'no-listo';
  try {
    return api.callMethod<JSString>('instalar'.toJS).toDart;
  } catch (_) {
    return 'no-listo';
  }
}
