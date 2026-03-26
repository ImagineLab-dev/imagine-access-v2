import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_helper.dart';
import '../../../events/presentation/event_state.dart';
import '../../../settings/data/settings_repository.dart';
import '../../data/event_report_service.dart';
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
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.75,
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
            MetricCard(
              title: l10n.sales,
              value: CurrencyHelper.format(
                  (metrics['revenue'] as num? ?? 0).toDouble(), defaultCurrency),
              icon: CurrencyHelper.getIcon(defaultCurrency),
              color: AppTheme.accentYellow,
              delay: 300,
            ),
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

    return GestureDetector(
      onTap: _loading ? null : () => _export(context, ref),
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
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            else
              const Icon(Icons.download_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              _loading ? l10n.reportGenerating : l10n.downloadReport.toUpperCase(),
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
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
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
