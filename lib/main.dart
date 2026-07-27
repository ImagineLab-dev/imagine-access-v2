import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/i18n/locale_provider.dart';
import 'core/ui/loading_overlay.dart';
import 'core/ui/offline_sync_banner.dart';
import 'core/utils/error_handler.dart';
import 'core/observability/app_provider_observer.dart';
import 'core/deep_links/deep_link_coordinator.dart';
import 'core/offline/connectivity_provider.dart';
import 'features/auth/presentation/auth_controller.dart';

/// Flavor configuration
enum Flavor { dev, staging, prod }

/// Global flavor variable
Flavor? appFlavor;
bool isProduction = false;

Future<void> main({
  String flavor = 'prod',
  bool production = true,
}) async {
  // Set flavor
  appFlavor = Flavor.values.firstWhere(
    (e) => e.name == flavor,
    orElse: () => Flavor.prod,
  );
  isProduction = production;

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      ErrorHandler.logError(
        'Flutter framework error',
        details.exception,
        stackTrace: details.stack,
        source: 'FlutterError',
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      ErrorHandler.logError(
        'Uncaught platform error',
        error,
        stackTrace: stack,
        source: 'PlatformDispatcher',
      );
      return true;
    };

    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
      );

      // Persist access token on every auth state change so Edge Function calls
      // can use it even after the SDK auto-refresh clears the session.
      const storage = FlutterSecureStorage();
      final client = Supabase.instance.client;
      final currentToken = client.auth.currentSession?.accessToken;
      if (currentToken != null) {
        await storage.write(key: 'last_access_token', value: currentToken);
      }
      client.auth.onAuthStateChange.listen((data) {
        final token = data.session?.accessToken;
        if (token != null) {
          storage.write(key: 'last_access_token', value: token);
        }
      });
    } catch (e, stack) {
      ErrorHandler.logError(
        'Supabase init error',
        e,
        stackTrace: stack,
        source: 'main',
      );
      // Show error to user instead of staying on splash forever
      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error initializing app:\n$e',
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }

    runApp(
      ProviderScope(
        observers: [AppProviderObserver()],
        child: const ImagineAccessApp(),
      ),
    );
  }, (error, stack) {
    ErrorHandler.logError(
      'Uncaught zone error',
      error,
      stackTrace: stack,
      source: 'runZonedGuarded',
    );
  });
}

/// App initialization provider — waits for async state notifiers to finish
/// loading from storage before the router evaluates auth state.
final appInitProvider = FutureProvider<void>((ref) async {
  final deviceNotifier = ref.read(deviceProvider.notifier);
  final orgNotifier = ref.read(userOrganizationProvider.notifier);
  await Future.wait([deviceNotifier.ready, orgNotifier.ready]);
});

class ImagineAccessApp extends ConsumerWidget {
  const ImagineAccessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initState = ref.watch(appInitProvider);

    return initState.when(
      loading: () => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme(),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (err, stack) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Init Error: $err',
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      data: (_) {
        ref.watch(deepLinkCoordinatorProvider);
        ref.watch(offlineAutoSyncProvider);
        final themeMode = ref.watch(themeNotifierProvider);
        final locale = ref.watch(localeProvider);

        return MaterialApp.router(
          title: 'Imagine Access',
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: themeMode,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'), // English
            Locale('es'), // Spanish
            Locale('pt'), // Portuguese
          ],
          routerConfig: ref.watch(routerProvider),
          debugShowCheckedModeBanner: false,
          builder: (context, child) => LoadingOverlay(
            child: Stack(
              children: [
                child!,
                const Align(
                  alignment: Alignment.topCenter,
                  child: OfflineSyncBanner(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
