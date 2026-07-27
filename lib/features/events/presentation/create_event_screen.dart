import 'dart:developer' as dev;
import 'package:imagine_access/core/platform/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/ui/custom_input.dart';
import '../../../core/ui/neon_button.dart';
import '../../../core/theme/app_theme.dart';
import '../data/event_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/constants/app_roles.dart';
import '../../tickets/data/ticket_repository.dart';
import '../../settings/data/settings_repository.dart'; // To get default currency
import 'ticket_types_widget.dart';
import 'event_state.dart'; // To access selectedEventProvider

import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../../core/utils/error_handler.dart';

// ─── Date helpers ───
// Parse a stored date string back to a local DateTime (wall-clock time).
// Dates are stored as wall-clock time (no UTC conversion), so we just parse
// and treat the result as local regardless of the offset the DB appends.
DateTime _parseWallClock(String isoStr) {
    final dt = DateTime.parse(isoStr);
    // Return as local DateTime with the same year/month/day/hour/minute
    return DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);
}

class CreateEventScreen extends ConsumerStatefulWidget {
  final String? eventId; // If null, create mode. If set, edit mode.
  final Map<String, dynamic>? initialData;

  const CreateEventScreen({super.key, this.eventId, this.initialData});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _nameCtrl;
  late TextEditingController _slugCtrl;
  late TextEditingController _venueCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _cityCtrl;

