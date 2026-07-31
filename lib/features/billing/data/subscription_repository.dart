import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/tiempo_limite.dart';

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
    this.cancelledAt,
    this.daysLeft,
    this.suspendedReason,
    this.freeTicketsUsed = 0,
    this.freeTicketsLimit,
    this.freeTicketsLeft,
  });

  final String organizationId;
  final String status;
  final String plan;
  final String currency;
  final bool isActive;
  final String? country;
  final DateTime? expiresAt;

  /// Cuándo pidió la baja del cobro. Nulo = la suscripción sigue corriendo.
  final DateTime? cancelledAt;
  final int? daysLeft;
  final String? suspendedReason;

  /// Tickets emitidos contra el cupo gratuito. Solo sube: anular un ticket no
  /// devuelve el cupo, para que no se pueda reciclar emitiendo y anulando.
  final int freeTicketsUsed;

  /// Cupo de por vida. `null` = sin cupo, el caso de las organizaciones
  /// anteriores al cobro.
  final int? freeTicketsLimit;

  /// Cuántos quedan. `null` cuando no aplica (ya paga, o está exenta).
  final int? freeTicketsLeft;

  /// Se acabaron los tickets gratis y todavía no paga.
  bool get cupoAgotado => enPrueba && (freeTicketsLeft ?? 1) <= 0;

  bool get enPrueba => plan == 'trial';
  bool get suspendida => status == 'suspended';

  /// Venció por falta de pago, que no es lo mismo que estar suspendida a mano
  /// desde el panel de super-admin. El mensaje al usuario cambia según cuál sea.
  bool get vencida => !isActive && !suspendida;

  /// Pidió la baja: el cobro no se renueva, pero el acceso sigue hasta
  /// [expiresAt], que es hasta donde está pagado. Cancelar detiene la
  /// renovación, no el servicio.
  bool get cancelada => cancelledAt != null;

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
        cancelledAt: r['cancelled_at'] == null
            ? null
            : DateTime.tryParse(r['cancelled_at'] as String)?.toLocal(),
        daysLeft: (r['days_left'] as num?)?.toInt(),
        suspendedReason: r['suspended_reason'] as String?,
        freeTicketsUsed: (r['free_tickets_used'] as num?)?.toInt() ?? 0,
        freeTicketsLimit: (r['free_tickets_limit'] as num?)?.toInt(),
        freeTicketsLeft: (r['free_tickets_left'] as num?)?.toInt(),
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

  /// Enlace de pago de dLocal para la organización del usuario.
  ///
  /// El plan se crea del lado del servidor la primera vez y se reutiliza después.
  /// Se hace allá y no acá porque crear un plan exige la clave secreta de dLocal,
  /// que no puede estar en el bundle: cualquiera abriría `main.dart.js` y podría
  /// crear cobros a nombre de la cuenta.
  Future<String> enlaceDePago({String plan = 'monthly'}) async {
    final res = await _client.functions
        .invoke('dlocal_subscribe', body: {'plan': plan})
        .conLimite(TiempoLimite.normal, 'dlocal_subscribe');

    final datos = Map<String, dynamic>.from(res.data as Map);
    if (datos['ok'] != true || datos['url'] == null) {
      throw Exception(datos['mensaje'] ?? 'No se pudo generar el enlace de pago');
    }
    return datos['url'] as String;
  }

  /// Da de baja el cobro recurrente.
  ///
  /// Devuelve hasta cuándo sigue el acceso. La función del servidor corta el
  /// cobro en dLocal ANTES de marcarlo, así que si esto responde bien, el
  /// débito ya está detenido de verdad: no es una marca optimista.
  Future<DateTime?> cancelar() async {
    final res = await _client.functions
        .invoke('cancelar_suscripcion')
        .conLimite(TiempoLimite.conCorreo, 'cancelar_suscripcion');

    final datos = Map<String, dynamic>.from(res.data as Map);
    if (datos['ok'] != true) {
      throw Exception(datos['mensaje'] ?? 'No se pudo dar de baja la suscripción');
    }
    final hasta = datos['acceso_hasta'] as String?;
    return hasta == null ? null : DateTime.tryParse(hasta)?.toLocal();
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

