import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_helper.dart';
import '../../../events/presentation/event_state.dart';
import '../../../settings/data/settings_repository.dart';
import '../../data/event_report_service.dart';
import '../../../../core/ui/glass_card.dart';
import '../../../../core/ui/carrusel_metricas.dart';
import '../../../../core/ui/neon_button.dart';
import 'dashboard_components.dart';

class AdminDashboardView extends ConsumerWidget {
  final Map<String, dynamic> metrics;

  const AdminDashboardView({super.key, required this.metrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final defaultCurrency = ref.watch(defaultCurrencyProvider).value ?? 'PYG';

    // Los números del evento, en tres niveles de jerarquía.
    //
    // Antes eran OCHO tarjetas idénticas en una grilla de 2x4, más ventas
    // aparte. Ocho cajas del mismo tamaño, con el mismo peso, cada una con su
    // ícono de un color distinto: "6 TICKETS TOTALES" ocupaba exactamente lo
    // mismo que "0 / 0 PROMO". Cuando todo pesa igual, nada pesa: hay que leer
    // las ocho para encontrar la que importa. Y la mitad decían "0 / 0".
    //
    // Ahora:
    //   1. VENTAS, que es la única cifra de dinero, arriba y grande.
    //   2. ASISTENCIA, que es la pregunta que se hace durante el evento
    //      —cuántos entraron de los que compraron—, con barra de avance.
    //   3. El desglose por categoría como TABLA, no como tarjetas. Cinco filas
    //      de una línea ocupan menos que dos tarjetas, se comparan de arriba
    //      abajo (que es como se comparan números) y las categorías vacías se
    //      apagan en vez de gritar igual que las demás.
    //
    // "Tickets totales", "válido" y "escaneados" eran tres tarjetas para tres
    // números que son el mismo dato: total = escaneados + sin ingresar. Ahora
    // es una sola línea que lo dice entero.
    final total = (metrics['total_sold'] as num? ?? 0).toInt();
    final escaneados = (metrics['scanned'] as num? ?? 0).toInt();
    final sinIngresar = (total - escaneados).clamp(0, total);

    int n(String clave) => (metrics[clave] as num? ?? 0).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelVentas(
          monto: CurrencyHelper.format(
              (metrics['revenue'] as num? ?? 0).toDouble(), defaultCurrency),
          titulo: l10n.sales,
        ),
        const SizedBox(height: 12),

        // Las ocho métricas, en carrusel.
        //
        // Antes eran ocho tarjetas iguales en una grilla de 2x4: ninguna
        // destacaba y la mitad decía "0 / 0". Acá pasa una por vez, grande y
        // con su barra de avance, y las vecinas quedan asomando a los costados
        // para que se vea que hay más y se puedan comparar de a tres.
        //
        // Ventas NO entra: es la única cifra de dinero y va fija arriba.
        CarruselMetricas(
          tarjetas: [
            TarjetaCarrusel(
              etiqueta: l10n.attendance,
              valor: '$escaneados / $total',
              icono: Icons.qr_code_scanner,
              avance: proporcion(escaneados, total),
            ),
            TarjetaCarrusel(
              etiqueta: l10n.totalTickets,
              valor: '$total',
              icono: Icons.confirmation_number_outlined,
              detalle: l10n.ticketsNotEntered(sinIngresar),
            ),
            TarjetaCarrusel(
              etiqueta: l10n.valid,
              valor: '${n('valid')}',
              icono: Icons.check_circle_outline,
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
              valor:
                  "${n('invitations_scanned')} / ${n('invitations_total')}",
              icono: Icons.mail_outline,
              avance:
                  proporcion(n('invitations_scanned'), n('invitations_total')),
            ),
            TarjetaCarrusel(
              etiqueta: 'Promo',
              valor: "${n('promo_entered')} / ${n('promo_created')}",
              icono: Icons.local_offer_outlined,
              avance: proporcion(n('promo_entered'), n('promo_created')),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Los dos van con contorno, ninguno macizo.
        //
        // "Estadísticas" era un bloque lima a todo lo ancho: lo más ruidoso de
        // la pantalla, más que la cifra de ventas. Pero no es la acción
        // principal del panel —esa es emitir un ticket—, así que no le
        // corresponde el color macizo.
        NeonButton(
          text: l10n.statistics,
          icon: Icons.analytics_outlined,
          isSecondary: true,
          onPressed: () {
            final selectedEvent = ref.read(selectedEventProvider);
            final eventId = selectedEvent?['id'] as String?;
            if (eventId != null && eventId.isNotEmpty) {
              context.push('/stats/$eventId');
            }
          },
        ),
        const SizedBox(height: 10),
        _DownloadReportButton(metrics: metrics),
        const SizedBox(height: 30),
        QuickActions(
          actions: [
            // Acá va solo lo que no se puede alcanzar desde otro lado.
            //
            // "Escáner" y "Ver todos los tickets" salieron porque son dos de
            // los cuatro botones de la barra de abajo. "Crear evento" salió
            // porque vive en la pantalla de Eventos —el botón + de su cabecera—
            // que es el segundo botón de esa misma barra.
            ActionItem(l10n.newTicket, Icons.confirmation_number,
                '/create_ticket',
                isPrimary: true),
            ActionItem(l10n.manageTeam, Icons.groups, '/event_staff'),
          ],
          onActionBeforeNavigate: (action) =>
              _checkEventSelected(context, ref, action.route),
        ),
      ],
    );
  }

  bool _checkEventSelected(BuildContext context, WidgetRef ref, String route) {
    if (route == '/tickets') {
      return true;
    }

    final selectedEvent = ref.read(selectedEventProvider);
    if (selectedEvent == null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseSelectEvent)),
      );
      return false;
    }

