import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Una organización vista desde el panel de super-admin, con sus métricas.
class Tenant {
  const Tenant({
    required this.id,
    required this.name,
    required this.slug,
    required this.status,
    required this.plan,
    this.subscriptionExpiresAt,
    this.taxId,
    this.contactEmail,
    this.createdAt,
    this.usersCount = 0,
    this.eventsCount = 0,
    this.ticketsCount = 0,
    this.lastActivity,
  });

  final String id;
  final String name;
  final String slug;
  final String status;
  final String plan;
  final DateTime? subscriptionExpiresAt;
  final String? taxId;
  final String? contactEmail;
  final DateTime? createdAt;
  final int usersCount;
  final int eventsCount;
  final int ticketsCount;
  final DateTime? lastActivity;

  bool get suspendido => status == 'suspended';

  /// Días que faltan para el vencimiento. Negativo si ya venció, null si la
  /// organización no tiene fecha de vencimiento cargada.
  int? get diasParaVencer {
    final vence = subscriptionExpiresAt;
    if (vence == null) return null;
    return vence.difference(DateTime.now()).inDays;
  }

  bool get vencida {
    final d = diasParaVencer;
    return d != null && d < 0;
  }

  static DateTime? _fecha(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  factory Tenant.fromRow(Map<String, dynamic> r) {
    return Tenant(
      id: r['id'] as String,
      name: (r['name'] as String?) ?? '',
      slug: (r['slug'] as String?) ?? '',
      status: (r['status'] as String?) ?? 'active',
      plan: (r['plan'] as String?) ?? 'trial',
      subscriptionExpiresAt: _fecha(r['subscription_expires_at']),
      taxId: r['tax_id'] as String?,
      contactEmail: r['contact_email'] as String?,
      createdAt: _fecha(r['created_at']),
      usersCount: (r['users_count'] as num?)?.toInt() ?? 0,
      eventsCount: (r['events_count'] as num?)?.toInt() ?? 0,
      ticketsCount: (r['tickets_count'] as num?)?.toInt() ?? 0,
      lastActivity: _fecha(r['last_activity']),
    );
  }
}

/// Una entrada del registro de auditoría.
class AuditEntry {
  const AuditEntry({
    required this.action,
    required this.createdAt,
    this.actorEmail,
    this.organizationName,
  });

  final String action;
  final DateTime createdAt;
  final String? actorEmail;
  final String? organizationName;

  factory AuditEntry.fromRow(Map<String, dynamic> r) => AuditEntry(
        action: (r['action'] as String?) ?? '',
        createdAt:
            DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        actorEmail: r['actor_email'] as String?,
        organizationName: r['organization_name'] as String?,
      );
}

class TenantRepository {
  TenantRepository(this._client);

  final SupabaseClient _client;

  /// Las organizaciones ajenas NO se pueden leer con un select normal: las
  /// policies filtran por pertenencia. Todo pasa por funciones que verifican
  /// `is_superadmin()` del lado del servidor, así que un cliente manipulado no
  /// consigue nada.
  Future<List<Tenant>> listTenants() async {
    final filas = await _client.rpc('superadmin_list_tenants') as List<dynamic>;
    return filas
        .map((f) => Tenant.fromRow(Map<String, dynamic>.from(f as Map)))
        .toList();
  }

  Future<void> setStatus(String organizationId, String status,
      {String? reason}) async {
    await _client.rpc('superadmin_set_status', params: {
      'p_organization_id': organizationId,
      'p_status': status,
      'p_reason': reason,
    });
  }

  Future<void> setSubscription(
    String organizationId, {
    required String plan,
    DateTime? expiresAt,
  }) async {
    await _client.rpc('superadmin_set_subscription', params: {
      'p_organization_id': organizationId,
      'p_plan': plan,
      'p_expires_at': expiresAt?.toUtc().toIso8601String(),
    });
  }

  /// Mueve al super-admin a esa organización para ver la app como el cliente.
  ///
  /// No emite otro token ni cambia de identidad: solo cambia su pertenencia, y
  /// queda registrado en la auditoría. Así RLS sigue aplicando sin excepciones
  /// especiales, que es donde suelen aparecer los agujeros.
  Future<void> impersonate(String organizationId) async {
    await _client.rpc('superadmin_impersonate', params: {
      'p_organization_id': organizationId,
    });
  }

  Future<List<AuditEntry>> recentAudit({int limit = 30}) async {
    final filas = await _client
        .from('superadmin_audit')
        .select('action, created_at, actor_email, organization_name')
        .order('created_at', ascending: false)
        .limit(limit);
    return (filas as List<dynamic>)
        .map((f) => AuditEntry.fromRow(Map<String, dynamic>.from(f as Map)))
        .toList();
  }
}

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  return TenantRepository(Supabase.instance.client);
});

final tenantsProvider = FutureProvider<List<Tenant>>((ref) {
  return ref.watch(tenantRepositoryProvider).listTenants();
});

final superadminAuditProvider = FutureProvider<List<AuditEntry>>((ref) {
  return ref.watch(tenantRepositoryProvider).recentAudit();
});
