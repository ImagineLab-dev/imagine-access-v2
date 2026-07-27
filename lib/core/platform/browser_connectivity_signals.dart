import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'connectivity_signals.dart';

/// [ConnectivitySignals] sobre las APIs reales del navegador.
///
/// No tiene tests unitarios a propósito: es una capa de traducción sin lógica.
/// Se verifica en el navegador, en la Tarea 7.
class BrowserConnectivitySignals implements ConnectivitySignals {
  BrowserConnectivitySignals({
    required this.probeUrl,
    this.probeTimeout = const Duration(seconds: 5),
  });

  /// URL a la que se le hace la sonda. Debe responder sin autenticación.
  final String probeUrl;
  final Duration probeTimeout;

  @override
  bool get isOnline => web.window.navigator.onLine;

  @override
  Stream<void> get onOnline => _windowEvents('online');

  @override
  Stream<void> get onOffline => _windowEvents('offline');

  @override
  Future<bool> probe() async {
    try {
      // `mode: 'no-cors'` a propósito: solo interesa saber si hay camino de
      // red hasta el backend, no leer la respuesta. Evita depender de que el
      // endpoint mande cabeceras CORS — si no las mandara, un fetch normal
      // tiraría excepción y reportaríamos "offline" estando online.
      //
      // La contrapartida es que la respuesta es opaca (`status == 0`), así
      // que el indicador de alcanzabilidad es que la promesa **resuelva**,
      // no el código de estado.
      await web.window
          .fetch(
            probeUrl.toJS,
            web.RequestInit(method: 'GET', mode: 'no-cors', cache: 'no-store'),
          )
          .toDart
          .timeout(probeTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  Stream<void> _windowEvents(String type) {
    late final StreamController<void> controller;
    final listener = ((web.Event _) {
      if (!controller.isClosed) controller.add(null);
    }).toJS;

    controller = StreamController<void>.broadcast(
      onListen: () => web.window.addEventListener(type, listener),
      onCancel: () => web.window.removeEventListener(type, listener),
    );

    return controller.stream;
  }
}
