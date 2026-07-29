import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/error_handler.dart';
import 'pending_operation.dart';

typedef OfflineOperationExecutor = Future<bool> Function(PendingOperation op);

class OfflineQueuedException implements Exception {
  final String message;
  const OfflineQueuedException(this.message);

  @override
  String toString() => message;
}

class QueueProcessResult {
  final int processed;
  final int succeeded;
  final int failed;
  final int remaining;
  final int dropped;

  const QueueProcessResult({
    required this.processed,
    required this.succeeded,
    required this.failed,
    required this.remaining,
    this.dropped = 0,
  });
}

class OfflineQueueService {
  static const String _storageKey = 'offline_pending_operations_v1';
  static const int _maxRetries = 3;

  Future<List<PendingOperation>> getPendingOperations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <PendingOperation>[];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) =>
            PendingOperation.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> enqueue(PendingOperation operation) async {
    final current = await getPendingOperations();
    current.removeWhere((item) => item.id == operation.id);
    current.add(operation);
    await _save(current);
  }

  Future<void> removeById(String operationId) async {
    final current = await getPendingOperations();
    current.removeWhere((item) => item.id == operationId);
    await _save(current);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<int> count() async {
    final current = await getPendingOperations();
    return current.length;
  }

  Future<QueueProcessResult> processQueue({
    SupabaseClient? client,
    OfflineOperationExecutor? executor,
  }) async {
    final current = await getPendingOperations();
    if (current.isEmpty) {
      return const QueueProcessResult(
        processed: 0,
        succeeded: 0,
        failed: 0,
        remaining: 0,
      );
    }

    final nextQueue = <PendingOperation>[];
    int succeeded = 0;
    int failed = 0;
    int dropped = 0;

    for (final op in current) {
      try {
        final ok = executor != null
            ? await executor(op)
            : await _executeWithSupabase(client!, op);

        if (ok) {
          succeeded++;
          continue;
        }

        failed++;
        final retried = op.copyWith(retryCount: op.retryCount + 1);
        if (retried.retryCount < _maxRetries) {
          nextQueue.add(retried);
        } else {
          dropped++;
        }
      } catch (e, stack) {
        failed++;
        final networkError = ErrorHandler.analyzeError(e);
        final retried = op.copyWith(retryCount: op.retryCount + 1);

        if (networkError.isRetryable && retried.retryCount < _maxRetries) {
          nextQueue.add(retried);
        } else {
          dropped++;
        }
        // Non-retryable errors are dropped (not re-queued)

        if (kDebugMode) {
          dev.log(
            'Offline queue operation failed: ${op.type} (${op.id})',
            error: e,
            stackTrace: stack,
            name: 'OfflineQueue',
          );
        }
      }
    }

    await _save(nextQueue);
    return QueueProcessResult(
      processed: current.length,
      succeeded: succeeded,
      failed: failed,
      remaining: nextQueue.length,
      dropped: dropped,
    );
  }

  /// Cuerpo de la operación con la sesión ACTUAL, no la que tenía al encolarse.
  ///
  /// Los JWT vencen en aproximadamente una hora. Una validación hecha sin
  /// conexión a las dos de la mañana y sincronizada a las cinco llegaba con un
  /// token muerto: el servidor respondía 401, la cola lo contaba como fallo, y
  /// tras unos reintentos la descartaba EN SILENCIO. La persona ya había
  /// entrado, no quedaba registro, y el ticket seguía figurando como válido
  /// para que otro lo usara.
  ///
  /// Las sesiones de puerta no tienen este problema —se identifican con
  /// device_id y PIN, que no vencen— pero las de admin y RRPP sí.
  Map<String, dynamic> _cuerpoConSesionActual(
      SupabaseClient client, PendingOperation op) {
    final cuerpo = Map<String, dynamic>.from(op.payload);
    final token = client.auth.currentSession?.accessToken;
    if (token != null) {
      cuerpo['_auth_token'] = token;
    } else {
      // Sin sesión vigente se manda sin token: si la operación lleva
      // credenciales de dispositivo, el servidor la acepta igual.
      cuerpo.remove('_auth_token');
    }
    return cuerpo;
  }

  Future<bool> _executeWithSupabase(
    SupabaseClient client,
    PendingOperation op,
  ) async {
    final cuerpo = _cuerpoConSesionActual(client, op);

    switch (op.type) {
      case 'create_ticket':
        final createTicketResponse =
            await client.functions.invoke('create_ticket', body: cuerpo);
        return createTicketResponse.status == 200 ||
            createTicketResponse.status == 201;

      case 'validate_ticket':
        final validateResponse =
            await client.functions.invoke('validate_ticket', body: cuerpo);
        return validateResponse.status == 200 || validateResponse.status == 201;

      default:
        throw UnsupportedError('Unsupported offline operation: ${op.type}');
    }
  }

  Future<void> _save(List<PendingOperation> operations) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(operations.map((item) => item.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}

final offlineQueueProvider = Provider<OfflineQueueService>((ref) {
  return OfflineQueueService();
});

final offlineQueueCountProvider = FutureProvider<int>((ref) async {
  return ref.watch(offlineQueueProvider).count();
});
