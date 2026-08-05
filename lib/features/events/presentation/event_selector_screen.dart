import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/glass_scaffold.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_roles.dart';
import '../data/event_repository.dart';
import 'create_event_screen.dart';
import 'admin_event_list.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

class EventSelectorScreen extends ConsumerWidget {
  const EventSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider);
    final role = ref.watch(userRoleProvider);
    final l10n = AppLocalizations.of(context);

    return DefaultTabController(
      length: 2,
      // El título va dentro del contenido y las pestañas bajan con él: dentro
      // del armazón, un `AppBar` propio dejaba dos barras apiladas —la global
      // con la marca y esta con el título— comiéndose 116 px antes de que
      // empezara la lista.
      child: GlassScaffold(
        titulo: l10n.manageEvents,
        acciones: [
          if (AppRoles.isAdmin(role))
            IconButton(
                tooltip: l10n.createEvent,
                onPressed: () {
                  Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (_) => const CreateEventScreen()))
                      .then((_) => ref.invalidate(eventsProvider));
                },
                icon: const Icon(Icons.add_circle_outline))
        ],
        body: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.borde(context)),
                ),
              ),
              child: TabBar(
                tabs: [
                  Tab(text: l10n.active.toUpperCase()),
                  Tab(text: l10n.archived.toUpperCase()),
                ],
              ),
            ),
            Expanded(
              child: eventsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Center(child: Text(l10n.error)),
                  data: (events) {
                    final activeEvents = events
                        .where((e) => (e['is_archived'] as bool? ?? false) == false)
                        .toList();
                    final archivedEvents = events
                        .where((e) => (e['is_archived'] as bool? ?? false) == true)
                        .toList();

                    return TabBarView(
                      children: [
                        AdminEventList(events: activeEvents),
                        AdminEventList(
                            events: archivedEvents,
                            isArchived: true),
                      ],
                    );
                  }),
            ),
          ],
        ),
      ),
    );
  }
}
