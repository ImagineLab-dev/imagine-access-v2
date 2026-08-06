import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

import 'package:imagine_access/features/events/presentation/event_state.dart';
import 'package:imagine_access/features/auth/presentation/auth_controller.dart';

class EventDeepLinkScreen extends ConsumerStatefulWidget {
  final String slug;
  const EventDeepLinkScreen({super.key, required this.slug});

  @override
  ConsumerState<EventDeepLinkScreen> createState() =>
      _EventDeepLinkScreenState();
}

class _EventDeepLinkScreenState extends ConsumerState<EventDeepLinkScreen> {
  @override
  void initState() {
    super.initState();
    _resolveEvent();
  }

  Future<void> _resolveEvent() async {
    final l10n = AppLocalizations.of(context);
    try {
      final client = Supabase.instance.client;
      final orgId = ref.read(organizationIdProvider);
      if (orgId == null) {
        if (!mounted) return;
        context.go('/events');
        return;
      }
      final query = client
          .from('events')
          .select('id, name, slug')
          .eq('slug', widget.slug)
          .eq('organization_id', orgId);
      final event = await query.maybeSingle();

      if (!mounted || event == null) {
        if (!mounted) return;
        context.go('/events');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.eventNotFound)),
        );
        return;
      }

      await ref.read(selectedEventProvider.notifier).selectEvent(
        event['id'] as String,
        event['name'] as String,
        event['slug'] as String,
        currency: event['currency']?.toString(),
      );

      if (!mounted) return;
      context.go('/dashboard');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.eventSelectedFromDeepLink)),
      );
    } catch (_) {
      if (!mounted) return;
      context.go('/events');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.couldNotOpenSharedEvent)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
