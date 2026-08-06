import 'package:flutter/material.dart';
import 'package:imagine_access/core/ui/empty_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_roles.dart';
import '../data/event_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import 'event_state.dart';

import 'package:imagine_access/l10n/generated/app_localizations.dart';

class AdminEventList extends ConsumerWidget {
  final List<Map<String, dynamic>> events;
  final bool isArchived;

  const AdminEventList(
      {super.key, required this.events, this.isArchived = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final role = ref.watch(userRoleProvider);
    final isDevice = ref.watch(deviceProvider) != null;
    final displayRole = isDevice ? AppRoles.door : role;
    final isAdmin = AppRoles.isAdmin(displayRole);

    if (events.isEmpty) {
      return EmptyState(
        icon: Icons.event_outlined,
        title: l10n.noEventsYet,
        body: l10n.noEventsYetBody,
        // Solo un admin puede crear eventos: a un RRPP ofrecerle el botón lo
        // manda a una pantalla que le va a rebotar.
        actionLabel: isAdmin ? l10n.createFirstEvent : null,
        actionIcon: Icons.add,
        onAction: isAdmin ? () => context.push('/create_event') : null,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final event = events[index];
        final date = DateTime.parse((event['date'] as String?) ?? DateTime.now().toIso8601String());
        final isActive = event['is_active'] as bool? ?? false;

        final cardContent = GlassCard(
          onTap: () async {
            if (!isAdmin) {
              // RRPP/Door: Select event directly
              await ref
                  .read(selectedEventProvider.notifier)
                  .selectEvent(event['id'], event['name'], event['slug'] ?? '',
                      currency: event['currency']?.toString());
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${l10n.selected}: ${event['name']}')));
              context.pop();
              return;
            }

            // Admin: Show dialog with all options
            final action = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(event['name']),
                content: Text(l10n.whatToDo),
                actions: [
                  if (!isArchived)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, 'select'),
                      child: Text(l10n.selectForScanning),
                    ),
                  if (!isArchived)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, 'edit'),
                      child: Text(l10n.editEvent.toUpperCase()),
                    ),
                  if (isArchived)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, 'restore'),
                      child: Text(l10n.restoreEvent, style: const TextStyle(color: AppTheme.lima)),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'delete'),
                    child: Text(l10n.delete.toUpperCase(),
                        style: const TextStyle(color: AppTheme.accentOrange)),
                  ),
                ],
              ),
            );

            if (action == 'select' && context.mounted) {
              await ref
                  .read(selectedEventProvider.notifier)
                  .selectEvent(event['id'], event['name'], event['slug'] ?? '',
                      currency: event['currency']?.toString());
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${l10n.selected}: ${event['name']}')));
              context.pop();
            } else if (action == 'edit' && context.mounted) {
              context
                  .push('/create_event', extra: Map<String, dynamic>.from(event))
                  .then((_) => ref.invalidate(eventsProvider));
            } else if (action == 'restore' && context.mounted) {
               try {
                  await ref
                      .read(eventRepositoryProvider)
                      .unarchiveEvent(event['id']);
                  ref.read(eventRepositoryProvider).clearCache();
                  ref.invalidate(eventsProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(l10n.eventArchiveError)));
                  }
                }
            } else if (action == 'delete' && context.mounted) {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.deleteEventQuery),
                  content: Text(l10n.deleteEventConfirm),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(l10n.cancel)),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(l10n.delete.toUpperCase(),
                            style: const TextStyle(color: AppTheme.accentOrange))),
                  ],
                ),
              );

              if (confirm == true) {
                try {
                  await ref
                      .read(eventRepositoryProvider)
                      .deleteEvent(event['id']);
                  ref.read(eventRepositoryProvider).clearCache();
                  ref.invalidate(eventsProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(l10n.deleteErrorMessage)));
                  }
                }
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      color: isActive
                        ? AppTheme.accentGreen.withValues(alpha: 0.1)
                        : AppTheme.accentPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      border: Border.all(
                          color: isActive
                              ? AppTheme.accentGreen
                              : Colors.transparent)),
                  child: Center(
                    child: Text(
                      date.day.toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event['name'],
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                          "${event['venue']} • ${event['ticket_types']?.length ?? 0} ${l10n.types}",
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (isAdmin)
                  const Icon(Icons.edit, color: AppTheme.neonBlue, size: 20)
              ],
            ),
          ),
        ).animate().fade(duration: 300.ms, delay: (100 * index).ms).slideX();

        if (!isAdmin) return cardContent;

        return Dismissible(
          key: Key(event['id']),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                      title: Text(l10n.deleteEventQuery),
                      content: Text(l10n.deleteEventConfirm),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(l10n.cancel)),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(l10n.delete,
                                style: const TextStyle(color: AppTheme.accentOrange))),
                      ],
                    ));
            if (confirmed != true) return false;
            try {
              await ref.read(eventRepositoryProvider).deleteEvent(event['id']);
              ref.read(eventRepositoryProvider).clearCache();
              ref.invalidate(eventsProvider);
              return true;
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.deleteErrorMessage)));
              }
              return false;
            }
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: AppTheme.accentOrange.withValues(alpha: 0.2),
            child: const Icon(Icons.delete, color: AppTheme.accentOrange),
          ),
          child: cardContent,
        );
      },
    );
  }
}
