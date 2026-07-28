import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Estado de la suscripción de la organización del usuario actual.
class Subscription {
  const Subscription({
    required this.organizationId,
    required this.status,
    required this.plan,
    required this.currency,
    required this.isActive,
    this.country,
    this.expiresAt,
    this.daysLeft,
    this.suspendedReason,
  });

  final String organizationId;
  final String status;
  final String plan;
  final String currency;
  final bool isActive;
  final String? country;
  final DateTime? expiresAt;
  final int? daysLeft;
  final String? suspendedReason;

  bool get enPrueba => plan == 'trial';
  bool get suspendida => status == 'suspended';

  /// Venció por falta de pago, que no es lo mismo que estar suspendida a mano
  /// desde el panel de super-admin. El mensaje al usuario cambia según cuál sea.
  bool get vencida => !isActive && !suspendida;

  /// Sin fecha de vencimiento = acceso indefinido. Es el caso de las
  /// organizaciones anteriores a la facturación: no se les corta nada.
  bool get sinVencimiento => expiresAt == null;

  factory Subscription.fromRow(Map<String, dynamic> r) => Subscription(
        organizationId: r['organization_id'] as String,
        status: (r['status'] as String?) ?? 'active',
        plan: (r['plan'] as String?) ?? 'trial',
        currency: (r['currency'] as String?) ?? 'USD',
        country: r['country'] as String?,
        isActive: (r['is_active'] as bool?) ?? true,
        expiresAt: r['expires_at'] == null
            ? null
            : DateTime.tryParse(r['expires_at'] as String)?.toLocal(),
        daysLeft: (r['days_left'] as num?)?.toInt(),
        suspendedReason: r['suspended_reason'] as String?,
      );
}

class SubscriptionRepository {
  SubscriptionRepository(this._client);

  final SupabaseClient _client;

  /// No recibe un id de organización a propósito: la función del servidor
  /// resuelve la del usuario autenticado, así que nadie puede sondear el estado
  /// de suscripción de un tercero.
  Future<Subscription?> actual() async {
    final filas = await _client.rpc('my_subscription') as List<dynamic>;
    if (filas.isEmpty) return null;
    return Subscription.fromRow(Map<String, dynamic>.from(filas.first as Map));
  }
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(Supabase.instance.client);
});

final subscriptionProvider = FutureProvider<Subscription?>((ref) async {
  try {
    return await ref.watch(subscriptionRepositoryProvider).actual();
  } catch (_) {
    // Sin sesión, sin red, o el usuario todavía no tiene organización. El aviso
    // de suscripción no es crítico: si no se puede leer, no se muestra nada en
    // vez de romper la pantalla que lo contiene.
    return null;
  }
});
