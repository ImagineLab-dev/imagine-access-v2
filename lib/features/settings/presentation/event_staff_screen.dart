import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

import '../../../core/constants/app_roles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../events/presentation/event_state.dart';
import '../data/settings_repository.dart';

final eventStaffProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final selectedEvent = ref.watch(selectedEventProvider);
  if (selectedEvent == null) return [];
  return ref.watch(settingsRepositoryProvider).getEventStaff(selectedEvent['id']);
});

class EventStaffScreen extends ConsumerWidget {
  const EventStaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedEvent = ref.watch(selectedEventProvider);
    final theme = Theme.of(context);
    final staffAsync = ref.watch(eventStaffProvider);
    final allUsersAsync = ref.watch(usersListProvider);
    final l10n = AppLocalizations.of(context);

    if (selectedEvent == null) {
      // Antes esto era un Scaffold pelado con una linea de texto: sin barra,
      // sin boton de volver y sin forma de ir a elegir el evento. El usuario
      // quedaba atrapado y tenia que usar el atras del navegador.
      return GlassScaffold(
        appBar: AppBar(title: Text(l10n.manageTeam)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy_outlined,
                    size: 56, color: Theme.of(context).hintColor),
                const SizedBox(height: 20),
                Text(
                  l10n.selectEventFirstTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.selectEventFirstBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).hintColor, height: 1.5),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.push('/events'),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(l10n.goToEvents),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.teamForEvent(selectedEvent['name'])),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showAddStaffDialog(context, ref, allUsersAsync.value ?? []),
            tooltip: l10n.addStaffToEvent,
          ),
        ],
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text(l10n.error)),
        data: (staffList) {
          if (staffList.isEmpty) {
            return Center(child: Text(l10n.noStaffAssignedToEvent, style: theme.textTheme.bodyMedium));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: staffList.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final staff = staffList[index];
              final userDetails = allUsersAsync.value?.firstWhere(
                        (u) => u['user_id'] == staff['user_id'],
                        orElse: () => {
                          'display_name': l10n.unknownUser,
                          'email': l10n.unknown,
                        },
                      ) ??
                  {};

              final role = staff['role'];
              final qStandard = staff['quota_standard'] ?? 0;
              final qGuest = staff['quota_guest'] ?? 0;
              final qStandardUsed = staff['quota_standard_used'] ?? 0;
              final qGuestUsed = staff['quota_guest_used'] ?? 0;

              return GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: _getRoleColor(role).withValues(alpha: 0.2),
                          child: Icon(Icons.person, color: _getRoleColor(role)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userDetails['display_name'] ?? l10n.unknown,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppTheme.texto(context),
                                ),
                              ),
                              Text(
                                role.toString().toUpperCase(),
                                style: TextStyle(
                                  color: _getRoleColor(role),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.edit,
                          icon: const Icon(Icons.edit, color: AppTheme.lima),
                          onPressed: () => _showEditQuotaDialog(
                            context,
                            ref,
                            staff,
                            userDetails['display_name'] ?? l10n.user,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.delete,
                          icon: const Icon(Icons.delete_outline, color: AppTheme.accentOrange),
                          onPressed: () => _confirmRemoveStaff(
                            context,
                            ref,
                            staff,
                            userDetails['display_name'] ?? l10n.unknown,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _QuotaBadge(
                          title: l10n.standardShort,
                          used: qStandardUsed,
                          total: qStandard,
                          color: Colors.blue,
                        ),
                        _QuotaBadge(
                          title: l10n.invitationShort,
                          used: staff['quota_invitation_used'] ?? 0,
                          total: staff['quota_invitation'] ?? 0,
                          color: Colors.purple,
                        ),
                        _QuotaBadge(
                          title: l10n.vipShort,
                          used: qGuestUsed,
                          total: qGuest,
                          color: Colors.pink,
                        ),
                      ],
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case AppRoles.admin:
        return AppTheme.accentOrange;
      case AppRoles.rrpp:
        return AppTheme.neonBlue;
      case AppRoles.door:
        return AppTheme.accentGreen;
      default:
        return AppTheme.accentPurple;
    }
  }

  void _showAddStaffDialog(BuildContext context, WidgetRef ref, List<Map<String, dynamic>> allUsers) {
    final l10n = AppLocalizations.of(context);

    String? selectedUserId;
    String selectedRole = AppRoles.rrpp;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppTheme.panel(context),
          title: Text(
            l10n.addStaffToEvent,
            style: TextStyle(color: AppTheme.texto(context)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                // Limita el texto al ancho del campo: sin esto una etiqueta
                // larga se sale del recuadro en vez de recortarse.
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.selectUser),
                items: allUsers
                    .map((u) => DropdownMenuItem(
                          value: u['user_id'] as String,
                          child: Text(u['display_name'] ?? l10n.user),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => selectedUserId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                // Limita el texto al ancho del campo: sin esto una etiqueta
                // larga se sale del recuadro en vez de recortarse.
                isExpanded: true,
                initialValue: selectedRole,
                decoration: InputDecoration(labelText: l10n.roleInEvent),
                items: [
                  DropdownMenuItem(value: AppRoles.rrpp, child: Text(AppRoles.label(AppRoles.rrpp))),
                  DropdownMenuItem(value: AppRoles.door, child: Text(AppRoles.label(AppRoles.door))),
                  DropdownMenuItem(value: AppRoles.admin, child: Text(AppRoles.label(AppRoles.admin))),
                ],
                onChanged: (v) => setState(() => selectedRole = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: selectedUserId == null
                  ? null
                  : () async {
                      final eventId = ref.read(selectedEventProvider)!['id'];
                      try {
                        await ref.read(settingsRepositoryProvider).manageEventStaff(
                              eventId: eventId,
                              userId: selectedUserId!,
                              role: selectedRole,
                              quotaStandard: 0,
                              quotaGuest: 0,
                              quotaInvitation: 0,
                            );
                        ref.invalidate(eventStaffProvider);
                        if (context.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.eventSaveError)),
                          );
                        }
                      }
                    },
              child: Text(l10n.addAction),
            )
          ],
        ),
      ),
    );
  }

  void _confirmRemoveStaff(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> staff,
    String userName,
  ) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.removeStaff),
        content: Text(l10n.confirmRemoveStaff(userName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              final eventId = ref.read(selectedEventProvider)!['id'];
              try {
                await ref.read(settingsRepositoryProvider).removeEventStaff(
                      eventId: eventId,
                      userId: staff['user_id'],
                    );
                ref.invalidate(eventStaffProvider);
                if (context.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.eventSaveError)),
                  );
                }
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: AppTheme.accentOrange)),
          ),
        ],
      ),
    );
  }

  void _showEditQuotaDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> staff,
    String userName,
  ) {
    final l10n = AppLocalizations.of(context);

    final stdCtrl = TextEditingController(text: (staff['quota_standard'] ?? 0).toString());
    final guestCtrl = TextEditingController(text: (staff['quota_guest'] ?? 0).toString());
    final invCtrl = TextEditingController(text: (staff['quota_invitation'] ?? 0).toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panel(context),
        title: Text(
          l10n.editQuotasFor(userName),
          style: TextStyle(color: AppTheme.texto(context)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: stdCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.standardTicketQuota),
              style: TextStyle(color: AppTheme.texto(context)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: guestCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.guestListQuotaVip),
              style: TextStyle(color: AppTheme.texto(context)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: invCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.invitationQuotaNormal),
              style: TextStyle(color: AppTheme.texto(context)),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () async {
              final std = (int.tryParse(stdCtrl.text) ?? 0).clamp(0, 999999);
              final guest = (int.tryParse(guestCtrl.text) ?? 0).clamp(0, 999999);
              final inv = (int.tryParse(invCtrl.text) ?? 0).clamp(0, 999999);
              final eventId = ref.read(selectedEventProvider)!['id'];

              try {
                await ref.read(settingsRepositoryProvider).manageEventStaff(
                      eventId: eventId,
                      userId: staff['user_id'],
                      role: staff['role'],
                      quotaStandard: std,
                      quotaGuest: guest,
                      quotaInvitation: inv,
                    );
                ref.invalidate(eventStaffProvider);
                if (context.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.eventSaveError)),
                  );
                }
              }
            },
            child: Text(l10n.save),
          )
        ],
      ),
    );
  }
}

class _QuotaBadge extends StatelessWidget {
  final String title;
  final int used;
  final int total;
  final Color color;

  const _QuotaBadge({
    required this.title,
    required this.used,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            '$used / ${total == 0 ? '∞' : total}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        )
      ],
    );
  }
}
