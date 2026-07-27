import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../platform/browser_connectivity_signals.dart';
import '../platform/connectivity_service.dart';
import 'offline_queue_service.dart';

export '../platform/connectivity_service.dart' show AppConnectivity;

/// Endpoint de salud de GoTrue: liviano y sin efectos secundarios.
///
/// La clave va por query string y no por cabecera a propósito: la sonda usa
/// `mode: 'no-cors'`, que descarta las cabeceras no estándar, así que un
/// `apikey:` nunca llegaría. Sin la clave, Kong responde 401 y el navegador
/// ensucia la consola con un error en cada sondeo. La detección funcionaba
/// igual —con no-cors alcanza con que la promesa resuelva— pero el ruido
/// hacía parecer que algo estaba roto.
///
/// Exponer la clave anon en la URL no agrega riesgo: ya viaja en el bundle
/// JS, es pública por diseño, y la barrera real es RLS.
String _probeUrl() =>
    '${Env.supabaseUrl}/auth/v1/health?apikey=${Uri.encodeQueryComponent(Env.supabaseAnonKey)}';

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService(
    BrowserConnectivitySignals(probeUrl: _probeUrl()),
  );
});

final connectivityStatusProvider = StreamProvider<AppConnectivity>((ref) {
  return ref.watch(connectivityServiceProvider).watch();
});

/// Observa la conectividad y procesa la cola offline al recuperar conexión.
final offlineAutoSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AppConnectivity>>(connectivityStatusProvider,
      (previous, next) {
    final wasOffline = previous?.valueOrNull == AppConnectivity.offline;
    final isOnline = next.valueOrNull == AppConnectivity.online;

    if (wasOffline && isOnline) {
      if (kDebugMode) {
        dev.log('Connection restored — processing offline queue',
            name: 'OfflineAutoSync');
      }
      final queue = ref.read(offlineQueueProvider);
      queue.processQueue(client: Supabase.instance.client).then((result) {
        if (kDebugMode) {
          dev.log(
              'Offline sync: ${result.succeeded} ok, ${result.failed} failed, ${result.remaining} remaining',
              name: 'OfflineAutoSync');
        }
      });
    }
  });
});
