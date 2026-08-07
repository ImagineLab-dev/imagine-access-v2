import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../../../core/ui/carrusel_metricas.dart';

/// El panel que ve el personal de puerta.
///
/// Antes eran NUEVE tarjetas de métrica en una grilla, todas del mismo color
/// apagado y del mismo tamaño: una pared de números de peso idéntico para
/// alguien cuyo único trabajo es escanear. Nada guiaba la mirada a lo que
/// importa en la puerta —cuántos entraron y cuántos faltan—.
///
/// Ahora usa el mismo carrusel que el panel de admin (el que la revisión de
/// diseño destacó): una métrica grande por vez, con su barra de avance, y las
/// vecinas asomando a los costados para que se vea que hay más. La asistencia
/// —escaneados sobre el total— va PRIMERA porque es el pulso de la noche.
///
/// A diferencia del admin, acá NO hay panel de ventas: el personal de puerta no
/// ve el dinero. El guard del router ya lo impide a nivel de datos; esto es que
/// tampoco aparezca en la pantalla que sí puede ver.
class DoorDashboardView extends ConsumerWidget {
  final Map<String, dynamic> metrics;

  const DoorDashboardView({super.key, required this.metrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    int n(String clave) => (metrics[clave] as num? ?? 0).toInt();
    final total = n('total_sold');
    final escaneados = n('scanned');
    final sinIngresar = (total - escaneados).clamp(0, total);

    return CarruselMetricas(
      tarjetas: [
        // El pulso de la puerta: cuántos entraron de cuántos hay.
        TarjetaCarrusel(
          etiqueta: l10n.attendance,
          valor: '$escaneados / $total',
          icono: Icons.qr_code_scanner,
          avance: proporcion(escaneados, total),
        ),
        // Lo que queda por entrar: el número que un portero mira toda la noche.
        TarjetaCarrusel(
          etiqueta: l10n.toEnter,
          valor: '$sinIngresar',
          icono: Icons.hourglass_empty_rounded,
          detalle: l10n.ticketsNotEntered(sinIngresar),
        ),
        TarjetaCarrusel(
          etiqueta: l10n.manualUpper,
          valor: '${n('scanned_manual')}',
          icono: Icons.back_hand,
        ),
        TarjetaCarrusel(
          etiqueta: l10n.staff,
          valor: "${n('staff_entered')} / ${n('staff_created')}",
          icono: Icons.badge_outlined,
          avance: proporcion(n('staff_entered'), n('staff_created')),
        ),
        TarjetaCarrusel(
          etiqueta: l10n.guests,
          valor: "${n('guest_entered')} / ${n('guest_created')}",
          icono: Icons.star_border,
          avance: proporcion(n('guest_entered'), n('guest_created')),
        ),
        TarjetaCarrusel(
          etiqueta: l10n.normal,
          valor: "${n('standard_entered')} / ${n('standard_created')}",
          icono: Icons.people_outline,
          avance: proporcion(n('standard_entered'), n('standard_created')),
        ),
        TarjetaCarrusel(
          etiqueta: l10n.guestEntry,
          valor: "${n('invitations_scanned')} / ${n('invitations_total')}",
          icono: Icons.mail_outline,
          avance: proporcion(n('invitations_scanned'), n('invitations_total')),
        ),
        TarjetaCarrusel(
          etiqueta: 'Promo',
          valor: "${n('promo_entered')} / ${n('promo_created')}",
          icono: Icons.local_offer_outlined,
          avance: proporcion(n('promo_entered'), n('promo_created')),
        ),
      ],
    );
    // Sin acciones rápidas: escanear y buscar por documento ya están en la
    // barra de abajo, con el dedo encima. Repetirlas acá sería hacer leer
    // cuatro botones para elegir entre dos.
  }
}
