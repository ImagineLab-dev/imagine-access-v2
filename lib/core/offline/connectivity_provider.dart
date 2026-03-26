import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_queue_service.dart';

final connectivityStatusProvider =
    StreamProvider<ConnectivityResult>((ref) {
  try {
    return Connectivity()
        .onConnectivityChanged
        .map((results) => results.isNotEmpty ? results.first : ConnectivityResult.none)
        .distinct()
        .handleError((error) {
      // Silently handle connectivity stream errors on iOS
    });
  } catch (e) {
    // If stream creation fails, return a single-value stream with 'none'
    return Stream.value(ConnectivityResult.none);
  }
});

/// Watches connectivity and auto-processes offline queue when connection is restored
final offlineAutoSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<ConnectivityResult>>(connectivityStatusProvider,
      (previous, next) {
    final wasOffline = previous?.valueOrNull == ConnectivityResult.none;
    final isOnline = next.valueOrNull != null &&
        next.valueOrNull != ConnectivityResult.none;

    if (wasOffline && isOnline) {
      if (kDebugMode) {
        dev.log('Connection restored — processing offline queue',
            name: 'OfflineAutoSync');
      }
      final queue = ref.read(offlineQueueProvider);
      queue
          .processQueue(client: Supabase.instance.client)
          .then((result) {
        if (kDebugMode) {
          dev.log(
              'Offline sync: ${result.succeeded} ok, ${result.failed} failed, ${result.remaining} remaining',
              name: 'OfflineAutoSync');
        }
      });
    }
  });
});
