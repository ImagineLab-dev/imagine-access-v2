import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_queue_service.dart';

/// Simple connectivity status without native plugin dependency.
enum AppConnectivity { online, offline }

final connectivityStatusProvider =
    StreamProvider<AppConnectivity>((ref) {
  return Stream.periodic(const Duration(seconds: 5), (i) => i)
      .asyncMap((i) async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty
          ? AppConnectivity.online
          : AppConnectivity.offline;
    } catch (_) {
      return AppConnectivity.offline;
    }
  }).distinct();
});

/// Watches connectivity and auto-processes offline queue when connection is restored
final offlineAutoSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AppConnectivity>>(connectivityStatusProvider,
      (previous, next) {
    final wasOffline = previous?.valueOrNull == AppConnectivity.offline;
    final isOnline = next.valueOrNull != null &&
        next.valueOrNull == AppConnectivity.online;

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
