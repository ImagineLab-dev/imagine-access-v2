import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_roles.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/utils/currency_helper.dart';
import 'package:imagine_access/features/dashboard/data/dashboard_repository.dart';
import 'package:imagine_access/features/auth/presentation/auth_controller.dart';
import 'package:imagine_access/features/settings/data/settings_repository.dart';
import 'package:imagine_access/features/events/data/event_repository.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyAsync = ref.watch(defaultCurrencyProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final role = ref.watch(userRoleProvider);

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Global Config
          Text(l10n.general,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: AppTheme.accentBlue)),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.defaultCurrency),
                Consumer(builder: (ctx, ref, _) {
                  final isDark = theme.brightness == Brightness.dark;
                  final dropdownColor = isDark ? Colors.black87 : Colors.white;
                  final textColor = isDark ? Colors.white : Colors.black87;
                  final currentValue = currencyAsync.value ?? 'PYG';

                  return DropdownButton<String>(
                      value: CurrencyHelper.currencies.containsKey(currentValue)
                          ? currentValue
                          : 'PYG',
                      dropdownColor: dropdownColor,
                      style: TextStyle(color: textColor, fontSize: 14),
                      underline: const SizedBox(),
                      iconEnabledColor:
                          isDark ? Colors.white70 : Colors.black87,
                      items: CurrencyHelper.currencies.entries
                          .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  '${e.value.symbol} ${e.key}',
                                  style: TextStyle(color: textColor),
                                ),
                              ))
                          .toList(),
                      onChanged: (val) async {
                        if (val != null) {
                          await ref
                              .read(settingsRepositoryProvider)
                              .updateDefaultCurrency(val);
                          ref.invalidate(defaultCurrencyProvider);
                        }
                      });
                })
              ],
            ),
          ),

          const SizedBox(height: 20),

          // El tema y el idioma NO van aca: son preferencias personales del
          // usuario y viven en Perfil. Estaban duplicados en ambas pantallas,
          // asi que cambiarlos en una dejaba la otra mostrando lo anterior.

          if (AppRoles.isAdmin(role)) ...[
            const SizedBox(height: 32),

            // 2. Access Management
            Text(l10n.accessControl,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: AppTheme.accentBlue)),
            const SizedBox(height: 12),

            _SettingsTile(
              icon: Icons.people,
              title: l10n.userManagement,
              subtitle: l10n.userManagementDesc,
              onTap: () => context.push('/settings/users'),
            ),

            const SizedBox(height: 12),

            _SettingsTile(
              icon: Icons.devices,
              title: l10n.deviceManagement,
              subtitle: l10n.deviceManagementDesc,
              onTap: () => context.push('/settings/devices'),
            ),

            const SizedBox(height: 12),

            _SettingsTile(
              icon: Icons.groups,
              title: l10n.manageTeam,
              subtitle: l10n.addStaffToEvent,
              onTap: () => context.push('/event_staff'),
            ),
          ],

          const SizedBox(height: 12),

          _SettingsTile(
            icon: Icons.refresh,
            title: l10n.forceRefresh,
            subtitle: l10n.reloadLocaleData,
            onTap: () async {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l10n.refreshing)));

              // Force invalidate providers
              ref.invalidate(localeProvider);
              ref.invalidate(themeNotifierProvider);
              ref.invalidate(defaultCurrencyProvider);
              ref.invalidate(eventsProvider); // Reload events list
              ref.invalidate(dashboardMetricsProvider); // Reset metrics

              await Future.delayed(const Duration(seconds: 1)); // UX delay

              if (context.mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(l10n.updated),
                    backgroundColor: Colors.green));
              }
            },
          ),

          const SizedBox(height: 20),

          // Legal / Privacy Policy
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: l10n.legalInfo,
            subtitle: l10n.legalInfoDesc,
            onTap: () => context.push('/settings/legal'),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;

  const _SettingsTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      // ignore: unused_element_parameter
      this.color = AppTheme.neonBlue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold, color: color)),
                Text(subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey)
        ],
      ),
    );
  }
}
