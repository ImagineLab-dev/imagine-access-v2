import 'dart:async';

import 'connectivity_signals.dart';

/// Estado de conectividad tal como lo consume la app.
enum AppConnectivity { online, offline }

/// Deriva [AppConnectivity] a partir de las [ConnectivitySignals] del navegador.
///
/// `navigator.onLine` en `false` es concluyente: no hay red y no vale la pena
/// gastar una sonda. En `true` no lo es —un portal cautivo también da `true`—
/// así que se confirma con una sonda al backend.
class ConnectivityService {
  ConnectivityService(
    this._signals, {
    this.probeInterval = const Duration(seconds: 30),
  });

  final ConnectivitySignals _signals;
  final Duration probeInterval;

  Stream<AppConnectivity> watch() {
    late final StreamController<AppConnectivity> controller;
    final subscriptions = <StreamSubscription<void>>[];
    Timer? timer;
    AppConnectivity? last;
    var evaluating = false;

    Future<void> evaluate() async {
      if (evaluating || controller.isClosed) return;
      evaluating = true;
      try {
        final AppConnectivity status;
        if (!_signals.isOnline) {
          status = AppConnectivity.offline;
        } else {
          status = await _signals.probe()
              ? AppConnectivity.online
              : AppConnectivity.offline;
        }
        if (status != last && !controller.isClosed) {
          last = status;
          controller.add(status);
        }
      } finally {
        evaluating = false;
      }
    }

    controller = StreamController<AppConnectivity>(
      onListen: () {
        subscriptions.add(_signals.onOnline.listen((_) => evaluate()));
        subscriptions.add(_signals.onOffline.listen((_) => evaluate()));
        timer = Timer.periodic(probeInterval, (_) => evaluate());
        unawaited(evaluate());
      },
      onCancel: () async {
        timer?.cancel();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream;
  }
}
