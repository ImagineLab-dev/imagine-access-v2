import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/ttl_cache.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/utils/tiempo_limite.dart';

class SettingsRepository {
  final SupabaseClient _client;
  final Ref _ref;
  final TtlCacheStore _cacheStore;

  SettingsRepository(this._client, this._ref, {TtlCacheStore? cacheStore})
      : _cacheStore = cacheStore ?? InMemoryTtlCacheStore();

  // --- APP SETTINGS (scoped per organization) ---

  String? _currentOrgId() {
    return _ref.read(organizationIdProvider);
  }

  Future<String> getDefaultCurrency() async {
    final orgId = _currentOrgId();
    try {
      var query = _client
          .from('app_settings')
          .select('setting_value')
          .eq('setting_key', 'default_currency');

      if (orgId != null && orgId.isNotEmpty) {
        query = query.eq('organization_id', orgId);
      }

      final response = await query.maybeSingle();
      return response?['setting_value'] as String? ?? 'PYG';
    } catch (e) {
      if (kDebugMode) {
        dev.log('Error fetching default currency',
            error: e, name: 'SettingsRepository');
      }
      return 'PYG';
    }
  }

  Future<void> updateDefaultCurrency(String currency) async {
    final orgId = _currentOrgId();
    try {
      final data = <String, dynamic>{
        'setting_key': 'default_currency',
        'setting_value': currency,
      };
      if (orgId != null && orgId.isNotEmpty) {
        data['organization_id'] = orgId;
      }
      await _client.from('app_settings').upsert(data);
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        dev.log('Failed to update currency',
            error: e, name: 'SettingsRepository');
      }
      throw Exception('Error al actualizar moneda: ${e.message}');
    } catch (e) {
      if (kDebugMode) {
        dev.log('Unexpected error updating currency',
            error: e, name: 'SettingsRepository');
      }
      throw Exception('Error inesperado al actualizar moneda');
    }
  }

  // --- USER MANAGEMENT (Profiles) ---

  Future<List<Map<String, dynamic>>> getUsers() async {
    const cacheKey = 'settings:users';
    final cached = _cacheStore.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null && cached.isValidAt(DateTime.now())) {
      return cached.value;
    }

    try {
      if (kDebugMode) dev.log('SettingsRepository: Fetching users via get_team_members...', name: 'SettingsRepository');
      // Use Edge Function 'get_team_members' to bypass RLS policies
      // which block 'select' access for standard users.
      final response = await _client.functions.invoke('get_team_members');

      if (kDebugMode) dev.log('get_team_members response status: ${response.status}', name: 'SettingsRepository');
      
      if (response.status != 200) {
        throw Exception('Error fetching members: ${response.status} - Data: ${response.data}');
      }

      // The response.data should be the list
      final List<dynamic> data = response.data;
      if (kDebugMode) dev.log('get_team_members fetched ${data.length} users successfully.', name: 'SettingsRepository');
      final mapped = List<Map<String, dynamic>>.from(data);
      _cacheStore.set(cacheKey, mapped, ttl: const Duration(minutes: 1));
      return mapped;
    } catch (e) {
      if (kDebugMode) dev.log('CRITICAL ERROR in getUsers: $e', error: e, name: 'SettingsRepository');
      ErrorHandler.logError('getUsers', e, source: 'SettingsRepository');
      // Fallback: Return empty list or try direct query if function fails
      return cached?.value ?? [];
    }
  }

  Future<void> createUserProfile({
    required String userId,
    required String role,
    required String displayName,
    String? organizationId,
  }) async {
    try {
      // TODO: Migrar a Edge Function para validación dual y auditoría
      await _client.from('users_profile').insert({
        'user_id': userId,
        'role': role,
        'display_name': displayName,
        'organization_id': ?organizationId,
      });
      _cacheStore.invalidate('settings:users');
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        dev.log('Error creating user profile',
            error: e, name: 'SettingsRepository');
      }
      throw Exception('Error al crear perfil: ${e.message}');
    }
  }

  Future<void> updateUserRole(String userId, String role) async {
    const validRoles = ['admin', 'rrpp', 'door'];
    if (!validRoles.contains(role)) {
      throw Exception('Rol inválido: $role');
    }
    // SECURITY: Prevent assigning 'owner' role via this method
    if (role == 'owner') {
      throw Exception('No se puede asignar el rol owner desde la UI');
    }
    final currentUserId = _client.auth.currentUser?.id;
    if (userId == currentUserId) {
      throw Exception('No puedes cambiar tu propio rol');
    }
    final orgId = _currentOrgId();
    try {
      var query = _client
          .from('users_profile')
          .update({'role': role})
          .eq('user_id', userId);

      // Scope to current organization — org filter is mandatory, never omit it
      if (orgId == null || orgId.isEmpty) {
        throw Exception('No se pudo determinar la organización actual');
      }
      query = query.eq('organization_id', orgId);

      await query;
      _cacheStore.invalidate('settings:users');
    } on PostgrestException catch (e) {
      if (kDebugMode) dev.log('Error updating role', error: e, name: 'SettingsRepository');
      throw Exception('Error al actualizar rol: ${e.message}');
    }
  }

  Future<void> deleteUserProfile(String userId) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (userId == currentUserId) {
      throw Exception('Cannot delete your own account from here');
    }
    try {
      final response = await _client.functions.invoke('delete_user', body: {
        'target_user_id': userId,
      });

      if (response.status != 200) {
        throw Exception('Error deleting user: ${response.data}');
      }

      _cacheStore.invalidate('settings:users');
    } on FunctionException catch (e) {
      if (kDebugMode) {
        dev.log('Function error deleting user profile',
            error: e, name: 'SettingsRepository');
      }
      throw Exception('Error de permisos al eliminar usuario: ${e.details ?? e.reasonPhrase}');
    } catch (e) {
      if (kDebugMode) {
        dev.log('Error deleting user profile',
            error: e, name: 'SettingsRepository');
      }
      throw Exception('Error al eliminar perfil');
    }
  }

  // --- DEVICE MANAGEMENT (Using Edge Function to bypass RLS) ---

  Future<List<Map<String, dynamic>>> getDevices() async {
    const cacheKey = 'settings:devices';
    final cached = _cacheStore.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null && cached.isValidAt(DateTime.now())) {
      return cached.value;
    }

    try {
      final response = await _client.functions
          .invoke('manage_devices', body: {'action': 'list'});
      if (response.status != 200) throw Exception('Status ${response.status}');

      final List<dynamic> data = response.data;
      final mapped = List<Map<String, dynamic>>.from(data);
      _cacheStore.set(cacheKey, mapped, ttl: const Duration(minutes: 1));
      return mapped;
    } catch (e) {
      ErrorHandler.logError('getDevices', e, source: 'SettingsRepository');
      if (cached != null) return cached.value;
      rethrow;
    }
  }

  Future<void> createDevice({
    required String deviceId,
    required String alias,
    required String pinHash,
  }) async {
    try {
      // Intentar con Edge Function primero
      final response = await _client.functions.invoke('manage_devices',
          body: {
            'action': 'create',
            'id': deviceId,
            'device_id': deviceId,
            'alias': alias,
            'pin': pinHash
          });

      if (response.status != 200 && response.status != 201) {
        throw Exception('Server error: ${response.data}');
      }
      _cacheStore.invalidate('settings:devices');
    } on FunctionException catch (fe) {
      if (kDebugMode) {
        dev.log('Edge Function failed for createDevice',
            error: fe, name: 'SettingsRepository');
      }
      throw Exception('Error al registrar dispositivo: ${fe.details ?? fe.reasonPhrase}');
    } catch (e) {
      if (kDebugMode) {
        dev.log('Error creating device', error: e, name: 'SettingsRepository');
      }
      throw Exception('Error al registrar dispositivo');
    }
  }

  Future<void> deleteDevice(String deviceId) async {
    try {
      await _client.functions.invoke('manage_devices',
          body: {'action': 'delete', 'id': deviceId});
      _cacheStore.invalidate('settings:devices');
    } catch (e) {
      if (kDebugMode) dev.log('Error deleting device', error: e, name: 'SettingsRepository');
      throw Exception('Error al eliminar dispositivo');
    }
  }

  Future<void> toggleDevice(String deviceId, bool enabled) async {
    try {
      await _client.functions.invoke('manage_devices',
          body: {'action': 'toggle', 'id': deviceId, 'enabled': enabled});
      _cacheStore.invalidate('settings:devices');
    } catch (e) {
      if (kDebugMode) dev.log('Error toggling device', error: e, name: 'SettingsRepository');
      throw Exception('Error al cambiar estado');
    }
  }

  Future<Map<String, dynamic>> createUser(
      {required String email,
      required String displayName,
      required String role}) async {
    try {
      Future<FunctionResponse> invokeCreateUser() {
        return _client.functions.invoke('create_user', body: {
          'email': email,
          'display_name': displayName,
          'role': role,
          // Idioma para el correo de invitación. Se manda el del admin que
          // invita: no hay forma de saber el del invitado antes de que entre,
          // y quien lo suma casi siempre comparte idioma con él.
          'language': _ref.read(localeProvider).languageCode,
        });
      }

      FunctionResponse response;
      try {
        response = await invokeCreateUser()
            .conLimite(TiempoLimite.conCorreo, 'create_user');
      } on FunctionException catch (e) {
        final details = (e.details ?? '').toString().toLowerCase();
        final isJwtError = e.status == 401 ||
            details.contains('invalid jwt') ||
            details.contains('unauthorized');
        if (!isJwtError) rethrow;

        await _client.auth.refreshSession();
        response = await invokeCreateUser();
      }

      if (response.status != 200) {
        throw Exception('Error creating user: ${response.status}');
      }
      
      _cacheStore.invalidate('settings:users');
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      if (kDebugMode) {
        dev.log('Error creating user via Edge Function',
            error: e, name: 'SettingsRepository');
      }
      throw Exception('Error al crear usuario');
    }
  }
  // --- EVENT STAFF MANAGEMENT (Quotas) ---

  Future<void> manageEventStaff({
    required String eventId,
    required String userId,
    required String role,
    required int quotaStandard,
    required int quotaGuest,
    required int quotaInvitation,
  }) async {
    try {
      await _client.rpc('manage_event_staff', params: {
        'p_event_id': eventId,
        'p_user_id': userId,
        'p_role': role,
        'p_quota_standard': quotaStandard,
        'p_quota_guest': quotaGuest,
        'p_quota_invitation': quotaInvitation,
      });
    } catch (e) {
      ErrorHandler.logError('manageEventStaff', e, source: 'SettingsRepository');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getEventStaff(String eventId) async {
    try {
      final response =
          await _client.from('event_staff').select().eq('event_id', eventId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      ErrorHandler.logError('getEventStaff', e, source: 'SettingsRepository');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getMyEventStaff(
      String eventId, String userId) async {
    try {
      final response = await _client
          .from('event_staff')
          .select()
          .eq('event_id', eventId)
          .eq('user_id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      ErrorHandler.logError('getMyEventStaff', e, source: 'SettingsRepository');
      rethrow;
    }
  }

  Future<void> removeEventStaff({
    required String eventId,
    required String userId,
  }) async {
    try {
      await _client
          .from('event_staff')
          .delete()
          .eq('event_id', eventId)
          .eq('user_id', userId);
    } catch (e) {
      ErrorHandler.logError('removeEventStaff', e, source: 'SettingsRepository');
      rethrow;
    }
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(Supabase.instance.client, ref);
});

final defaultCurrencyProvider = FutureProvider<String>((ref) async {
  return ref.watch(settingsRepositoryProvider).getDefaultCurrency();
});

final usersListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(settingsRepositoryProvider).getUsers();
});

final devicesListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(settingsRepositoryProvider).getDevices();
});
