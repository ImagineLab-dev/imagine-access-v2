import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../offline/connectivity_provider.dart';
import '../offline/offline_queue_service.dart';

class OfflineSyncBanner extends ConsumerStatefulWidget {
  const OfflineSyncBanner({super.key});

  @override
  ConsumerState<OfflineSyncBanner> createState() => _OfflineSyncBannerState();
}

class _OfflineSyncBannerState extends ConsumerState<OfflineSyncBanner> {
  ConnectivityResult? _lastStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trySyncNow();
    });
  }

  Future<void> _trySyncNow() async {
    try {
      final result = await ref
          .read(offlineQueueProvider)
          .processQueue(client: Supabase.instance.client);
      if (result.dropped > 0 && mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.offlineOpsDropped(result.dropped)),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (_) {}
    ref.invalidate(offlineQueueCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = ref.watch(connectivityStatusProvider);
    final queueCount = ref.watch(offlineQueueCountProvider);

    return connectivity.when(
      data: (status) {
        final wasOffline = _lastStatus == ConnectivityResult.none;
        _lastStatus = status;

        if (status != ConnectivityResult.none && wasOffline) {
          Future<void>.microtask(_trySyncNow);
        }

        if (status != ConnectivityResult.none) {
          return const SizedBox.shrink();
        }

        final count = queueCount.valueOrNull ?? 0;
        final l10n = AppLocalizations.of(context);

        return SafeArea(
          bottom: false,
          child: Material(
            color: Colors.orange.shade700,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      count > 0
                          ? l10n.offlinePendingOps(count)
                          : l10n.offlineWillSync,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
