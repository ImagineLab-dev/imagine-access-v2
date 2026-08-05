import 'package:flutter/material.dart';
import 'package:imagine_access/core/ui/empty_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;
import 'dart:developer' as dev;
import 'package:flutter_animate/flutter_animate.dart';
import '../data/ticket_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/constants/app_roles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/ui/custom_input.dart';
import '../../../core/ui/pase_ticket.dart';
import '../../../core/ui/status_badge.dart';
import '../../events/presentation/event_state.dart';

import 'package:imagine_access/l10n/generated/app_localizations.dart';

// Provider for tickets list with pagination
final ticketsProvider =
    AutoDisposeAsyncNotifierProvider<TicketsNotifier, List<Map<String, dynamic>>>(
        TicketsNotifier.new);

class TicketsNotifier extends AutoDisposeAsyncNotifier<List<Map<String, dynamic>>> {
  static const _pageSize = 50;
  int _offset = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  bool get hasMore => _hasMore;

  @override
  Future<List<Map<String, dynamic>>> build() async {
    _offset = 0;
    _hasMore = true;
    _isLoadingMore = false;
    final data = await ref.read(ticketRepositoryProvider).getTickets(limit: _pageSize, offset: 0);
    _offset = data.length;
    _hasMore = data.length >= _pageSize;
    return data;
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    try {
      final current = state.valueOrNull ?? [];
      final next = await ref.read(ticketRepositoryProvider).getTickets(limit: _pageSize, offset: _offset);
      _offset += next.length;
      _hasMore = next.length >= _pageSize;
      state = AsyncData([...current, ...next]);
    } catch (e) {
      if (kDebugMode) dev.log('Error in loadMore', error: e, name: 'TicketsNotifier');
    } finally {
      _isLoadingMore = false;
    }
  }
}

// REALTIME UPDATER for Tickets List
final ticketsRealtimeProvider = Provider.autoDispose<void>((ref) {
  final supabase = Supabase.instance.client;
  final selectedEvent = ref.watch(selectedEventProvider);
  final eventId = selectedEvent?['id'] as String?;
  if (eventId == null) return;

  final channel = supabase
      .channel('tickets_updates_$eventId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tickets',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'event_id',
          value: eventId,
        ),
        callback: (payload) {
          if (kDebugMode) dev.log('Realtime change in tickets for event $eventId', name: 'TicketsRealtime');
          ref.invalidate(ticketsProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'checkins',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'event_id',
          value: eventId,
        ),
        callback: (payload) {
          if (kDebugMode) dev.log('Realtime change in checkins for event $eventId', name: 'TicketsRealtime');
          ref.invalidate(ticketsProvider);
        },
      )
      .subscribe();

  ref.onDispose(() {
    supabase.removeChannel(channel);
  });
});

class TicketListScreen extends ConsumerStatefulWidget {
  const TicketListScreen({super.key});

