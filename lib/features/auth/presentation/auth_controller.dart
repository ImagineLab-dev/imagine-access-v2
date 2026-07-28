import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/app_roles.dart';
import '../../../core/platform/captcha.dart';
import '../../events/data/event_repository.dart';
import '../../events/presentation/event_state.dart';

// State classes
class DeviceSession {
  final String deviceId; // Internal UUID for RPC calls
  final String alias; // Human-readable name for login
  final String pin;
  final String? organizationId;
  DeviceSession(
      {required this.deviceId, required this.alias, required this.pin, this.organizationId});
}

class UserOrganization {
  final String id;
  final String name;
  final String slug;

  UserOrganization({required this.id, required this.name, required this.slug});

  factory UserOrganization.fromJson(Map<String, dynamic> json) {
    return UserOrganization(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
    );
  }
}

// Global Providers
final userProvider =
    StateProvider<User?>((ref) => Supabase.instance.client.auth.currentUser);

final deviceProvider = StateNotifierProvider<DeviceNotifier, DeviceSession?>(
    (ref) => DeviceNotifier());

// Organization Provider - derived from user metadata or local storage
final userOrganizationProvider =
    StateNotifierProvider<OrganizationNotifier, UserOrganization?>((ref) {
  return OrganizationNotifier();
});

class OrganizationNotifier extends StateNotifier<UserOrganization?> {
  OrganizationNotifier() : super(null) {
    _loadOrganization().then((_) => _ready.complete()).catchError((e) {
      if (!_ready.isCompleted) _ready.complete();
    });
  }

  final Completer<void> _ready = Completer<void>();
  Future<void> get ready => _ready.future;

  static const String _orgIdKey = 'user_org_id';
  static const String _orgNameKey = 'user_org_name';
  static const String _orgSlugKey = 'user_org_slug';

  Future<void> _loadOrganization() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_orgIdKey);
    final name = prefs.getString(_orgNameKey);
    final slug = prefs.getString(_orgSlugKey);
    if (id != null && name != null && slug != null) {
      state = UserOrganization(id: id, name: name, slug: slug);
    }
  }

  Future<void> setOrganization(String id, String name, String slug) async {
    state = UserOrganization(id: id, name: name, slug: slug);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_orgIdKey, id);
    await prefs.setString(_orgNameKey, name);
    await prefs.setString(_orgSlugKey, slug);
  }

  Future<void> clearOrganization() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_orgIdKey);
    await prefs.remove(_orgNameKey);
    await prefs.remove(_orgSlugKey);
  }
}

class DeviceNotifier extends StateNotifier<DeviceSession?> {
  DeviceNotifier() : super(null) {
    _loadSession().then((_) => _ready.complete()).catchError((e) {
      if (!_ready.isCompleted) _ready.complete();
    });
  }

  final Completer<void> _ready = Completer<void>();
  Future<void> get ready => _ready.future;

  static const String _deviceIdKey = 'auth_device_id';
  static const String _deviceAliasKey = 'auth_device_alias';
  static const String _devicePinKey = 'auth_device_pin';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_deviceIdKey);
    final alias = prefs.getString(_deviceAliasKey);
    final pin = await _secureStorage.read(key: _devicePinKey);
    if (id != null && alias != null && pin != null) {
      final orgId = prefs.getString('${_deviceIdKey}_org');
      state = DeviceSession(deviceId: id, alias: alias, pin: pin, organizationId: orgId);
    }
  }

  Future<void> setSession(String deviceId, String alias, String pin, {String? organizationId}) async {
    state = DeviceSession(deviceId: deviceId, alias: alias, pin: pin, organizationId: organizationId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, deviceId);
    await prefs.setString(_deviceAliasKey, alias);
    await _secureStorage.write(key: _devicePinKey, value: pin);
    await prefs.remove(_devicePinKey);
    if (organizationId != null) {
      await prefs.setString('${_deviceIdKey}_org', organizationId);
    }
  }

  Future<void> clearSession() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_deviceAliasKey);
    await prefs.remove(_devicePinKey);
    await prefs.remove('${_deviceIdKey}_org');
    await _secureStorage.delete(key: _devicePinKey);
  }
}

// Role Provider (derived from user metadata, with DB fallback)
final userRoleProvider = Provider<String>((ref) {
  // Device sessions are always 'door' role
  final device = ref.watch(deviceProvider);
  if (device != null) return AppRoles.door;

  final user = ref.watch(userProvider);
  if (user == null) return 'guest';

  // Check app_metadata for 'role' (set by our SQL trigger/Edge Function)
  final appMeta = user.appMetadata;
  final role = appMeta['role'] as String?;
  if (role != null && role.isNotEmpty) return role;

  // Fallback: check user_metadata (set during invite)
  final userMeta = user.userMetadata;
  final userMetaRole = userMeta?['role'] as String?;
  if (userMetaRole != null && userMetaRole.isNotEmpty) return userMetaRole;

  // SECURITY: default to 'guest' instead of 'rrpp' to prevent privilege escalation
  return 'guest';
});

