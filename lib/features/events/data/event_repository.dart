import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/constants/app_roles.dart';
import '../../../core/utils/ttl_cache.dart';

class EventRepository {
  final SupabaseClient _client;
  final TtlCacheStore _cacheStore;

  EventRepository(this._client, {TtlCacheStore? cacheStore})
      : _cacheStore = cacheStore ?? InMemoryTtlCacheStore();

  void clearCache() => _cacheStore.clear();

  String? _safeCurrentUserId() {
    try {
      return _client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  User? _safeCurrentUser() {
    try {
      return _client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _getEventsForDevice(
      String deviceId, String organizationId, String? devicePin) async {
    final cacheKey = 'events::device=$deviceId::org=$organizationId';
    final cached = _cacheStore.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null && cached.isValidAt(DateTime.now())) {
      return cached.value;
    }

    try {
      final response = await _client.functions.invoke(
        'device_events',
        // El PIN va también acá. Antes bastaba con conocer los dos UUID para
        // listar todos los eventos con sus tipos y precios: el id del
        // dispositivo funcionaba como credencial por sí solo, así que el de uno
        // dado de baja seguía sirviendo aunque le cambiaran el PIN.
        body: {
          'device_id': deviceId,
          'organization_id': organizationId,
          'pin': devicePin,
        },
      );
      if (response.status != 200) return [];
      final data = response.data as Map<String, dynamic>;
      final events = List<Map<String, dynamic>>.from(data['events'] ?? []);
      _cacheStore.set<List<Map<String, dynamic>>>(
        cacheKey, events, ttl: const Duration(minutes: 5));
      return events;
    } catch (_) {
      if (cached != null) return cached.value;
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getEvents(
      {bool includeArchived = false,
      String? organizationId,
      String? userRole,
      String? deviceId,
      String? devicePin}) async {
    final currentUserId = _safeCurrentUserId();

    // Device session: use Edge Function (no Supabase auth, RLS would block)
    if (currentUserId == null && deviceId != null && organizationId != null) {
      return _getEventsForDevice(deviceId, organizationId, devicePin);
    }

    String? resolvedOrganizationId = organizationId;
    if ((resolvedOrganizationId == null || resolvedOrganizationId.isEmpty) &&
        currentUserId != null) {
      try {
        final profile = await _client
            .from('users_profile')
            .select('organization_id')
            .eq('user_id', currentUserId)
            .maybeSingle();
        resolvedOrganizationId = profile?['organization_id'] as String?;
      } catch (_) {
        // Profile lookup failed - no fallback to userMetadata (security risk)
      }
    }

    // SECURITY: no org and no user context means no access scope
    if ((resolvedOrganizationId == null || resolvedOrganizationId.isEmpty) &&
        currentUserId == null) {
      return [];
    }

    final cacheKey =
      'events::org=$resolvedOrganizationId::user=$currentUserId::includeArchived=$includeArchived';
    final cached = _cacheStore.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null && cached.isValidAt(DateTime.now())) {
      return cached.value;
    }

    try {
      var query = _client.from('events').select('*, ticket_types(*)');

      if (!includeArchived) {
        query = query.eq('is_archived', false);
      }

      if (resolvedOrganizationId != null &&
          resolvedOrganizationId.isNotEmpty &&
          currentUserId != null) {
        query = query
            .or('organization_id.eq.$resolvedOrganizationId,created_by.eq.$currentUserId');
      } else if (resolvedOrganizationId != null &&
          resolvedOrganizationId.isNotEmpty) {
        query = query.eq('organization_id', resolvedOrganizationId);
      } else if (currentUserId != null) {
        query = query.eq('created_by', currentUserId);
      }

      final response = await query.order('date', ascending: true);
      var mapped = List<Map<String, dynamic>>.from(response);

      // For non-admin roles (except door), filter events to only those assigned in event_staff
      // or created by the current user. Door role sees all org events (they scan at any event).
      if (currentUserId != null &&
          userRole != null &&
          !AppRoles.isAdmin(userRole) &&
          userRole != AppRoles.door) {
        try {
          final staffAssignments = await _client
              .from('event_staff')
              .select('event_id')
              .eq('user_id', currentUserId);
          final assignedEventIds = List<Map<String, dynamic>>.from(staffAssignments)
              .map((s) => s['event_id'] as String)
              .toSet();
          mapped = mapped
              .where((e) =>
                  assignedEventIds.contains(e['id'] as String) ||
                  e['created_by'] == currentUserId)
              .toList();
        } catch (e) {
          if (kDebugMode) dev.log('event_staff filter failed, showing all org events: $e', name: 'EventRepository');
        }
      }

      _cacheStore.set<List<Map<String, dynamic>>>(
        cacheKey,
        mapped,
        ttl: const Duration(minutes: 5),
      );
      return mapped;
    } catch (_) {
      if (cached != null) {
        return cached.value;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createEvent({
    required String name,
    required String venue,
    required String address,
    required String city,
    required DateTime date,
    required String slug,
    required String currency,
    String timezone = 'America/Asuncion',
    String? organizationId,
  }) async {
    final currentUser = _safeCurrentUser();
    final metadataOrgId = currentUser?.appMetadata['organization_id'] as String?;
    String? resolvedOrganizationId =
        organizationId ?? metadataOrgId;

    if ((resolvedOrganizationId == null || resolvedOrganizationId.isEmpty) &&
        currentUser != null) {
      try {
        final profile = await _client
            .from('users_profile')
            .select('organization_id')
            .eq('user_id', currentUser.id)
            .maybeSingle();
        resolvedOrganizationId = profile?['organization_id'] as String?;
      } catch (_) {
        // Error handled by final validation below.
      }
    }

    if (resolvedOrganizationId == null || resolvedOrganizationId.isEmpty) {
      throw Exception(
          'No organization found for current user. Please sign in again.');
    }

    final insertData = {
      'name': name,
      'venue': venue,
      'address': address,
      'city': city,
      'date': date.toIso8601String(),
      'slug': slug,
      'currency': currency,
      'timezone': timezone,
      'is_active': true,
      'is_archived': false,
      'organization_id': resolvedOrganizationId,
      if (currentUser != null) 'created_by': currentUser.id,
    };

    final response =
        await _client.from('events').insert(insertData).select().single();

    // Auto-assign creator to event_staff so they can see the event
    if (currentUser != null) {
      final userRole = currentUser.appMetadata['role'] as String? ?? 'rrpp';
      try {
        await _client.from('event_staff').upsert({
          'event_id': response['id'],
          'user_id': currentUser.id,
          'role': userRole,
        });
      } catch (_) {
        // Non-critical: creator can still see via created_by fallback
      }
    }

    return response;
  }

  Future<Map<String, dynamic>> updateEvent(
      String id, Map<String, dynamic> data) async {
    final response = await _client
        .from('events')
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return response;
  }

  Future<void> deleteEvent(String id) async {
    // Soft delete (archive) preferred, but Admin can hard delete if no tickets exist
    await _client.from('events').delete().eq('id', id);
  }

  Future<void> archiveEvent(String id) async {
    await _client
        .from('events')
        .update({'is_archived': true, 'is_active': false}).eq('id', id);
  }

  Future<void> unarchiveEvent(String id) async {
    await _client
        .from('events')
        .update({'is_archived': false, 'is_active': true}).eq('id', id);
  }

  // Ticket Types Management
  Future<void> createTicketType({
    required String eventId,
    required String name,
    required double price,
    required String currency,
    String category = 'standard',
    DateTime? validUntil,
    int toleranceMinutes = 0,
    String? color,
    int? promoQty, // for promo category: number of tickets in the pack
  }) async {
    await _client.from('ticket_types').insert({
      'event_id': eventId,
      'name': name,
      'price': price,
      'currency': currency,
      'category': category,
      'valid_until': validUntil?.toIso8601String(),
      'tolerance_minutes': toleranceMinutes,
      'color': color,
      'is_active': true,
      if (promoQty != null && promoQty > 1) 'promo_qty': promoQty,
    });
    _cacheStore.invalidate('ticket_types:$eventId');
  }

  Future<void> updateTicketType(String id, Map<String, dynamic> data, {String? eventId}) async {
    await _client.from('ticket_types').update(data).eq('id', id);
    if (eventId != null) _cacheStore.invalidate('ticket_types:$eventId');
  }

  Future<void> deleteTicketType(String id, {String? eventId}) async {
    await _client.from('ticket_types').delete().eq('id', id);
    if (eventId != null) _cacheStore.invalidate('ticket_types:$eventId');
  }
}

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(Supabase.instance.client);
});

final eventsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repository = ref.watch(eventRepositoryProvider);
  final orgId = ref.watch(organizationIdProvider);
  final role = ref.watch(userRoleProvider);
  final device = ref.watch(deviceProvider);
  return repository.getEvents(
    includeArchived: true,
    organizationId: orgId,
    userRole: role,
    deviceId: device?.deviceId,
    devicePin: device?.pin,
  );
});
