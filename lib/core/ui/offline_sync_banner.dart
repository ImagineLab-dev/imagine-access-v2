import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../offline/connectivity_provider.dart';
import '../offline/offline_queue_service.dart';
import '../theme/app_theme.dart';

/// Tinta sobre el ámbar. El blanco sobre ámbar da ~1,9:1 y no se lee.
const Color _tinta = Color(0xFF3A2A00);

class OfflineSyncBanner extends ConsumerStatefulWidget {
  const OfflineSyncBanner({super.key});

  @override
  ConsumerState<OfflineSyncBanner> createState() => _OfflineSyncBannerState();
}

class _OfflineSyncBannerState extends ConsumerState<OfflineSyncBanner> {
  AppConnectivity? _lastStatus;

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
          backgroundColor: AppTheme.accentOrange,
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
        final wasOffline = _lastStatus == AppConnectivity.offline;
        _lastStatus = status;

        if (status == AppConnectivity.online && wasOffline) {
          Future<void>.microtask(_trySyncNow);
        }

        if (status == AppConnectivity.online) {
          return const SizedBox.shrink();
        }

        final count = queueCount.valueOrNull ?? 0;
        final l10n = AppLocalizations.of(context);

        // Banda ámbar a sangre: sin conexión es un estado del sistema, no un
        // aviso al pasar. Va en mono porque lo que importa es el contador de
        // operaciones pendientes.
        return SafeArea(
          bottom: false,
          child: Material(
            color: AppTheme.accentYellow,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off, color: _tinta, size: 16),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      (count > 0
                              ? l10n.offlinePendingOps(count)
                              : l10n.offlineWillSync)
                          .toUpperCase(),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: _tinta,
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
