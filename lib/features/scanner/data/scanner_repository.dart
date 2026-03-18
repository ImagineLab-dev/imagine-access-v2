import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/offline/offline_queue_service.dart';
import '../../../core/offline/pending_operation.dart';

class ScannerRepository {
  final SupabaseClient _client;
  final Ref _ref;
  ScannerRepository(this._client, this._ref);

  Future<Map<String, dynamic>> validateQr(
      String qrToken, String? deviceId, String? pin, String eventId) async {
    final requestId = const Uuid().v4();
    final payload = {
      'method': 'qr',
      'qr_token': qrToken,
      'device_id': deviceId,
      'pin': pin,
      'event_id': eventId,
      'request_id': requestId,
    };

    try {
      final response = await _client.functions.invoke('validate_ticket', body: payload);

      if (response.status != 200) {
        final data = response.data;
        final errorMsg = (data is Map ? data['error'] : null) ?? 'Error de validación QR';
        throw errorMsg;
      }

      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      if (kDebugMode) dev.log('Error in validateQr', error: e, name: 'ScannerRepository');
      final networkError = ErrorHandler.analyzeError(e);
      if (networkError.isRetryable) {
        await _ref.read(offlineQueueProvider).enqueue(
              PendingOperation(
                id: requestId,
                type: 'validate_ticket',
                payload: payload,
                createdAt: DateTime.now(),
              ),
            );
        throw const OfflineQueuedException(
          'Sin conexión. Validación encolada para sincronizar.',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> validateById({
    required String ticketId,
    required String reason,
    required String? deviceId,
    required String eventId,
    String? pin,
  }) async {
    final requestId = const Uuid().v4();
    final payload = {
      'method': 'id',
      'ticket_id': ticketId,
      'notes': reason,
      'device_id': deviceId,
      'pin': pin,
      'event_id': eventId,
      'request_id': requestId,
    };

    try {
      final response = await _client.functions.invoke('validate_ticket', body: payload);

      if (response.status != 200) {
        final data = response.data;
        final errorMsg = (data is Map ? data['error'] : null) ?? 'Error de validación por ID';
        throw errorMsg;
      }

      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      if (kDebugMode) dev.log('Error in validateById', error: e, name: 'ScannerRepository');
      final networkError = ErrorHandler.analyzeError(e);
      if (networkError.isRetryable) {
        await _ref.read(offlineQueueProvider).enqueue(
              PendingOperation(
                id: requestId,
                type: 'validate_ticket',
                payload: payload,
                createdAt: DateTime.now(),
              ),
            );
        throw const OfflineQueuedException(
          'Sin conexión. Validación encolada para sincronizar.',
        );
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> searchTickets({
    required String query,
    required String type, // 'doc' or 'phone'
    required String eventId,
  }) async {
    try {
      // 1. Gather Context (Auth vs Device)
      final deviceSession = _ref.read(deviceProvider);

      // 2. Call Unified RPC
      final response = await _client.rpc('search_tickets_unified', params: {
        'p_query': query,
        'p_type': type,
        'p_event_id': eventId,
        'p_device_id': deviceSession?.deviceId, // nullable
        'p_device_pin': deviceSession?.pin, // nullable
      });

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) dev.log('Error in searchTickets', error: e, name: 'ScannerRepository');
      rethrow;
    }
  }
}

final scannerRepositoryProvider =
    Provider((ref) => ScannerRepository(Supabase.instance.client, ref));
