import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import '../../events/presentation/event_state.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/ttl_cache.dart';
import '../../auth/presentation/auth_controller.dart';

class DashboardRepository {
  final SupabaseClient _client;
  final TtlCacheStore _cacheStore;

  DashboardRepository(this._client, {TtlCacheStore? cacheStore})
      : _cacheStore = cacheStore ?? InMemoryTtlCacheStore();

  Future<Map<String, dynamic>> getMetrics(String? eventId) async {
    if (eventId == null) return {};

    final cacheKey = 'dashboard:metrics:$eventId';
    final cached = _cacheStore.get<Map<String, dynamic>>(cacheKey);
    if (cached != null && cached.isValidAt(DateTime.now())) {
      return cached.value;
    }

    try {
      final response = await _client.rpc(
        'get_staff_dashboard',
        params: {'p_event_id': eventId},
      );
      if (kDebugMode) dev.log('get_staff_dashboard response type: ${response.runtimeType}, value: $response', name: 'DashboardRepo');
      final mapped = Map<String, dynamic>.from(response);
      _cacheStore.set(cacheKey, mapped, ttl: const Duration(minutes: 1));
      return mapped;
    } catch (e, st) {
      if (kDebugMode) dev.log('getMetrics FAILED: $e', name: 'DashboardRepo', error: e, stackTrace: st);
      ErrorHandler.logError('getMetrics', e, source: 'DashboardRepository');
      if (cached != null) return cached.value;
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getRecentActivity(String? eventId) async {
    if (eventId == null) return [];

    final cacheKey = 'dashboard:recent:$eventId';
    final cached = _cacheStore.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null && cached.isValidAt(DateTime.now())) {
      return cached.value;
    }

    try {
      final response = await _client
          .from('checkins')
          .select(
              '*, tickets(buyer_name, type, users_profile!created_by(display_name))')
          .eq('event_id', eventId)
          .order('scanned_at', ascending: false)
          .limit(3);
      final mapped = List<Map<String, dynamic>>.from(response);
      _cacheStore.set(cacheKey, mapped, ttl: const Duration(seconds: 30));
      return mapped;
    } catch (e) {
      ErrorHandler.logError(
        'getRecentActivity',
        e,
        source: 'DashboardRepository',
      );
      if (cached != null) return cached.value;
      return [];
    }
  }

  Future<Map<String, dynamic>> getStats(String? eventId) async {
    if (eventId == null) return {};

    final cacheKey = 'dashboard:stats:$eventId';
    final cached = _cacheStore.get<Map<String, dynamic>>(cacheKey);
    if (cached != null && cached.isValidAt(DateTime.now())) {
      return cached.value;
    }

    try {
      final response = await _client.rpc(
        'get_event_statistics',
        params: {'p_event_id': eventId},
      );
      final mapped = Map<String, dynamic>.from(response);
      _cacheStore.set(cacheKey, mapped, ttl: const Duration(minutes: 1));
      return mapped;
    } catch (e) {
      ErrorHandler.logError('getStats', e, source: 'DashboardRepository');
      if (cached != null) return cached.value;
      return {};
    }
  }

  /// Fetch metrics via device_dashboard EF for device sessions
  Future<Map<String, dynamic>> getMetricsForDevice(
      String eventId, String deviceId, String pin) async {
    try {
      final response = await _client.functions.invoke('device_dashboard',
          body: {'device_id': deviceId, 'pin': pin, 'event_id': eventId});
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (data['error'] != null) {
        return {'error': data['error'].toString()};
      }
      return Map<String, dynamic>.from(data['metrics'] ?? {});
    } on FunctionException catch (e) {
      ErrorHandler.logError('getMetricsForDevice', e, source: 'DashboardRepository');
      return {'error': 'device_dashboard_error'};
    } catch (e) {
      ErrorHandler.logError('getMetricsForDevice', e, source: 'DashboardRepository');
      return {'error': 'device_dashboard_error'};
    }
  }

  /// Fetch recent activity via device_dashboard EF
  Future<List<Map<String, dynamic>>> getRecentActivityForDevice(
      String eventId, String deviceId, String pin) async {
    try {
      final response = await _client.functions.invoke('device_dashboard',
          body: {'device_id': deviceId, 'pin': pin, 'event_id': eventId});
      final data = Map<String, dynamic>.from(response.data);
      return List<Map<String, dynamic>>.from(data['recent'] ?? []);
    } catch (e) {
      ErrorHandler.logError('getRecentActivityForDevice', e,
          source: 'DashboardRepository');
      return [];
    }
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(Supabase.instance.client);
});

final eventStatsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, eventId) async {
  return ref.watch(dashboardRepositoryProvider).getStats(eventId);
});

final dashboardMetricsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final selectedEvent = ref.watch(selectedEventProvider);
  final eventId = selectedEvent?['id'];
  if (kDebugMode) dev.log('dashboardMetricsProvider: eventId=$eventId, device=${ref.read(deviceProvider)}', name: 'DashboardProv');
  if (eventId == null) return {};

  final device = ref.watch(deviceProvider);
  if (device != null) {
    if (kDebugMode) dev.log('Using device path for metrics', name: 'DashboardProv');
    final result = await ref
        .watch(dashboardRepositoryProvider)
        .getMetricsForDevice(eventId, device.deviceId, device.pin);
    return result;
  }
  if (kDebugMode) dev.log('Using user path for metrics', name: 'DashboardProv');
  return ref.watch(dashboardRepositoryProvider).getMetrics(eventId);
});

final recentActivityProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final selectedEvent = ref.watch(selectedEventProvider);
  final eventId = selectedEvent?['id'];
  if (eventId == null) return [];

  final device = ref.watch(deviceProvider);
  if (device != null) {
    return ref
        .watch(dashboardRepositoryProvider)
        .getRecentActivityForDevice(eventId, device.deviceId, device.pin);
  }
  return ref
      .watch(dashboardRepositoryProvider)
      .getRecentActivity(eventId);
});

// REALTIME UPDATER: Listens for changes and invalidates providers
final dashboardRealtimeProvider = Provider.autoDispose<void>((ref) {
  final selectedEvent = ref.watch(selectedEventProvider);
  if (selectedEvent == null) return;

  final eventId = selectedEvent['id'];
  final supabase = Supabase.instance.client;

  if (kDebugMode) dev.log('Dashboard realtime setup event=$eventId', name: 'DashboardRealtime');

  final channel = supabase
      .channel('dashboard_updates_$eventId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'checkins',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'event_id',
          value: eventId,
        ),
        callback: (payload) {
          if (kDebugMode) dev.log('Realtime checkins change', name: 'DashboardRealtime');
          // Invalidate cache so next provider read fetches fresh data
          final repo = ref.read(dashboardRepositoryProvider);
          repo._cacheStore.invalidate('dashboard:metrics:$eventId');
          repo._cacheStore.invalidate('dashboard:recent:$eventId');
          repo._cacheStore.invalidate('dashboard:stats:$eventId');
          ref.invalidate(dashboardMetricsProvider);
          ref.invalidate(recentActivityProvider);
          ref.invalidate(eventStatsProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tickets',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'event_id',
          value: eventId,
        ),
        callback: (payload) {
          if (kDebugMode) dev.log('Realtime tickets change', name: 'DashboardRealtime');
          final repo = ref.read(dashboardRepositoryProvider);
          repo._cacheStore.invalidate('dashboard:metrics:$eventId');
          repo._cacheStore.invalidate('dashboard:recent:$eventId');
          repo._cacheStore.invalidate('dashboard:stats:$eventId');
          ref.invalidate(dashboardMetricsProvider);
          ref.invalidate(recentActivityProvider);
          ref.invalidate(eventStatsProvider);
        },
      )
      .subscribe();

  ref.onDispose(() {
    if (kDebugMode) {
      dev.log('Dashboard realtime disposed event=$eventId',
          name: 'DashboardRealtime');
    }
    supabase.removeChannel(channel);
  });
});