    return true;
  }
}

/// Ventas: la cifra que manda en el panel.
///
/// Es la única que es dinero, así que no comparte tamaño con los conteos. El
/// rótulo va arriba en chico y el número abajo en grande —no al costado— porque
/// una cifra larga ("Gs 12.500.000") necesita el ancho entero: alineada a la
/// derecha junto a una etiqueta, se encogía hasta volverse ilegible.
class _PanelVentas extends StatelessWidget {
  const _PanelVentas({required this.monto, required this.titulo});

  final String monto;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      // Rótulo a la izquierda, monto a la derecha, en la misma línea.
      //
      // Con el número al final del renglón la cifra termina siempre en el mismo
      // borde, así que dos lecturas seguidas se comparan sin que el ojo tenga
      // que buscar dónde empieza. Apilado quedaba más grande, pero el monto
      // arrancaba en un lugar distinto según su largo.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            titulo.toUpperCase(),
            style: AppTheme.etiqueta(
              context,
              size: 12,
              color: AppTheme.acentoTexto(context),
            ),
          ),
          const SizedBox(width: 14),
          // FittedBox para que una cifra larga se encoja en vez de desbordar:
          // "Gs 12.500.000" ocupa más del doble que "Gs 0".
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(monto, style: AppTheme.titular(context, size: 34)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadReportButton extends ConsumerStatefulWidget {
  final Map<String, dynamic> metrics;
  const _DownloadReportButton({required this.metrics});

  @override
  ConsumerState<_DownloadReportButton> createState() => _DownloadReportButtonState();
}

class _DownloadReportButtonState extends ConsumerState<_DownloadReportButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _loading ? null : () => _export(ref),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? AppTheme.darkText : AppTheme.lightText),
              )
            else
              Icon(Icons.download_outlined,
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                  size: 20),
            const SizedBox(width: 10),
            Text(
              _loading ? l10n.reportGenerating : l10n.downloadReport.toUpperCase(),
              style: TextStyle(
                color: isDark ? AppTheme.darkText : AppTheme.lightText,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sin recibir el `BuildContext` por parámetro: se usa el del `State`.
  ///
  /// Es el mismo objeto —lo llamaba el `build` de esta misma clase pasándole su
  /// propio contexto— pero el analizador no podía probarlo, y avisaba cuatro
  /// veces que el `mounted` era "de un objeto no relacionado". Eran falsos
  /// positivos, y el problema de convivir con ellos es que el día que aparezca
  /// uno de verdad va a pasar desapercibido entre los cuatro de siempre.
  Future<void> _export(WidgetRef ref) async {
    final selectedEvent = ref.read(selectedEventProvider);
    if (selectedEvent == null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseSelectEvent)),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final l10n = AppLocalizations.of(context);
      await ref.read(eventReportServiceProvider).exportAndShare(
        selectedEvent['id'] as String,
        selectedEvent['name'] as String? ?? 'evento',
        l10n,
      );
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.reportReady)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.reportError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
