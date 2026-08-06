import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:imagine_access/core/theme/app_theme.dart';
import 'package:imagine_access/core/ui/empty_state.dart';
import 'package:imagine_access/core/ui/glass_card.dart';
import 'package:imagine_access/core/ui/glass_scaffold.dart';
import 'package:imagine_access/core/ui/responsive.dart';
import 'package:imagine_access/features/superadmin/data/tenant_repository.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../../core/ui/status_badge.dart';

class SuperAdminScreen extends ConsumerStatefulWidget {
  const SuperAdminScreen({super.key});

  @override
  ConsumerState<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends ConsumerState<SuperAdminScreen> {
  String _busqueda = '';

  void _aviso(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? AppTheme.accentOrange : null,
      ));
  }

  Future<void> _confirmarSuspension(Tenant t, AppLocalizations l10n) async {
    final motivoCtrl = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${l10n.tenantSuspend} · ${t.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Se explica la consecuencia concreta, no un "¿estás seguro?".
            // Suspender en medio de un evento deja gente en la puerta.
            Text(l10n.tenantSuspendWarning,
                style: TextStyle(color: Theme.of(ctx).hintColor, height: 1.4)),
            const SizedBox(height: 16),
            TextField(
              controller: motivoCtrl,
              decoration: InputDecoration(
                labelText: l10n.tenantSuspendReason,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentOrange,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tenantSuspend),
          ),
        ],
      ),
    );

    if (confirmado != true) return;
    try {
      await ref
          .read(tenantRepositoryProvider)
          .setStatus(t.id, 'suspended', reason: motivoCtrl.text.trim());
      ref.invalidate(tenantsProvider);
      ref.invalidate(superadminAuditProvider);
      _aviso(l10n.tenantSuspended);
    } catch (_) {
      _aviso(l10n.error, error: true);
    }
  }

  Future<void> _reactivar(Tenant t, AppLocalizations l10n) async {
    try {
      await ref.read(tenantRepositoryProvider).setStatus(t.id, 'active');
      ref.invalidate(tenantsProvider);
      ref.invalidate(superadminAuditProvider);
      _aviso(l10n.tenantActive);
    } catch (_) {
      _aviso(l10n.error, error: true);
    }
  }

  Future<void> _editarSuscripcion(Tenant t, AppLocalizations l10n) async {
    var plan = t.plan;
    DateTime? vence = t.subscriptionExpiresAt;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${l10n.subscription} · ${t.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                // Limita el texto al ancho del campo: sin esto una etiqueta
                // larga se sale del recuadro en vez de recortarse.
                isExpanded: true,
                initialValue: plan,
                decoration: InputDecoration(
                    labelText: l10n.plan, border: const OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'trial', child: Text('Trial')),
                  DropdownMenuItem(value: 'basic', child: Text('Basic')),
                  DropdownMenuItem(value: 'pro', child: Text('Pro')),
                  DropdownMenuItem(value: 'courtesy', child: Text('Cortesía')),
                ],
                onChanged: (v) => setLocal(() => plan = v ?? plan),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.expiresOn),
                subtitle: Text(vence == null
                    ? l10n.noExpiry
                    : DateFormat('dd/MM/yyyy').format(vence!)),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final elegida = await showDatePicker(
                    context: ctx,
                    initialDate: vence ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (elegida != null) setLocal(() => vence = elegida);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.save)),
          ],
        ),
      ),
    );

    if (guardar != true) return;
    try {
      await ref
          .read(tenantRepositoryProvider)
          .setSubscription(t.id, plan: plan, expiresAt: vence);
      ref.invalidate(tenantsProvider);
      ref.invalidate(superadminAuditProvider);
      _aviso(l10n.orgSaved);
    } catch (_) {
      _aviso(l10n.error, error: true);
    }
  }

  Future<void> _verComoCliente(Tenant t, AppLocalizations l10n) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.name),
        content: Text(l10n.viewAsTenantWarning),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.viewAsTenant)),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;
    try {
      await ref.read(tenantRepositoryProvider).impersonate(t.id);
      if (!mounted) return;
      // Se invalida todo el árbol de datos: los providers tienen cacheada la
      // organización anterior y sin esto el panel mostraría datos mezclados.
      ref.invalidate(tenantsProvider);
      context.go('/dashboard');
    } catch (_) {
      _aviso(l10n.error, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tenantsAsync = ref.watch(tenantsProvider);

    return GlassScaffold(
      titulo: l10n.superAdmin,
      acciones: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: l10n.refresh,
          onPressed: () {
            ref.invalidate(tenantsProvider);
            ref.invalidate(superadminAuditProvider);
          },
        ),
      ],
      body: tenantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('${l10n.error}\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (tenants) {
          final filtrados = _busqueda.isEmpty
              ? tenants
              : tenants
                  .where((t) =>
                      t.name.toLowerCase().contains(_busqueda.toLowerCase()) ||
                      t.slug.toLowerCase().contains(_busqueda.toLowerCase()) ||
                      (t.taxId ?? '').contains(_busqueda))
                  .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _resumen(l10n, tenants),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  hintText: l10n.searchTenant,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _busqueda = v),
              ),
              const SizedBox(height: 16),
              if (filtrados.isEmpty)
                EmptyState(
                    icon: Icons.apartment_outlined, title: l10n.noTenants)
              else
                ...filtrados.map((t) => _tarjetaTenant(t, l10n)),
              const SizedBox(height: 24),
              _auditoria(l10n),
            ],
          );
        },
      ),
    );
  }

  Widget _resumen(AppLocalizations l10n, List<Tenant> tenants) {
    final activas = tenants.where((t) => !t.suspendido).length;
    final vencidas = tenants.where((t) => t.vencida).length;
    final tickets = tenants.fold<int>(0, (a, t) => a + t.ticketsCount);

    Widget dato(String etiqueta, String valor, Color color) => Expanded(
          child: GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              children: [
                Text(valor,
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 4),
                Text(etiqueta,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).hintColor)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        dato(l10n.tenantActive, '$activas', AppTheme.primaryColor),
        const SizedBox(width: 10),
        dato(l10n.tenantSuspended, '${tenants.length - activas}',
            AppTheme.accentYellow),
        const SizedBox(width: 10),
        if (!Responsive.esTelefono(context)) ...[
          dato(l10n.expiresOn, '$vencidas', AppTheme.accentOrange),
          const SizedBox(width: 10),
        ],
        dato(l10n.tenantTickets, '$tickets',
            Theme.of(context).colorScheme.onSurface),
      ],
    );
  }

  Widget _tarjetaTenant(Tenant t, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final dias = t.diasParaVencer;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        [t.slug, if (t.taxId != null) t.taxId!].join(' · '),
                        style:
                            TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
                _chip(
                  t.suspendido ? l10n.tenantSuspended : l10n.tenantActive,
                  t.suspendido ? BadgeStatus.warning : BadgeStatus.success,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _metrica(l10n.tenantUsers, t.usersCount),
                _metrica(l10n.tenantEvents, t.eventsCount),
                _metrica(l10n.tenantTickets, t.ticketsCount),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.workspace_premium_outlined,
                    size: 15, color: theme.hintColor),
                const SizedBox(width: 6),
                Text(t.plan.toUpperCase(),
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    dias == null
                        ? l10n.noExpiry
                        : dias < 0
                            ? l10n.expiredDaysAgo(-dias)
                            : l10n.expiresInDays(dias),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: dias != null && dias < 7
                          ? AppTheme.accentOrange
                          : theme.hintColor,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _editarSuscripcion(t, l10n),
                  icon: const Icon(Icons.event_repeat, size: 17),
                  label: Text(l10n.extendSubscription),
                ),
                TextButton.icon(
                  onPressed: () => _verComoCliente(t, l10n),
                  icon: const Icon(Icons.visibility_outlined, size: 17),
                  label: Text(l10n.viewAsTenant),
                ),
                if (t.suspendido)
                  TextButton.icon(
                    onPressed: () => _reactivar(t, l10n),
                    icon: const Icon(Icons.play_arrow, size: 17),
                    label: Text(l10n.tenantReactivate),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _confirmarSuspension(t, l10n),
                    icon: Icon(Icons.block,
                        size: 17, color: AppTheme.accentYellow),
                    label: Text(l10n.tenantSuspend,
                        style: TextStyle(color: AppTheme.accentYellow)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Estado del inquilino. Usa el componente del sistema en lugar de pintar el
  /// color al 15% de opacidad: sobre papel, el lima al 15% con texto lima
  /// encima no se leia.
  Widget _chip(String texto, BadgeStatus estado) =>
      StatusBadge(text: texto, status: estado);

  Widget _metrica(String etiqueta, int valor) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$valor',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 4),
          Text(etiqueta,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).hintColor)),
        ],
      );

  Widget _auditoria(AppLocalizations l10n) {
    final auditAsync = ref.watch(superadminAuditProvider);

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 18),
              const SizedBox(width: 8),
              Text(l10n.auditLog,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          auditAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Text(l10n.error),
            data: (entradas) {
              if (entradas.isEmpty) {
                return Text('—', style: TextStyle(color: Theme.of(context).hintColor));
              }
              return Column(
                children: entradas.take(12).map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${e.action} · ${e.organizationName ?? "—"}',
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          DateFormat('dd/MM HH:mm').format(e.createdAt),
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
