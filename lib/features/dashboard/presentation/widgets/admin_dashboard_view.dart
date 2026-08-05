import 'package:flutter/material.dart';
import 'package:imagine_access/core/ui/responsive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_helper.dart';
import '../../../events/presentation/event_state.dart';
import '../../../settings/data/settings_repository.dart';
import '../../data/event_report_service.dart';
import '../../../../core/ui/glass_card.dart';
import 'dashboard_components.dart';

class AdminDashboardView extends ConsumerWidget {
  final Map<String, dynamic> metrics;

  const AdminDashboardView({super.key, required this.metrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final defaultCurrency = ref.watch(defaultCurrencyProvider).value ?? 'PYG';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: Responsive.columnas(context),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: Responsive.proporcionTarjeta(context),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            MetricCard(
              title: l10n.totalTickets,
              value: (metrics['total_sold'] ?? 0).toString(),
              icon: Icons.confirmation_number_outlined,
              color: AppTheme.accentBlue,
              delay: 0,
            ),
            MetricCard(
              title: l10n.valid,
              value: (metrics['valid'] ?? 0).toString(),
              icon: Icons.check_circle_outline,
              color: AppTheme.accentGreen,
              delay: 100,
            ),
            MetricCard(
              title: l10n.scanned,
              value: (metrics['scanned'] ?? 0).toString(),
              icon: Icons.qr_code_scanner,
              color: AppTheme.accentPurple,
              delay: 200,
            ),
            // Ventas NO va acá: se dibuja a ancho completo debajo de la grilla.
            // Ver el comentario de `_TarjetaVentas` más abajo.
            MetricCard(
              title: "${l10n.staff} (IN/TOT)",
              value:
                  "${metrics['staff_entered'] ?? 0} / ${metrics['staff_created'] ?? 0}",
              icon: Icons.badge_outlined,
              color: Colors.orangeAccent,
              delay: 400,
            ),
            MetricCard(
              title: "${l10n.guests} (IN/TOT)",
              value:
                  "${metrics['guest_entered'] ?? 0} / ${metrics['guest_created'] ?? 0}",
              icon: Icons.star_border,
              color: Colors.pinkAccent,
              delay: 500,
            ),
            MetricCard(
              title: "${l10n.normal} (IN/TOT)",
              value:
                  "${metrics['standard_entered'] ?? 0} / ${metrics['standard_created'] ?? 0}",
              icon: Icons.people_outline,
              color: Colors.cyanAccent,
              delay: 600,
            ),
            MetricCard(
              title: "${l10n.guestEntry} (IN/TOT)",
              value:
                  "${metrics['invitations_scanned'] ?? 0} / ${metrics['invitations_total'] ?? 0}",
              icon: Icons.mail_outline,
              color: Colors.deepPurpleAccent,
              delay: 650,
            ),
            MetricCard(
              title: "Promo (IN/TOT)",
              value:
                  "${metrics['promo_entered'] ?? 0} / ${metrics['promo_created'] ?? 0}",
              icon: Icons.local_offer,
              color: Colors.orangeAccent,
              delay: 700,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Ventas, de borde a borde.
        //
        // Estaba dentro de la grilla y eran NUEVE tarjetas en dos columnas: la
        // última fila quedaba con una sola y el bloque entero se veía torcido.
        // Sacándola quedan ocho, que son cuatro filas de dos exactas.
        //
        // Y es el lugar que le corresponde por jerarquía: de los nueve números
        // es el único que es dinero. A ancho completo se lee de un vistazo sin
        // competir con los conteos, y queda pegada al botón de Estadísticas, que
        // es a donde va quien está mirando la plata.
        _TarjetaVentas(
          monto: CurrencyHelper.format(
              (metrics['revenue'] as num? ?? 0).toDouble(), defaultCurrency),
          icono: CurrencyHelper.getIcon(defaultCurrency),
          titulo: l10n.sales,
        ),
        const SizedBox(height: 16),

        GestureDetector(
          onTap: () {
            final selectedEvent = ref.read(selectedEventProvider);
            final eventId = selectedEvent?['id'] as String?;
            if (eventId != null && eventId.isNotEmpty) {
              context.push('/stats/$eventId');
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.accentBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.analytics_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  l10n.statistics.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _DownloadReportButton(metrics: metrics),
        const SizedBox(height: 32),
        QuickActions(
          actions: [
            ActionItem(l10n.newTicket, Icons.confirmation_number, '/create_ticket',
                isPrimary: true),
            ActionItem(l10n.manageTeam, Icons.groups, '/event_staff',
                color: Colors.blueAccent),
            ActionItem(l10n.scanner, Icons.qr_code_scanner, '/scanner',
                color: Colors.purpleAccent),
            ActionItem(l10n.viewAllTickets, Icons.list_alt, '/tickets',
                color: Colors.orangeAccent),
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

/// Tarjeta de ventas, de borde a borde.
///
/// No usa `MetricCard` porque no cumple la misma función. Las otras ocho son
/// conteos que se comparan entre sí, y por eso conviene que sean todas iguales y
/// del mismo tamaño. Esta es la única cifra de dinero: se lee sola, no se
/// compara con nada, y tiene que destacarse.
///
/// El monto va a la DERECHA y el rótulo a la izquierda, alineados en la misma
/// línea. Con el número al final del renglón, la coma decimal cae siempre en el
/// mismo lugar aunque cambie el largo de la cifra, y el ojo no tiene que
/// recorrer el ancho de la pantalla para unir la etiqueta con su valor.
class _TarjetaVentas extends StatelessWidget {
  const _TarjetaVentas({
    required this.monto,
    required this.icono,
    required this.titulo,
  });

  final String monto;
  final IconData icono;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GlassCard(
      // Un poco mas alta que las de la grilla (74 px) porque el numero es mas
      // grande, pero sin llegar al doble: sigue siendo una linea de contenido.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.accentYellow.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, color: AppTheme.accentYellow, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              titulo.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.9,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // FittedBox para que una cifra larga se encoja en vez de desbordar:
          // "Gs 12.500.000" ocupa mas del doble que "Gs 0".
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                monto,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  height: 1,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
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
          borderRadius: BorderRadius.circular(14),
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