  @override
  ConsumerState<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends ConsumerState<TicketListScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'all';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _deepLinkHandled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_deepLinkHandled) {
      _deepLinkHandled = true;
      final extra = GoRouterState.of(context).extra;
      if (extra is Map) {
        final q = extra['searchQuery'] as String?;
        if (q != null && q.isNotEmpty) {
          _searchQuery = q;
          _searchController.text = q;
        }
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final notifier = ref.read(ticketsProvider.notifier);
      if (notifier.hasMore) {
        notifier.loadMore();
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(ticketsProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Start Realtime Listeners
    ref.watch(ticketsRealtimeProvider);

    return GlassScaffold(
      titulo: l10n.guestList,
      acciones: [
        IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(ticketsProvider)),
      ],
      body: Column(
        children: [
          _buildSearchAndFilter(theme, isDark, l10n),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(ticketsProvider),
              child: ticketsAsync.when(
              data: (tickets) {
                // Filter logic
                final filtered = tickets.where((t) {
                  final matchSearch = t['buyer_name']
                          .toString()
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()) ||
                      t['buyer_email']
                          .toString()
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()) ||
                      (t['buyer_doc'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()) ||
                      (t['buyer_phone'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()) ||
                      (t['id'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase());

                  final hasCheckins =
                      (t['checkins'] as List?)?.isNotEmpty ?? false;
                  final rawStatus = (t['status'] ?? 'valid').toString().toLowerCase();
                  final currentStatus = rawStatus == 'void'
                      ? 'void'
                      : (hasCheckins ? 'used' : rawStatus);

                  final matchFilter = _selectedFilter == 'all' ||
                      currentStatus == _selectedFilter;
                  return matchSearch && matchFilter;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Con búsqueda activa el vacío significa "no coincide
                        // nada", no "todavía no creaste tickets": ofrecer
                        // "crear ticket" ahí sería desorientador.
                        EmptyState(
                          icon: Icons.confirmation_number_outlined,
                          title: l10n.noTicketsYet,
                          body: l10n.noTicketsYetBody,
                          actionLabel: l10n.createFirstTicket,
                          actionIcon: Icons.add,
                          onAction: () => context.push('/create_ticket'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _buildTicketCard(filtered[index], theme, l10n)
                        .animate()
                        .fade()
                        .slideX(begin: 0.1, end: 0, delay: (50 * index).ms);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                  child: Text(l10n.error,
                      style: TextStyle(color: theme.colorScheme.error))),
            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter(
      ThemeData theme, bool isDark, AppLocalizations l10n) {
    return GlassCard(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        children: [
          CustomInput(
            label: l10n.search,
            controller: _searchController,
            hint: l10n.searchHint,
            prefixIcon: Icons.search,
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                    label: l10n.all,
                    value: 'all',
                    groupValue: _selectedFilter,
                    onChanged: (v) => setState(() => _selectedFilter = v)),
                const SizedBox(width: 8),
                _FilterChip(
                    label: l10n.validCaps,
                    value: 'valid',
                    groupValue: _selectedFilter,
                    onChanged: (v) => setState(() => _selectedFilter = v)),
                const SizedBox(width: 8),
                _FilterChip(
                    label: l10n.usedCaps,
                    value: 'used',
                    groupValue: _selectedFilter,
                    onChanged: (v) => setState(() => _selectedFilter = v)),
                const SizedBox(width: 8),
                _FilterChip(
                    label: l10n.voidCaps,
                    value: 'void',
                    groupValue: _selectedFilter,
                    onChanged: (v) => setState(() => _selectedFilter = v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketCard(
      Map<String, dynamic> ticket, ThemeData theme, AppLocalizations l10n) {
    final buyerName = ticket['buyer_name'] ?? l10n.guest;
    final type = ticket['type'] ?? 'general';
    final id = ticket['id'];

    final hasCheckins = (ticket['checkins'] as List?)?.isNotEmpty ?? false;
    final dbStatus = (ticket['status'] ?? 'valid').toString().toLowerCase();
    final rawStatus = hasCheckins ? 'used' : dbStatus;

    BadgeStatus badgeStatus = BadgeStatus.neutral;
    String statusText = rawStatus.toUpperCase();

    if (rawStatus == 'valid') {
      badgeStatus = BadgeStatus.success;
      statusText = l10n.validCaps;
    } else if (rawStatus == 'used') {
      badgeStatus = BadgeStatus.warning;
      statusText = l10n.usedCaps;
    } else if (rawStatus == 'void') {
      badgeStatus = BadgeStatus.error;
      statusText = l10n.voidCaps;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        onTap: () {
          _showTicketDetails(context, ticket, l10n, ref);
        },
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              ),
              child: Icon(Icons.confirmation_num_outlined,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(buyerName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    l10n.sentByLine(
                      ticket['users_profile']?['display_name'] ?? l10n.systemUser,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(type.toString().toUpperCase(),
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary)),
                      const SizedBox(width: 8),
                      Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                              color:
                                theme.colorScheme.onSurface.withValues(alpha: 0.3))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(id.toString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5)),
                              overflow: TextOverflow.ellipsis)),
                      if (ticket['email_sent_at'] != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Tooltip(
                              message: l10n.emailSent,
                              child: Icon(Icons.mark_email_read,
                                  size: 16, color: theme.colorScheme.primary)),
                        ),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(text: statusText, status: badgeStatus),
          ],
        ),
      ),
    );
  }

  void _showTicketDetails(BuildContext context, Map<String, dynamic> ticket,
      AppLocalizations l10n, WidgetRef ref) {
    final role = ref.read(userRoleProvider);
    final isDevice = ref.read(deviceProvider) != null;
    final isAdmin = AppRoles.isAdmin(role);
    final canResend = isAdmin || role == AppRoles.rrpp;
    final parentMessenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          final theme = Theme.of(context);
          final id = ticket['id'];
          final status = ticket['status'] ?? 'valid';
          final isVoid = status == 'void';

          final fondoHoja = AppTheme.fondo(context);

          return Container(
            decoration: BoxDecoration(
              color: fondoHoja,
              border: Border(
                top: BorderSide(color: AppTheme.borde(context)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 34),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tirador. Rectangular, como todo lo demás.
                  Center(
                    child: Container(
                      width: 34,
                      height: 3,
                      color: AppTheme.borde(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(l10n.ticketDetails.toUpperCase(),
                      style: AppTheme.titular(context, size: 17)),
                  const SizedBox(height: 16),

                  // El pase en sí. Reemplaza a la lista de siete filas que
                  // había: la misma información, pero con la forma del objeto
                  // que la persona muestra en la puerta.
                  PaseTicket(
                    colorFondo: fondoHoja,
                    anulado: isVoid,
                    titulo: (ticket['events']?['name'] ?? l10n.event).toString(),
                    subtitulo: (ticket['type'] ?? '').toString(),
                    serial: id.toString(),
                    // Sin traducir a propósito: "ID" se lee igual en los tres
                    // idiomas y es lo que dice el correo del ticket.
                    etiquetaSerial: 'ID',
                    datos: [
                      (l10n.buyerInfo, (ticket['buyer_name'] ?? l10n.guest).toString()),
                      (l10n.statusLabel, status.toString().toUpperCase()),
                      (l10n.email, (ticket['buyer_email'] ?? l10n.unknown).toString()),
                      if (ticket['email_sent_at'] != null)
                        (l10n.emailSent, _formatDate(ticket['email_sent_at'])),
                    ],
                  ),

                  const SizedBox(height: 26),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.share_outlined),
                        label: Text(l10n.share),
                        onPressed: () {
                          final link = 'imagineaccess://ticket/$id';
                          final message = l10n.sharedTicketMessage(link, id.toString());
                          SharePlus.instance.share(ShareParams(text: message));
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ),
                    if (canResend && !isDevice) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.email_outlined),
                          label: Text(l10n.resendEmail),
                          onPressed: () async {
                            // Los colores se leen ANTES del await, igual que
                            // `parentMessenger`: después de cerrar la hoja este
                            // `context` ya está desmontado y consultarle el tema
                            // es leer un árbol que no existe.
                            final fondo = AppTheme.panelElevado(context);
                            final ok = AppTheme.acentoTexto(context);
                            final mal = AppTheme.peligroTexto(context);

                            Navigator.pop(context);
                            try {
                              parentMessenger.showSnackBar(
                                  SnackBar(content: Text(l10n.sending)));
                              await ref
                                  .read(ticketRepositoryProvider)
                                  .resendTicket(id);
                              parentMessenger.showSnackBar(SnackBar(
                                  content: Text(l10n.emailResent),
                                  backgroundColor: fondo,
                                  shape: Border(
                                      left: BorderSide(color: ok, width: 4))));
                            } catch (e) {
                              parentMessenger.showSnackBar(SnackBar(
                                  content: Text(l10n.resendCodeError),
                                  backgroundColor: fondo,
                                  shape: Border(
                                      left: BorderSide(color: mal, width: 4))));
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: theme.colorScheme.primary),
                          ),
                        ),
                      ),
                    ],
                    if (!isVoid && isAdmin && !isDevice) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.block, color: Colors.white),
                          label: Text(l10n.voidTicket,
                              style: const TextStyle(color: Colors.white)),
                          onPressed: () {
                            showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                      title: Text(l10n.voidTicket),
                                      content: Text(l10n.confirmVoid),
                                      actions: [
                                        TextButton(
                                            child: Text(l10n.cancel),
                                            onPressed: () =>
                                                Navigator.pop(ctx)),
                                        TextButton(
                                            child: Text(l10n.confirm,
                                                style: const TextStyle(
                                                    color: AppTheme.accentOrange)),
                                            onPressed: () async {
                                              Navigator.pop(ctx);
                                              Navigator.pop(context);
                                              try {
                                                parentMessenger
                                                    .showSnackBar(SnackBar(
                                                        content: Text(
                                                            l10n.voiding)));
                                                await ref
                                                    .read(
                                                        ticketRepositoryProvider)
                                                    .voidTicket(id);
                                                ref.invalidate(ticketsProvider);
                                                parentMessenger
                                                    .showSnackBar(SnackBar(
                                                        content: Text(l10n
                                                            .ticketVoided),
                                                        backgroundColor:
                                                            AppTheme.lima));
                                              } catch (e) {
                                                parentMessenger
                                                    .showSnackBar(SnackBar(
                                                        content:
                                                            Text(l10n.voidTicketError),
                                                        backgroundColor:
                                                            AppTheme.accentOrange));
                                              }
                                            }),
                                      ],
                                    ));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ]
                    ],
                  ),
                ],
              ),
            ),
          );
        });
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      return "${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return isoString;
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onChanged;

  const _FilterChip(
      {required this.label,
      required this.value,
      required this.groupValue,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isSelected = groupValue == value;
    final theme = Theme.of(context);

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (v) => onChanged(value),
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.5),
        selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
          color: isSelected
              ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          fontWeight: FontWeight.bold,
          fontSize: 12),
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary
          : theme.colorScheme.onSurface.withValues(alpha: 0.1),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      showCheckmark: false,
    );
  }
}