// Organization ID from metadata (for API calls)
final organizationIdProvider = Provider<String?>((ref) {
  final cachedOrg = ref.watch(userOrganizationProvider);
  if (cachedOrg != null && cachedOrg.id.isNotEmpty) {
    return cachedOrg.id;
  }

  final user = ref.watch(userProvider);
  final metadataOrgId = user?.appMetadata['organization_id'] as String?;
  if (metadataOrgId != null && metadataOrgId.isNotEmpty) {
    return metadataOrgId;
  }

  // Fallback: check user_metadata
  final userMetaOrgId = user?.userMetadata?['organization_id'] as String?;
  if (userMetaOrgId != null && userMetaOrgId.isNotEmpty) {
    return userMetaOrgId;
  }

  // Fallback: check device session
  final device = ref.watch(deviceProvider);
  if (device?.organizationId != null && device!.organizationId!.isNotEmpty) {
    return device.organizationId;
  }

  return null;
});

// Auth Logic
class AuthController extends StateNotifier<bool> {
  AuthController(this.ref) : super(false);
  final Ref ref;

  Future<String> ensureOrganizationReady() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      throw const AuthException('No authenticated user');
    }

    String? orgId = user.appMetadata['organization_id'] as String?;
    final cachedOrg = ref.read(userOrganizationProvider);
    orgId ??= cachedOrg?.id;

    if (orgId != null && orgId.isNotEmpty) {
      Map<String, dynamic>? existing;
      try {
        existing = await client
            .from('organizations')
            .select('id, name, slug')
            .eq('id', orgId)
            .maybeSingle();
      } on PostgrestException catch (e) {
        final isJwtError = e.code == 'PGRST301' ||
            e.message.toLowerCase().contains('jwt') ||
            e.message.toLowerCase().contains('unauthorized');
        if (!isJwtError) rethrow;

        final refreshed = await client.auth.refreshSession();
        if (refreshed.session == null) {
          throw const AuthException('Session expired. Please log in again.');
        }

        ref.read(userProvider.notifier).state = refreshed.user;
        existing = await client
            .from('organizations')
            .select('id, name, slug')
            .eq('id', orgId)
            .maybeSingle();
      }

      if (existing != null) {
        final org = Map<String, dynamic>.from(existing);
        await ref.read(userOrganizationProvider.notifier).setOrganization(
              org['id'] as String,
              (org['name'] as String?) ?? 'Organization',
              (org['slug'] as String?) ?? 'org',
            );
        return orgId;
      }
    }

    final displayName = (user.userMetadata?['display_name'] as String?) ??
        user.email?.split('@').first ??
        'User';

    Future<FunctionResponse> invokeEnsureProfile() {
      return client.functions.invoke(
        'ensure_profile',
        body: {
          'user_id': user.id,
          'email': user.email,
          'display_name': displayName,
          'organization_name': cachedOrg?.name,
        },
      );
    }

    FunctionResponse result;
    try {
      result = await invokeEnsureProfile();
    } on FunctionException catch (e) {
      final details = (e.details ?? '').toString().toLowerCase();
      final isJwtError = e.status == 401 ||
          details.contains('invalid jwt') ||
          details.contains('unauthorized');

      if (!isJwtError) rethrow;

      final refreshed = await client.auth.refreshSession();
      if (refreshed.session == null) {
        throw const AuthException('Session expired. Please log in again.');
      }

      ref.read(userProvider.notifier).state = refreshed.user;
      result = await invokeEnsureProfile();
    }

    if (result.status != 200) {
      throw const AuthException('Could not initialize organization');
    }

    final data = Map<String, dynamic>.from(result.data as Map);
    final rawOrg = data['organization'];
    if (rawOrg == null || rawOrg is! Map) {
      throw const AuthException('Organization data missing from server response');
    }
    final org = Map<String, dynamic>.from(rawOrg);

    await ref.read(userOrganizationProvider.notifier).setOrganization(
          (org['id'] as String?) ?? (throw const AuthException('Organization ID missing')),
          (org['name'] as String?) ?? 'Organization',
          (org['slug'] as String?) ?? 'org',
        );

    final refreshed = await client.auth.refreshSession();
    if (refreshed.user != null) {
      ref.read(userProvider.notifier).state = refreshed.user;
    }

    return org['id'] as String;
  }

  // 1. Admin/RRPP Login (Supabase Auth)
  Future<void> loginEmail(String email, String password) async {
    state = true; // Loading
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
        captchaToken: await tokenCaptcha(),
      );
      if (response.user != null) {
        ref.read(userProvider.notifier).state = response.user;

        // Always call ensure_profile to verify/fix role and sync JWT metadata
        try {
          await Supabase.instance.client.functions.invoke(
            'ensure_profile',
            body: {
              'user_id': response.user!.id,
              'email': email,
            },
          );
        } catch (e) {
          if (kDebugMode) dev.log('Role sync on login failed (non-blocking): $e');
        }

        // Always refresh session to pick up app_metadata set by DB triggers
        try {
          final refreshed =
              await Supabase.instance.client.auth.refreshSession();
          if (refreshed.user != null) {
            ref.read(userProvider.notifier).state = refreshed.user;
          }
        } catch (e) {
          if (kDebugMode) dev.log('Session refresh failed (non-blocking): $e');
        }

        // Load organization from (now up-to-date) metadata
        final user = ref.read(userProvider);
        final appMeta = user?.appMetadata ?? {};
        var orgId = appMeta['organization_id'] as String?;
        var orgName = appMeta['organization_name'] as String?;
        var orgSlug = appMeta['organization_slug'] as String?;

        // Fallback: if app_metadata didn't sync, query users_profile directly
        if (orgId == null || orgId.isEmpty) {
          if (user == null) return;
          try {
            final profile = await Supabase.instance.client
                .from('users_profile')
                .select('organization_id, role, organizations(name, slug)')
                .eq('user_id', user.id)
                .maybeSingle();
            if (profile != null) {
              orgId = profile['organization_id'] as String?;
              final org = profile['organizations'] as Map<String, dynamic>?;
              orgName = org?['name'] as String?;
              orgSlug = org?['slug'] as String?;
            }
          } catch (e) {
            if (kDebugMode) dev.log('Profile fallback query failed: $e');
          }
        }

        if (orgId != null && orgName != null && orgSlug != null) {
          await ref
              .read(userOrganizationProvider.notifier)
              .setOrganization(orgId, orgName, orgSlug);
        }

        // Force fresh event data for the new user session
        ref.read(eventRepositoryProvider).clearCache();
        ref.invalidate(eventsProvider);
      }
    } catch (e) {
      rethrow;
    } finally {
      state = false;
    }
  }

  // Shared logic: create profile + org via ensure_profile with retries
  Future<void> _setupProfileAndOrg({
    required String userId,
    required String email,
    required String displayName,
    required String organizationName,
    String? country,
  }) async {
    bool profileCreated = false;
    for (int attempt = 0; attempt < 3 && !profileCreated; attempt++) {
      try {
        final result = await Supabase.instance.client.functions.invoke(
          'ensure_profile',
          body: {
            'user_id': userId,
            'email': email,
            'display_name': displayName,
            'organization_name': organizationName,
            'country': country,
          },
        );

        if (kDebugMode) dev.log('ensure_profile response: ${result.data}');

        final data = result.data as Map<String, dynamic>;
        final org = data['organization'] as Map<String, dynamic>?;

        if (org != null) {
          await ref.read(userOrganizationProvider.notifier).setOrganization(
                org['id'] as String,
                org['name'] as String,
                org['slug'] as String,
              );
        }

        var refreshed = await Supabase.instance.client.auth.refreshSession();
        ref.read(userProvider.notifier).state = refreshed.user;

        final actualRole = refreshed.user?.appMetadata['role'] as String?;
        if (actualRole != 'admin') {
          await Future.delayed(const Duration(milliseconds: 600));
          refreshed = await Supabase.instance.client.auth.refreshSession();
          ref.read(userProvider.notifier).state = refreshed.user;
        }
        profileCreated = true;
      } catch (e) {
        if (kDebugMode) dev.log('ensure_profile attempt ${attempt + 1} failed: $e');
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }

    if (!profileCreated) {
      if (kDebugMode) dev.log('WARNING: profile/org not set after 3 attempts, checking trigger');
      await Future.delayed(const Duration(milliseconds: 800));
      final lastChance = await Supabase.instance.client.auth.refreshSession();
      if (lastChance.user != null) {
        ref.read(userProvider.notifier).state = lastChance.user;
        final role = lastChance.user!.appMetadata['role'] as String?;
        if (role != null && role != 'guest') {
          profileCreated = true;
        }
      }
    }

    if (!profileCreated) {
      throw Exception(
          'Could not create organization profile. Please try again.');
    }

    // Ensure SharedPreferences has org data
    final currentOrg = ref.read(userOrganizationProvider);
    if (currentOrg == null) {
      final meta = ref.read(userProvider)?.appMetadata;
      final orgId = meta?['organization_id'] as String?;
      final orgName = meta?['organization_name'] as String?;
      final orgSlug = meta?['organization_slug'] as String?;
      if (orgId != null && orgName != null && orgSlug != null) {
        await ref.read(userOrganizationProvider.notifier).setOrganization(orgId, orgName, orgSlug);
      }
    }
  }

  // 1b. Admin/RRPP Sign Up - Creates NEW ORGANIZATION automatically
  Future<void> signUpEmail(String email, String password, String displayName,
      String organizationName,
      {String? country}) async {
    state = true;
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
        captchaToken: await tokenCaptcha(),
      );
      if (response.user != null && response.session == null) {
        // Email confirmation required — OTP sent, stop here
        if (kDebugMode) dev.log('signUpEmail: email confirmation required, OTP sent');
        return;
      }
      if (response.user != null) {
        ref.read(userProvider.notifier).state = response.user;
        await _setupProfileAndOrg(
          userId: response.user!.id,
          email: email,
          displayName: displayName,
          organizationName: organizationName,
          country: country,
        );

        // Final verification: ensure role is 'admin' for new signups
        final finalUser = ref.read(userProvider);
        final finalRole =
            finalUser?.appMetadata['role'] as String?;
        if (finalRole != 'admin') {
          if (kDebugMode) {
            dev.log(
                'WARNING: Role after signup is "$finalRole" instead of "admin". Forcing refresh.');
          }
          await Future.delayed(const Duration(milliseconds: 500));
          final corrected =
              await Supabase.instance.client.auth.refreshSession();
          if (corrected.user != null) {
            ref.read(userProvider.notifier).state = corrected.user;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) dev.log('signUpEmail FAILED: $e', name: 'AuthController');
      rethrow;
    } finally {
      state = false;
    }
  }

  // 1c. Verify OTP and setup profile after email confirmation
  Future<void> verifyOtpAndSetupProfile(
      String email, String otp, String displayName, String organizationName,
      {String? country}) async {
    state = true;
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.signup,
      );

      if (response.user == null || response.session == null) {
        throw Exception('Invalid OTP code');
      }

      ref.read(userProvider.notifier).state = response.user;
      await _setupProfileAndOrg(
        userId: response.user!.id,
        email: email,
        displayName: displayName,
        organizationName: organizationName,
      );

      ref.read(eventRepositoryProvider).clearCache();
      ref.invalidate(eventsProvider);
    } catch (e) {
      rethrow;
    } finally {
      state = false;
    }
  }

  // 1d. Resend OTP for email verification
  Future<void> resendOtp(String email) async {
    await Supabase.instance.client.auth.resend(
      type: OtpType.signup,
      email: email,
      captchaToken: await tokenCaptcha(),
    );
  }

  // 2. Door Login (Alias + PIN)
  Future<void> loginDevice(String alias, String pin) async {
    state = true;
    try {
      // Call Edge Function to validate credentials securely
      final response = await Supabase.instance.client.functions.invoke(
        'login_device',
        body: {'alias': alias, 'pin': pin},
      );

      if (response.status != 200) {
        throw const AuthException('Invalid or disabled device credentials');
      }

      // Extract deviceId from response for RPC calls
      final data = response.data as Map<String, dynamic>;
      final deviceId = data['device']?['id'] as String? ?? '';
      final deviceOrgId = data['device']?['organization_id'] as String?;

      // Store session locally (deviceId for RPCs, alias for display)
      await ref.read(deviceProvider.notifier).setSession(deviceId, alias, pin, organizationId: deviceOrgId);

      // Load organization info if available
      final org = data['organization'] as Map<String, dynamic>?;
      if (org != null) {
        await ref
            .read(userOrganizationProvider.notifier)
            .setOrganization(
              org['id'] as String,
              org['name'] as String,
              org['slug'] as String? ?? '',
            );
      }
    } catch (e) {
      // Map generic function errors to user-friendly message
      if (e is FunctionException) {
        throw const AuthException('Invalid credentials');
      }
      rethrow;
    } finally {
      state = false;
    }
  }

  Future<void> logout() async {
    try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
    ref.read(userProvider.notifier).state = null;
    try { await ref.read(deviceProvider.notifier).clearSession(); } catch (_) {}
    try { await ref.read(userOrganizationProvider.notifier).clearOrganization(); } catch (_) {}
    try { await ref.read(selectedEventProvider.notifier).clearEvent(); } catch (_) {}
    ref.read(eventRepositoryProvider).clearCache();
    ref.invalidate(eventsProvider);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, bool>((ref) {
  return AuthController(ref);
});
