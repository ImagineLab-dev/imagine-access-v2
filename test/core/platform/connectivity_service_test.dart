import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/platform/connectivity_service.dart';
import 'package:imagine_access/core/platform/connectivity_signals.dart';

class FakeSignals implements ConnectivitySignals {
  bool online = true;
  bool probeSucceeds = true;
  int probeCalls = 0;

  final _online = StreamController<void>.broadcast();
  final _offline = StreamController<void>.broadcast();

  @override
  bool get isOnline => online;

  @override
  Stream<void> get onOnline => _online.stream;

  @override
  Stream<void> get onOffline => _offline.stream;

  @override
  Future<bool> probe() async {
    probeCalls++;
    return probeSucceeds;
  }

  void emitOnline() {
    online = true;
    _online.add(null);
  }

  void emitOffline() {
    online = false;
    _offline.add(null);
  }

  Future<void> dispose() async {
    await _online.close();
    await _offline.close();
  }
}

void main() {
  late FakeSignals signals;
  late ConnectivityService service;

  setUp(() {
    signals = FakeSignals();
    service = ConnectivityService(
      signals,
      probeInterval: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    await signals.dispose();
  });

  test('reporta online cuando el navegador está online y el backend responde',
      () async {
    signals.online = true;
    signals.probeSucceeds = true;

    await expectLater(
      service.watch(),
      emitsInOrder(<AppConnectivity>[AppConnectivity.online]),
    );
  });

  test('reporta offline sin sondear cuando navigator.onLine es false', () async {
    signals.online = false;

    final first = await service.watch().first;

    expect(first, AppConnectivity.offline);
    expect(signals.probeCalls, 0,
        reason: 'sondear con el navegador offline es tráfico desperdiciado');
  });

  test('reporta offline ante portal cautivo: navegador online, backend no responde',
      () async {
    signals.online = true;
    signals.probeSucceeds = false;

    final first = await service.watch().first;

    expect(first, AppConnectivity.offline);
    expect(signals.probeCalls, greaterThan(0));
  });

  test('no repite el mismo estado dos veces seguidas', () async {
    signals.online = true;
    signals.probeSucceeds = true;

    final seen = <AppConnectivity>[];
    final sub = service.watch().listen(seen.add);

    await Future<void>.delayed(const Duration(milliseconds: 180));
    await sub.cancel();

    expect(seen, <AppConnectivity>[AppConnectivity.online],
        reason: 'varias sondas exitosas seguidas son un solo evento online');
  });

  test('reevalúa al recibir el evento online del navegador', () async {
    signals.online = false;

    final seen = <AppConnectivity>[];
    final sub = service.watch().listen(seen.add);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    signals.probeSucceeds = true;
    signals.emitOnline();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();

    expect(seen, <AppConnectivity>[
      AppConnectivity.offline,
      AppConnectivity.online,
    ]);
  });
}