  /// Arte del evento que viaja en el correo del ticket.
  String? _imageUrl;
  bool _subiendoArte = false;

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 30));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 20, minute: 0);
  String _currency = 'PYG';
  String _timezone = 'America/Asuncion';

  List<Map<String, dynamic>> _ticketTypes = [];
  final List<String> _deletedTicketTypeIds = []; // Track deletions
  bool _isLoading = false;

  // Professional Features
  bool _hasStaffTicket = false;
  bool _hasGuestTicket = false;
  bool _hasInvitationTicket = false;
  TimeOfDay? _invitationValidUntil; // Time limit for invitations
  int _invitationToleranceMinutes = 0; // Grace period (internal only)
  bool _hasPromoTicket = false;
  double _promoPrice = 0;
  int _promoQty = 2;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? {};

    _nameCtrl = TextEditingController(text: data['name']);
    _slugCtrl = TextEditingController(text: data['slug']);
    _venueCtrl = TextEditingController(text: data['venue']);
    _addressCtrl = TextEditingController(text: data['address']);
    _cityCtrl = TextEditingController(text: data['city']);
    _imageUrl = data['image_url'] as String?;
    _currency = data['currency'] ?? 'PYG';
    _timezone = data['timezone'] ?? 'America/Asuncion';

    if (data['date'] != null) {
      final parsed = _parseWallClock(data['date']);
      _selectedDate = parsed;
      _selectedTime = TimeOfDay.fromDateTime(parsed);
    }

    // If editing, we would fetch types here. For now start empty or from passed data.
    if (data['ticket_types'] != null) {
      final rawTypes = List<Map<String, dynamic>>.from(data['ticket_types']);
      // Detect special types
      _hasStaffTicket = rawTypes.any((t) => t['category'] == 'staff');
      _hasGuestTicket = rawTypes.any((t) => t['category'] == 'guest');
      _hasInvitationTicket = rawTypes.any((t) => t['category'] == 'invitation');
      _hasPromoTicket = rawTypes.any((t) => t['category'] == 'promo');

      if (_hasPromoTicket) {
        final promoType = rawTypes.cast<Map<String, dynamic>?>().firstWhere(
            (t) => t!['category'] == 'promo',
            orElse: () => null);
        if (promoType != null) {
          _promoPrice = (promoType['price'] as num?)?.toDouble() ?? 0;
          _promoQty = (promoType['promo_qty'] as int?) ?? 2;
        }
      }

      if (_hasInvitationTicket) {
        final invType = rawTypes.cast<Map<String, dynamic>?>().firstWhere(
            (t) => t!['category'] == 'invitation',
            orElse: () => null);
        if (invType != null && invType['valid_until'] != null) {
          final dtRaw = _parseWallClock(invType['valid_until']);
          _invitationValidUntil = TimeOfDay.fromDateTime(dtRaw);
        }
        if (invType != null && invType['tolerance_minutes'] != null) {
          _invitationToleranceMinutes = invType['tolerance_minutes'] as int;
        }
      }

      // Filter out special types from manual list
      _ticketTypes = rawTypes
          .where((t) =>
              t['category'] != 'staff' &&
              t['category'] != 'guest' &&
              t['category'] != 'invitation' &&
              t['category'] != 'promo')
          .toList();
    }

    // Default currency from settings if creating new
    if (widget.eventId == null) {
      Future.microtask(() async {
        final defaultCurrency =
            await ref.read(settingsRepositoryProvider).getDefaultCurrency();
        if (mounted) {
          setState(() => _currency = defaultCurrency);
        }
      });
    }

    // Auto-generate slug listener
    _nameCtrl.addListener(() {
      if (widget.eventId == null && _nameCtrl.text.isNotEmpty) {
        // Only auto-generate on create
        _slugCtrl.text = _nameCtrl.text
            .toLowerCase()
            .replaceAll(' ', '-')
            .replaceAll(RegExp(r'[^a-z0-9-]'), '');
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    _venueCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    // Check for duplicate ticket type names
    final typeNames = _ticketTypes
        .map((t) => (t['name'] as String?)?.trim().toUpperCase() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final seen = <String>{};
    final dupes = <String>{};
    for (final n in typeNames) {
      if (!seen.add(n)) dupes.add(n);
    }
    if (dupes.isNotEmpty) {
      ErrorHandler.showErrorSnackBar(
          context, l10n.duplicateTicketTypeNames(dupes.join(', ')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Combine Date & Time — use DateTime.utc so the Z suffix forces PostgreSQL
      // to store exactly this wall-clock hour regardless of DB timezone setting.
      final fullDate = DateTime.utc(_selectedDate.year, _selectedDate.month,
          _selectedDate.day, _selectedTime.hour, _selectedTime.minute);

      String newEventId;

      if (widget.eventId == null) {
        // Create — associate with user's organization
        final authController = ref.read(authControllerProvider.notifier);
        var orgId = ref.read(organizationIdProvider);

        // Ensure JWT has fresh metadata (role + org) before INSERT
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null && user.appMetadata['role'] == null) {
          final refreshed =
              await Supabase.instance.client.auth.refreshSession();
          if (refreshed.user != null) {
            ref.read(userProvider.notifier).state = refreshed.user;
            orgId = refreshed.user!.appMetadata['organization_id'] as String?;
          }
        }

        orgId ??= await authController.ensureOrganizationReady();

        Map<String, dynamic> res;
        final baseSlug = _slugCtrl.text;
        try {
          res = await ref.read(eventRepositoryProvider).createEvent(
                name: _nameCtrl.text,
                venue: _venueCtrl.text,
                address: _addressCtrl.text,
                city: _cityCtrl.text,
                slug: baseSlug,
                date: fullDate,
                currency: _currency,
                timezone: _timezone,
                organizationId: orgId,
              );
        } on PostgrestException catch (e) {
          final isOrgFkError =
              e.code == '23503' && e.message.contains('organization_id_fkey');
          final isRlsError = e.code == '42501';
          final isSlugDup = e.code == '23505' && e.message.contains('slug');
          if (!isOrgFkError && !isRlsError && !isSlugDup) rethrow;

          if (isSlugDup) {
            // Slug conflict: append random suffix and retry
            final uniqueSlug =
                '$baseSlug-${DateTime.now().millisecondsSinceEpoch % 100000}';
            res = await ref.read(eventRepositoryProvider).createEvent(
                  name: _nameCtrl.text,
                  venue: _venueCtrl.text,
                  address: _addressCtrl.text,
                  city: _cityCtrl.text,
                  slug: uniqueSlug,
                  date: fullDate,
                  currency: _currency,
                  organizationId: orgId,
                );
          } else {
            // RLS or FK error: refresh session and retry
            final refreshed =
                await Supabase.instance.client.auth.refreshSession();
            if (refreshed.user != null) {
              ref.read(userProvider.notifier).state = refreshed.user;
            }

            final repairedOrgId =
                await authController.ensureOrganizationReady();
            res = await ref.read(eventRepositoryProvider).createEvent(
                  name: _nameCtrl.text,
                  venue: _venueCtrl.text,
                  address: _addressCtrl.text,
                  city: _cityCtrl.text,
                  slug: baseSlug,
                  date: fullDate,
                  currency: _currency,
                  organizationId: repairedOrgId,
                );
          }
        }
        newEventId = res['id'];
      } else {
        // Update
        await ref.read(eventRepositoryProvider).updateEvent(widget.eventId!, {
          'name': _nameCtrl.text,
          'venue': _venueCtrl.text,
          'address': _addressCtrl.text,
          'city': _cityCtrl.text,
          'slug': _slugCtrl.text,
          'date': fullDate.toIso8601String(),
          'currency': _currency,
          'timezone': _timezone,
          'image_url': _imageUrl,
        });
        newEventId = widget.eventId!;
      }

      // 1. Handle Deletions
      for (var id in _deletedTicketTypeIds) {
        await ref.read(eventRepositoryProvider).deleteTicketType(id);
      }

      // 2. Save Ticket Types (Create & Update)
      for (var type in _ticketTypes) {
        if (type['is_new'] == true) {
          await ref.read(eventRepositoryProvider).createTicketType(
                eventId: newEventId,
                name: type['name'],
                price: (type['price'] as num).toDouble(),
                currency: _currency,
                color: type['color'],
              );
        } else if (type['id'] != null) {
          // Update existing
          await ref.read(eventRepositoryProvider).updateTicketType(type['id'], {
            'name': type['name'],
            'price': (type['price'] as num).toDouble(),
            'currency': _currency,
            'color': type['color'],
          });
        }
      }

      // 3. Handle Professional Tickets (Staff/Guest)
      Future<void> handleSpecialType(String category, String name) async {
        // Check if exists in original data to get ID
        final original = ((widget.initialData?['ticket_types'] ?? []) as List)
            .firstWhere((t) => t['category'] == category, orElse: () => null);

        DateTime? validUntilDate;
        if (category == 'invitation' && _invitationValidUntil != null) {
          // Use DateTime.utc so toIso8601String() emits Z suffix → PostgreSQL
          // stores exactly this wall-clock hour regardless of DB timezone.
          validUntilDate = DateTime.utc(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              _invitationValidUntil!.hour,
              _invitationValidUntil!.minute);
          // If cutoff time is before event start, it means after midnight → next day
          final eventMinutes = _selectedTime.hour * 60 + _selectedTime.minute;
          final cutoffMinutes =
              _invitationValidUntil!.hour * 60 + _invitationValidUntil!.minute;
          if (cutoffMinutes < eventMinutes) {
            validUntilDate = validUntilDate.add(const Duration(days: 1));
          }
        }

        // Default Colors
        String color = '#4F46E5'; // Default
        if (category == 'staff') {
          color = '#3B82F6'; // Blue
        } else if (category == 'invitation') {
          color = '#A855F7'; // Purple
        } else if (category == 'guest') {
          color = '#EC4899'; // Pink
        }

        if (original != null) {
          // Already exists. Ensure it's active.
          await ref
              .read(eventRepositoryProvider)
              .updateTicketType(original['id'], {
            'name': name,
            'price': 0,
            'currency': _currency,
            'category': category,
            'is_active': true,
            'valid_until': validUntilDate?.toIso8601String(),
            'tolerance_minutes': category == 'invitation' ? _invitationToleranceMinutes : 0,
            'color': color
          });
        } else {
          // Create New
          await ref.read(eventRepositoryProvider).createTicketType(
              eventId: newEventId,
              name: name,
              price: 0,
              currency: _currency,
              category: category,
              validUntil: validUntilDate,
              toleranceMinutes: category == 'invitation' ? _invitationToleranceMinutes : 0,
              color: color);
        }
      }

      Future<void> deleteSpecialType(String category) async {
        final original = ((widget.initialData?['ticket_types'] ?? []) as List)
            .firstWhere((t) => t['category'] == category, orElse: () => null);
        if (original != null) {
          await ref
              .read(eventRepositoryProvider)
              .deleteTicketType(original['id']);
        }
      }

      if (_hasStaffTicket) {
        await handleSpecialType('staff', l10n.ticketTypeStaffAccess);
      } else {
        await deleteSpecialType('staff');
      }

      if (_hasInvitationTicket) {
        await handleSpecialType('invitation', l10n.ticketTypeInvitation);
      } else {
        await deleteSpecialType('invitation');
      }

      if (_hasGuestTicket) {
        await handleSpecialType('guest', l10n.ticketTypeSpecialGuest);
      } else {
        await deleteSpecialType('guest');
      }

      if (_hasPromoTicket) {
        final promoOriginal = ((widget.initialData?['ticket_types'] ?? []) as List)
            .firstWhere((t) => t['category'] == 'promo', orElse: () => null);
        if (promoOriginal != null) {
          await ref.read(eventRepositoryProvider).updateTicketType(promoOriginal['id'], {
            'name': l10n.ticketTypePromo,
            'price': _promoPrice,
            'currency': _currency,
            'category': 'promo',
            'is_active': true,
            'color': '#F97316',
            'promo_qty': _promoQty,
          });
        } else {
          // Atomic creation: promoQty is set in the initial INSERT (no second round-trip)
          await ref.read(eventRepositoryProvider).createTicketType(
              eventId: newEventId,
              name: l10n.ticketTypePromo,
              price: _promoPrice,
              currency: _currency,
              category: 'promo',
              color: '#F97316',
              promoQty: _promoQty);
        }
      } else {
        await deleteSpecialType('promo');
      }

      ref.read(eventRepositoryProvider).clearCache();
      ref.invalidate(eventsProvider);
      // Also invalidate price provider for the wizard
      ref.invalidate(ticketTypesProvider(newEventId));

      if (mounted) context.pop();
    } catch (e, st) {
      if (kDebugMode) dev.log('EVENT SAVE FAILED: $e', name: 'CreateEvent', stackTrace: st);
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, l10n.eventSaveError);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _subirArte(AppLocalizations l10n) async {
    final archivo = await pickFile(accept: 'image/png,image/jpeg,image/webp');
    if (archivo == null) return;

    // 2 MB: el arte viaja por correo y varios proveedores recortan mensajes
    // pesados, ademas de que nadie quiere bajar 8 MB en datos moviles.
    if (archivo.bytes.lengthInBytes > 2 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.imageTooLarge)));
      }
      return;
    }

    setState(() => _subiendoArte = true);
    try {
      final ext = archivo.extension.isEmpty ? 'png' : archivo.extension;
      final ruta = 'events/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storage = Supabase.instance.client.storage.from('event-artwork');
      await storage.uploadBinary(
        ruta,
        archivo.bytes,
        fileOptions: FileOptions(contentType: archivo.mimeType, upsert: true),
      );
      if (!mounted) return;
      setState(() => _imageUrl = storage.getPublicUrl(ruta));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.imageUploadError)));
      }
    } finally {
      if (mounted) setState(() => _subiendoArte = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final role = ref.watch(userRoleProvider);

    if (!AppRoles.isAdmin(role)) {
      return GlassScaffold(
        appBar: AppBar(title: Text(l10n.newEvent)),
        body: Center(child: Text(l10n.noPermission)),
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: Text(widget.eventId == null ? l10n.newEvent : l10n.editEvent),
        actions: [
          if (widget.eventId != null)
            IconButton(
              icon: const Icon(Icons.archive, color: Colors.amber),
              onPressed: () async {
                try {
                  await ref.read(eventRepositoryProvider).archiveEvent(widget.eventId!);
                  ref.read(eventRepositoryProvider).clearCache();
                  ref.invalidate(eventsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.eventArchived)),
                    );
                    context.pop();
                  }
                } catch (e) {
                  if (context.mounted) {
                    ErrorHandler.showErrorSnackBar(context, l10n.eventArchiveError);
                  }
                }
              },
            ),
          if (widget.eventId != null)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              onPressed: () async {
                final l10n = AppLocalizations.of(context);
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
                              style: const TextStyle(color: Colors.red))),
                    ],
                  ),
                );

                if (confirm == true) {
                  try {
                    await ref
                        .read(eventRepositoryProvider)
                        .deleteEvent(widget.eventId!);
                    ref.read(eventRepositoryProvider).clearCache();
                    ref.invalidate(eventsProvider);
                    if (context.mounted) context.pop();
                  } catch (e) {
                    if (context.mounted) {
                      ErrorHandler.showErrorSnackBar(context, l10n.deleteErrorMessage);
                    }
                  }
                }
              },
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Basic Info
              Text(l10n.eventDetails, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              CustomInput(
                  label: l10n.eventName,
                  controller: _nameCtrl,
                  icon: Icons.event,
                  validator: (v) => v!.isEmpty ? l10n.required : null),
              const SizedBox(height: 12),
              CustomInput(
                  label: '${l10n.slug} (URL ID)',
                  controller: _slugCtrl,
                  icon: Icons.link,
                  validator: (v) => v!.isEmpty ? l10n.required : null),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2025),
                            lastDate: DateTime(2030));
                        if (d != null) setState(() => _selectedDate = d);
                      },
                      child: CustomInput(
                          key: ValueKey(_selectedDate), // Force rebuild
                          label: l10n.date,
                          icon: Icons.calendar_today,
                          enabled: false,
                          initialValue:
                              "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: () async {
                        final t = await showTimePicker(
                            context: context, initialTime: _selectedTime);
                        if (t != null) setState(() => _selectedTime = t);
                      },
                      child: CustomInput(
                          key: ValueKey(_selectedTime), // Force rebuild
                          label: l10n.time,
                          icon: Icons.access_time,
                          enabled: false,
                          initialValue: _selectedTime.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Location Section
              Text(l10n.location,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: AppTheme.accentBlue)),
              const SizedBox(height: 12),
              CustomInput(
                  label: l10n.venueName,
                  controller: _venueCtrl,
                  icon: Icons.stadium,
                  validator: (v) => v!.isEmpty ? l10n.required : null),
              const SizedBox(height: 12),
              CustomInput(
                  label: l10n.address,
                  controller: _addressCtrl,
                  icon: Icons.location_on,
                  validator: (v) => v!.isEmpty ? l10n.required : null),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      flex: 3,
                      child: CustomInput(
                          label: l10n.city,
                          controller: _cityCtrl,
                          icon: Icons.location_city)),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            l10n.currencyLabel,
                            style: TextStyle(
                              color: theme.brightness == Brightness.dark
                                  ? Colors.white70
                                  : Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey(_currency),
                          initialValue: _currency,
                          dropdownColor: theme.brightness == Brightness.dark
                              ? Colors.black87
                              : Colors.white,
                          style: TextStyle(
                            color: theme.brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            fillColor: theme.brightness == Brightness.dark
                              ? AppTheme.surfaceColor.withValues(alpha: 0.5)
                                : AppTheme.lightInput,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: (theme.brightness == Brightness.dark
                                          ? Colors.white
                                          : Colors.black)
                                  .withValues(alpha: 0.1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: (theme.brightness == Brightness.dark
                                          ? Colors.white
                                          : Colors.black)
                                  .withValues(alpha: 0.1)),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'PYG', child: Text('GS (PYG)')),
                            DropdownMenuItem(
                                value: 'USD', child: Text('USD (\$ )')),
                          ],
                          onChanged: (v) => setState(() => _currency = v!),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Arte del evento: viaja en el correo del ticket, a la derecha
              // del QR.
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  l10n.eventArtwork.toUpperCase(),
                  style: TextStyle(
                    color: theme.brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_imageUrl != null && _imageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        _imageUrl!,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                            width: 88,
                            height: 88,
                            child: Icon(Icons.broken_image_outlined)),
                      ),
                    )
                  else
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: (theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black)
                                .withValues(alpha: 0.12)),
                      ),
                      child: Icon(Icons.image_outlined,
                          color: theme.hintColor, size: 28),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.eventArtworkHint,
                            style: TextStyle(
                                color: theme.hintColor, fontSize: 12.5)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: _subiendoArte
                                  ? null
                                  : () => _subirArte(l10n),
                              icon: _subiendoArte
                                  ? const SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.upload_outlined, size: 18),
                              label: Text(l10n.uploadImage),
                            ),
                            if (_imageUrl != null && _imageUrl!.isNotEmpty)
                              TextButton(
                                onPressed: _subiendoArte
                                    ? null
                                    : () => setState(() => _imageUrl = null),
                                child: Text(l10n.removeImage),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Timezone
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'ZONA HORARIA',
                  style: TextStyle(
                    color: theme.brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(_timezone),
                initialValue: _timezone,
                dropdownColor: theme.brightness == Brightness.dark
                    ? Colors.black87
                    : Colors.white,
                style: TextStyle(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  fillColor: theme.brightness == Brightness.dark
                      ? AppTheme.surfaceColor.withValues(alpha: 0.5)
                      : AppTheme.lightInput,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: (theme.brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black)
                            .withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: (theme.brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black)
                            .withValues(alpha: 0.1)),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'America/Asuncion', child: Text('Paraguay (GMT-3)')),
                  DropdownMenuItem(value: 'America/Argentina/Buenos_Aires', child: Text('Argentina (GMT-3)')),
                  DropdownMenuItem(value: 'America/Sao_Paulo', child: Text('Brasil (GMT-3)')),
                  DropdownMenuItem(value: 'America/Santiago', child: Text('Chile (GMT-3/-4)')),
                  DropdownMenuItem(value: 'America/Bogota', child: Text('Colombia (GMT-5)')),
                  DropdownMenuItem(value: 'America/Mexico_City', child: Text('México (GMT-6)')),
                  DropdownMenuItem(value: 'America/New_York', child: Text('Este EEUU (GMT-4/-5)')),
                  DropdownMenuItem(value: 'America/Los_Angeles', child: Text('Oeste EEUU (GMT-7/-8)')),
                  DropdownMenuItem(value: 'Europe/Madrid', child: Text('España (GMT+1/+2)')),
                  DropdownMenuItem(value: 'Europe/London', child: Text('Reino Unido (GMT+0/+1)')),
                ],
                onChanged: (v) => setState(() => _timezone = v!),
              ),

              const SizedBox(height: 32),

              // 2. Ticket Types
              TicketTypesWidget(
                initialTypes: _ticketTypes,
                currency: _currency, // Pass currency down
                onChanged: (types) => _ticketTypes = types,
                onDeleted: (id) => _deletedTicketTypeIds.add(id),
              ),
              _PricingCard(
                title: l10n.professionalAccessStaff,
                subtitle: l10n.createsStaffAccessTicket,
                icon: Icons.badge,
                color: Colors.blueAccent,
                value: _hasStaffTicket,
                onChanged: (v) => setState(() => _hasStaffTicket = v),
              ),
              const SizedBox(height: 16),
              _PricingCard(
                title: l10n.enableInvitationsNormal,
                subtitle: l10n.createsInvitationTicketForQuotas,
                icon: Icons.mail,
                color: Colors.purpleAccent,
                value: _hasInvitationTicket,
                onChanged: (v) => setState(() => _hasInvitationTicket = v),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () async {
                        final t = await showTimePicker(
                            context: context,
                            initialTime: _invitationValidUntil ??
                                const TimeOfDay(hour: 23, minute: 59));
                        if (t != null) setState(() => _invitationValidUntil = t);
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: 16, color: Colors.white70),
                          const SizedBox(width: 8),
                          Text(
                              _invitationValidUntil == null
                                ? l10n.setValidUntilTimeOptional
                                : l10n.validUntilTime(_invitationValidUntil!.format(context)),
                              style: TextStyle(
                                  color: _invitationValidUntil == null
                                      ? Colors.white54
                                      : Colors.purpleAccent,
                                  fontWeight: _invitationValidUntil == null
                                      ? FontWeight.normal
                                      : FontWeight.bold)),
                          if (_invitationValidUntil != null)
                            IconButton(
                              icon: const Icon(Icons.clear,
                                  size: 16, color: Colors.red),
                              onPressed: () =>
                                  setState(() => _invitationValidUntil = null),
                            )
                        ],
                      ),
                    ),
                    if (_invitationValidUntil != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined,
                              size: 16, color: Colors.white70),
                          const SizedBox(width: 8),
                          Text(l10n.toleranceMinutesLabel,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: _invitationToleranceMinutes,
                            dropdownColor: Colors.grey[900],
                            style: const TextStyle(
                                color: Colors.purpleAccent,
                                fontWeight: FontWeight.bold),
                            underline: const SizedBox.shrink(),
                            items: [0, 5, 10, 15, 20, 30, 45, 60]
                                .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m == 0
                                        ? l10n.noTolerance
                                        : l10n.toleranceMinutesValue(
                                            m.toString()))))
                                .toList(),
                            onChanged: (v) => setState(
                                () => _invitationToleranceMinutes = v ?? 0),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _PricingCard(
                title: l10n.enableVipGuestList,
                subtitle: l10n.createsVipGuestTicketForQuotas,
                icon: Icons.star,
                color: Colors.pinkAccent,
                value: _hasGuestTicket,
                onChanged: (v) => setState(() => _hasGuestTicket = v),
              ),
              const SizedBox(height: 16),
              _PricingCard(
                title: l10n.enablePromoPack,
                subtitle: l10n.promoPackSubtitle,
                icon: Icons.local_offer,
                color: Colors.orangeAccent,
                value: _hasPromoTicket,
                onChanged: (v) => setState(() => _hasPromoTicket = v),
                child: Column(
                  children: [
                    // Price field
                    Row(
                      children: [
                        const Icon(Icons.attach_money,
                            size: 16, color: Colors.white70),
                        const SizedBox(width: 8),
                        Text(l10n.promoPrice,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: _promoPrice > 0
                                ? _promoPrice.toStringAsFixed(0)
                                : '',
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle:
                                  const TextStyle(color: Colors.white38),
                              suffixText: _currency,
                              suffixStyle:
                                  const TextStyle(color: Colors.white54),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              enabledBorder: const UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.white24)),
                              focusedBorder: const UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.orangeAccent)),
                            ),
                            onChanged: (v) {
                              _promoPrice = double.tryParse(v) ?? 0;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Quantity dropdown
                    Row(
                      children: [
                        const Icon(Icons.confirmation_number,
                            size: 16, color: Colors.white70),
                        const SizedBox(width: 8),
                        Text(l10n.promoQty,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: _promoQty,
                          dropdownColor: Colors.grey[900],
                          style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold),
                          underline: const SizedBox.shrink(),
                          items: List.generate(20, (i) => i + 1)
                              .map((n) => DropdownMenuItem(
                                  value: n, child: Text('$n')))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _promoQty = v ?? 2),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              NeonButton(
                  text: l10n.saveEvent,
                  icon: Icons.save,
                  isLoading: _isLoading,
                  onPressed: _save),
              const SizedBox(height: 24),
              if (widget.eventId != null)
                TextButton.icon(
                  onPressed: _deleteEvent,
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: Text(l10n.delete,
                      style: const TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteEvent() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.confirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(l10n.no)),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.yes, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        setState(() => _isLoading = true);
        await ref.read(eventRepositoryProvider).deleteEvent(widget.eventId!);

        // Clear selected event if it's the one we just deleted
        final selected = ref.read(selectedEventProvider);
        if (selected != null && selected['id'] == widget.eventId) {
          await ref.read(selectedEventProvider.notifier).clearEvent();
        }

        if (mounted) {
          context.pop(); // Close screen
          // Refresh list
          ref.read(eventRepositoryProvider).clearCache();
          ref.invalidate(eventsProvider);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ErrorHandler.showErrorSnackBar(context, l10n.deleteErrorMessage);
        }
      }
    }
  }
}

class _PricingCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? child;

  const _PricingCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.value,
    required this.onChanged,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4, left: 28),
              child: Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            value: value,
            activeThumbColor: color,
            onChanged: onChanged,
          ),
          if (value && child != null) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 8),
              child: child!,
            ),
          ]
        ],
      ),
    );
  }
}
