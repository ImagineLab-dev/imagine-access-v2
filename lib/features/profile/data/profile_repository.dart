import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/presentation/auth_controller.dart';

/// Datos del perfil del usuario autenticado.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.role,
    this.email,
    this.phone,
    this.avatarUrl,
    this.organizationId,
  });

  final String id;
  final String userId;
  final String displayName;
  final String role;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final String? organizationId;

  factory UserProfile.fromRow(Map<String, dynamic> row, {String? email}) {
    return UserProfile(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      displayName: (row['display_name'] as String?) ?? '',
      role: (row['role'] as String?) ?? '',
      email: email,
      phone: row['phone'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      organizationId: row['organization_id'] as String?,
    );
  }
}

/// Datos de la organización, incluidos los fiscales que usará la facturación.
class OrganizationDetails {
  const OrganizationDetails({
    required this.id,
    required this.name,
    this.legalName,
    this.taxId,
    this.logoUrl,
    this.contactEmail,
    this.contactPhone,
    this.address,
    this.country,
  });

  final String id;
  final String name;
  final String? legalName;
  final String? taxId;
  final String? logoUrl;
  final String? contactEmail;
  final String? contactPhone;
  final String? address;
  final String? country;

  factory OrganizationDetails.fromRow(Map<String, dynamic> row) {
    return OrganizationDetails(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? '',
      legalName: row['legal_name'] as String?,
      taxId: row['tax_id'] as String?,
      logoUrl: row['logo_url'] as String?,
      contactEmail: row['contact_email'] as String?,
      contactPhone: row['contact_phone'] as String?,
      address: row['address'] as String?,
      country: row['country'] as String?,
    );
  }
}

class ProfileException implements Exception {
  const ProfileException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ProfileRepository {
  ProfileRepository(this._client, this._ref);

  final SupabaseClient _client;
  final Ref _ref;

  static const int maxAvatarBytes = 2 * 1024 * 1024; // 2 MB

  User? get _user => _client.auth.currentUser;

  Future<UserProfile?> getProfile() async {
    final user = _user;
    if (user == null) return null;

    final row = await _client
        .from('users_profile')
        .select('id, user_id, display_name, role, phone, avatar_url, organization_id')
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) return null;
    return UserProfile.fromRow(Map<String, dynamic>.from(row), email: user.email);
  }

  /// Actualiza solo los datos personales.
  ///
  /// No expone `role` ni `organization_id` a propósito: cambiarlos es
  /// gestión de equipo, no edición de perfil. La base además lo impide con un
  /// trigger, pero mantenerlo fuera de esta firma evita que alguien lo intente
  /// desde acá y se pregunte por qué no tiene efecto.
  Future<void> updateProfile({
    required String displayName,
    String? phone,
    String? avatarUrl,
  }) async {
    final user = _user;
    if (user == null) throw const ProfileException('no-session');

    final cambios = <String, dynamic>{
      'display_name': displayName.trim(),
      'phone': _vacioANulo(phone),
    };
    // Se distingue "no tocar el avatar" de "borrar el avatar": el primero no
    // manda la clave, el segundo manda null explícito.
    if (avatarUrl != null) {
      cambios['avatar_url'] = avatarUrl.isEmpty ? null : avatarUrl;
    }

    try {
      await _client.from('users_profile').update(cambios).eq('user_id', user.id);
    } catch (e) {
      if (kDebugMode) {
        dev.log('updateProfile failed', error: e, name: 'ProfileRepository');
      }
      rethrow;
    }
  }

  /// Sube el avatar y devuelve su URL pública.
  ///
  /// La ruta empieza con el uid del usuario porque las policies del bucket
  /// exigen que el primer segmento coincida con `auth.uid()`. Cambiar este
  /// formato rompe la escritura con un error de permisos poco descriptivo.
  Future<String> uploadAvatar(Uint8List bytes, String extension) async {
    final user = _user;
    if (user == null) throw const ProfileException('no-session');

    if (bytes.lengthInBytes > maxAvatarBytes) {
      throw const ProfileException('too-large');
    }

    final ext = extension.replaceAll('.', '').toLowerCase();
    // El nombre cambia en cada subida para no pelear con la caché del CDN:
    // reusar el mismo nombre deja la foto vieja visible durante horas.
    final ruta =
        '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from('avatars').uploadBinary(
          ruta,
          bytes,
          fileOptions: FileOptions(
            contentType: _tipoMime(ext),
            upsert: true,
          ),
        );

    return _client.storage.from('avatars').getPublicUrl(ruta);
  }

  Future<OrganizationDetails?> getOrganization() async {
    final orgId = _ref.read(organizationIdProvider);
    if (orgId == null || orgId.isEmpty) return null;

    final row = await _client
        .from('organizations')
        .select(
            'id, name, legal_name, tax_id, logo_url, contact_email, contact_phone, address, country')
        .eq('id', orgId)
        .maybeSingle();

    if (row == null) return null;
    return OrganizationDetails.fromRow(Map<String, dynamic>.from(row));
  }

  /// Solo un admin llega acá: la pantalla oculta el formulario para el resto y
  /// las policies de la tabla lo rechazan igual si alguien lo fuerza.
  Future<void> updateOrganization({
    required String name,
    String? legalName,
    String? taxId,
    String? contactEmail,
    String? contactPhone,
    String? address,
  }) async {
    final orgId = _ref.read(organizationIdProvider);
    if (orgId == null || orgId.isEmpty) {
      throw const ProfileException('no-organization');
    }

    await _client.from('organizations').update({
      'name': name.trim(),
      'legal_name': _vacioANulo(legalName),
      'tax_id': _vacioANulo(taxId),
      'contact_email': _vacioANulo(contactEmail),
      'contact_phone': _vacioANulo(contactPhone),
      'address': _vacioANulo(address),
    }).eq('id', orgId);
  }

  Future<void> changePassword(String nueva) async {
    await _client.auth.updateUser(UserAttributes(password: nueva));
  }

  /// Cierra la sesión en los demás dispositivos, manteniendo la actual.
  Future<void> signOutOtherSessions() async {
    await _client.auth.signOut(scope: SignOutScope.others);
  }

  /// Un campo de texto vacío significa "sin dato", no cadena vacía: guardar ''
  /// ensucia la base y complica los chequeos de "está cargado".
  static String? _vacioANulo(String? valor) {
    if (valor == null) return null;
    final limpio = valor.trim();
    return limpio.isEmpty ? null : limpio;
  }

  static String _tipoMime(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(Supabase.instance.client, ref);
});

final profileProvider = FutureProvider<UserProfile?>((ref) {
  return ref.watch(profileRepositoryProvider).getProfile();
});

final organizationDetailsProvider = FutureProvider<OrganizationDetails?>((ref) {
  return ref.watch(profileRepositoryProvider).getOrganization();
});
