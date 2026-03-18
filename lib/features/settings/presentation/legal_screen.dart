import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/theme/app_theme.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  static const _privacyUrl = 'https://imagineaccess.app/privacy';
  static const _termsUrl = 'https://imagineaccess.app/terms';

  void _copyUrl(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('URL copiada: $url')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.legalInfo)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GlassCard(
            onTap: () => _copyUrl(context, _privacyUrl),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.privacy_tip_outlined,
                    color: AppTheme.accentBlue, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(l10n.privacyPolicy,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.neonBlue)),
                ),
                const Icon(Icons.open_in_new, color: Colors.grey, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            onTap: () => _copyUrl(context, _termsUrl),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.description_outlined,
                    color: AppTheme.accentBlue, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(l10n.termsOfService,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.neonBlue)),
                ),
                const Icon(Icons.open_in_new, color: Colors.grey, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Imagine Access v1.0.0\n© 2026 Imagine Lab',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
