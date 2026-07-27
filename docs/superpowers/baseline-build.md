# Build de referencia — pre-migración PWA

**Fecha:** 2026-07-27
**Rama:** `pwa-migration`
**Commit base:** `e238cf3` (refactor: reemplazar connectivity_plus por chequeo propio de conectividad)

Este documento captura el resultado real de compilar el proyecto tal como está hoy, para
confirmar cuáles de los hallazgos de `docs/superpowers/specs/2026-07-27-pwa-migration-design.md`
§2 son reales. Esa auditoría se hizo por análisis estático — no había SDK de Flutter
instalado. Este documento es la evidencia de build que faltaba.

## Entorno

```
Flutter 3.44.8 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 058e0af2c2 (4 days ago) • 2026-07-23 10:56:21 -0700
Engine • hash 13ffd72b2f9a5ca4db2a74ea52d5353ec2e8f939 (revision 0cd610717b) (4 days ago) • 2026-07-23 16:11:34.000Z
Tools • Dart 3.12.2 • DevTools 2.57.0
```

Piso del proyecto (`pubspec.yaml`): `sdk: '>=3.11.0 <4.0.0'`. Dart 3.12.2 lo cumple.

`flutter config --enable-web` y `flutter pub get` se ejecutaron sin errores (2 paquetes
transitivos —`meta`, `test_api`— subieron de versión patch; sin cambios de código).

---

## 1. `flutter analyze`

Comando ejecutado:

```
flutter analyze
```

**Resultado: exit code 1 — 5 issues, todos nivel `info` (ninguno `error` ni `warning`).**
`flutter analyze` devuelve exit 1 apenas encuentra cualquier issue, incluso solo-info; no
implica que el proyecto no compile.

```
Analyzing imagine-access-main...

   info - 'dart:html' is deprecated and shouldn't be used. Use package:web and dart:js_interop instead. Try replacing the use of the deprecated member with the replacement - lib\features\dashboard\data\event_report_service_web.dart:2:1 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check. Guard a 'State.context' use with a 'mounted' check on the State, and other BuildContext use with a 'mounted' check on the BuildContext - lib\features\dashboard\presentation\widgets\admin_dashboard_view.dart:246:42 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check. Guard a 'State.context' use with a 'mounted' check on the State, and other BuildContext use with a 'mounted' check on the BuildContext - lib\features\dashboard\presentation\widgets\admin_dashboard_view.dart:247:30 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check. Guard a 'State.context' use with a 'mounted' check on the State, and other BuildContext use with a 'mounted' check on the BuildContext - lib\features\dashboard\presentation\widgets\admin_dashboard_view.dart:253:42 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check. Guard a 'State.context' use with a 'mounted' check on the State, and other BuildContext use with a 'mounted' check on the BuildContext - lib\features\dashboard\presentation\widgets\admin_dashboard_view.dart:254:30 - use_build_context_synchronously

5 issues found. (ran in 54.6s)
```

Nota: `flutter analyze` analiza para la plataforma por defecto, no específicamente para web.
No señala como error el uso de `dart:io` en `connectivity_provider.dart` ni en
`error_handler.dart` (B2, B3) porque `dart:io` es válido para los targets no-web; sólo
`dart:html` aparece, y como `info` de deprecación, no como incompatibilidad de plataforma.

---

## 2. `flutter test`

Comando ejecutado:

```
flutter test
```

**Resultado: exit code 1 — 84 tests pasan, 10 fallan (94 tests individuales en 14 archivos).**
Esto es distinto de lo que asumía el Step 4 del brief ("debería pasar los 14 tests") — esa
cifra cuenta archivos de test (hay exactamente 14, confirmado con
`find test -name "*_test.dart" | wc -l`), no casos de test individuales. Dentro de esos 14
archivos hay 94 `test()`/`testWidgets()`, de los cuales 10 fallan.

Los 10 fallos, verificados como preexistentes (no introducidos por esta tarea — ninguno de
los archivos involucrados tiene cambios sin commitear; el último commit que tocó cada uno
es anterior a esta rama):

| Archivo | Test | Causa observada |
|---|---|---|
| `test/core/utils/currency_helper_test.dart` | `format should format PYG without decimals` | Esperado `'Gs 150000'`, real `'Gs 150.000'` |
| `test/core/utils/currency_helper_test.dart` | `format should format USD with 2 decimals` | Esperado `'$ 99.99'`, real `'$ 99,99'` |
| `test/core/utils/currency_helper_test.dart` | `format should format default currency correctly` | Esperado `'XYZ 1000.00'`, real `'XYZ 1.000,00'` |
| `test/core/utils/currency_helper_test.dart` | `format should handle zero correctly` | Esperado `'$ 0.00'`, real `'$ 0,00'` |
| `test/core/utils/currency_helper_test.dart` | `format should handle negative numbers` | Esperado `'$ -50.00'`, real `'$ -50,00'` |
| `test/features/tickets/ticket_repository_test.dart` | `createTicket calls create_ticket edge function with correct body` | Lanza `Error al crear ticket. Intente nuevamente.` (`ticket_repository.dart:100`) |
| `test/features/tickets/ticket_repository_test.dart` | `createTicket queues operation on retryable network errors` | Mismo error que el anterior |
| `test/features/tickets/ticket_repository_test.dart` | `resendTicket calls resend_ticket_email edge function` | Lanza `Error crítico al reenviar ticket` (`ticket_repository.dart:241`) |
| `test/features/tickets/ticket_repository_test.dart` | `voidTicket calls void_ticket edge function` | Lanza `Error crítico al anular ticket` (`ticket_repository.dart:270`) |
| `test/integration/app_flow_test.dart` | `Welcome shows both access options` | No encuentra el texto `"Admin / RRPP"` en pantalla |

**Diagnóstico de la causa (evidencia, no verificado a fondo — fuera de alcance de esta
tarea):**
- Las 5 fallas de `currency_helper_test.dart` son un desajuste código/test, no un problema
  de entorno: `CurrencyHelper._formatWithThousands()` (`lib/core/utils/currency_helper.dart:31`)
  formatea a mano con punto de miles y coma decimal (estilo latinoamericano) sin usar
  locale del sistema; el test espera formato con coma de miles y punto decimal (estilo US).
  Código y test fueron tocados juntos por última vez en el commit `6c252d9` ("feat: promo
  ticket pack…") — no es una regresión de esta rama.
- Las 4 fallas de `ticket_repository_test.dart` devuelven el mensaje de error genérico del
  `catch` de `TicketRepository`, lo que sugiere que el mock de Supabase del test no cubre
  alguna llamada que el repositorio hace ahora. Último commit que tocó ambos archivos:
  `e22ffda` ("feat: ticket validation fix…").
- La falla de `app_flow_test.dart` espera un texto de UI (`"Admin / RRPP"`) que no aparece
  — probablemente copy/label cambiado sin actualizar el test.

Ninguno de estos 10 fallos está relacionado con `dart:io`/`dart:html` ni con los hallazgos
B1–B4 del spec; son preexistentes en la rama antes de esta tarea.

Salida completa:

```
00:00 +0: loading C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/config/env_test.dart
00:00 +0: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/config/env_test.dart: (setUpAll)
00:00 +0: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/config/env_test.dart: Env supabaseUrl should return a valid URL
00:00 +1: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/config/env_test.dart: Env supabaseAnonKey should return a valid key
00:00 +2: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/config/env_test.dart: (tearDownAll)
00:00 +2: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles Constants admin should be "admin"
00:00 +3: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles Constants rrpp should be "rrpp"
00:00 +4: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles Constants door should be "door"
00:00 +5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles Constants all should contain exactly 3 roles
00:00 +6: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles Constants all should be in correct order
00:00 +7: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles Constants adminLevel should contain only admin
00:00 +8: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.label should return "Admin" for admin role
00:00 +9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.label should return "RRPP" for rrpp role
00:00 +10: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.label should return "Door/Puerta" for door role
00:00 +11: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.label should return uppercase for unknown role
00:00 +12: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.label should return uppercase for empty string
00:00 +13: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.isAdmin should return true for admin
00:00 +14: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.isAdmin should return false for rrpp
00:00 +15: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.isAdmin should return false for door
00:00 +16: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.isAdmin should return false for null
00:00 +17: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.isAdmin should return false for empty string
00:00 +18: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles.isAdmin should return false for ADMIN (case sensitive)
00:00 +19: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles - No Magic Strings Verification constants should match expected Supabase values exactly
00:00 +20: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/constants/app_roles_test.dart: AppRoles - No Magic Strings Verification role values should be lowercase
00:02 +21: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/offline/offline_queue_service_test.dart: OfflineQueueService enqueue persists operations
00:02 +22: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/offline/offline_queue_service_test.dart: OfflineQueueService processQueue removes successful operations
00:02 +23: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/offline/offline_queue_service_test.dart: OfflineQueueService processQueue retries failed operations
00:02 +24: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/theme/app_theme_test.dart: AppTheme darkTheme should return ThemeData with brightness.dark
00:02 +25: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/theme/app_theme_test.dart: AppTheme lightTheme should return ThemeData with brightness.light
00:02 +26: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/theme/app_theme_test.dart: AppTheme darkTheme should use Material3
00:02 +27: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/theme/app_theme_test.dart: AppTheme lightTheme should use Material3
00:02 +28: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/theme/app_theme_test.dart: AppTheme Color constants should be defined
00:02 +29: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/theme/app_theme_test.dart: AppTheme primaryColor should be accentBlue
00:02 +30: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should format PYG without decimals
00:02 +30 -1: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should format PYG without decimals [E]
  Expected: 'Gs 150000'
    Actual: 'Gs 150.000'
     Which: is different.
            Expected: Gs 150000
              Actual: Gs 150.000
                            ^
             Differ at offset 6

  package:matcher                                     expect
  package:flutter_test/src/widget_tester.dart 473:18  expect
  test\core\utils\currency_helper_test.dart 10:9      main.<fn>.<fn>.<fn>

00:02 +30 -1: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should format USD with 2 decimals
00:02 +30 -2: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should format USD with 2 decimals [E]
  Expected: '$ 99.99'
    Actual: '$ 99,99'
     Which: is different.
            Expected: $ 99.99
              Actual: $ 99,99
                          ^
             Differ at offset 4

  package:matcher                                     expect
  package:flutter_test/src/widget_tester.dart 473:18  expect
  test\core\utils\currency_helper_test.dart 15:9      main.<fn>.<fn>.<fn>

00:02 +30 -2: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should format default currency correctly
00:02 +30 -3: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should format default currency correctly [E]
  Expected: 'XYZ 1000.00'
    Actual: 'XYZ 1.000,00'
     Which: is different.
            Expected: XYZ 1000.00
              Actual: XYZ 1.000,00
                           ^
             Differ at offset 5

  package:matcher                                     expect
  package:flutter_test/src/widget_tester.dart 473:18  expect
  test\core\utils\currency_helper_test.dart 20:9      main.<fn>.<fn>.<fn>

00:02 +30 -3: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should handle zero correctly
00:02 +30 -4: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should handle zero correctly [E]
  Expected: '$ 0.00'
    Actual: '$ 0,00'
     Which: is different.
            Expected: $ 0.00
              Actual: $ 0,00
                         ^
             Differ at offset 3

  package:matcher                                     expect
  package:flutter_test/src/widget_tester.dart 473:18  expect
  test\core\utils\currency_helper_test.dart 25:9      main.<fn>.<fn>.<fn>

00:02 +30 -4: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should handle negative numbers
00:02 +30 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should handle negative numbers [E]
  Expected: '$ -50.00'
    Actual: '$ -50,00'
     Which: is different.
            Expected: $ -50.00
              Actual: $ -50,00
                           ^
             Differ at offset 5

  package:matcher                                     expect
  package:flutter_test/src/widget_tester.dart 473:18  expect
  test\core\utils\currency_helper_test.dart 30:9      main.<fn>.<fn>.<fn>

00:02 +30 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper getIcon should return attach_money for USD
00:02 +31 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper getIcon should return payments_outlined for PYG
00:02 +32 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper getIcon should return money for unknown currency
00:02 +33 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper getSymbol should return $ for USD
00:02 +34 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper getSymbol should return Gs for PYG
00:02 +35 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper getSymbol should return currency code for unknown currency
00:02 +36 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper getSymbol should handle uppercase conversion
00:02 +37 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/error_handler_test.dart: ErrorHandler.analyzeError classifies socket exceptions as noConnection
00:02 +38 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/error_handler_test.dart: ErrorHandler.analyzeError classifies unauthorized errors
00:02 +39 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/error_handler_test.dart: ErrorHandler.analyzeError classifies server errors as retryable
00:02 +40 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/error_handler_test.dart: ErrorHandler.analyzeError classifies unknown errors safely
00:03 +41 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/ttl_cache_test.dart: TtlCacheEntry isValidAt returns true inside ttl
00:03 +42 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/ttl_cache_test.dart: TtlCacheEntry isValidAt returns false after ttl expires
00:03 +43 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/ttl_cache_test.dart: InMemoryTtlCacheStore stores and retrieves value
00:03 +44 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/ttl_cache_test.dart: InMemoryTtlCacheStore invalidate removes key
00:03 +45 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/ttl_cache_test.dart: InMemoryTtlCacheStore clear removes all keys
00:03 +46 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/dashboard/dashboard_repository_test.dart: DashboardRepository getMetrics returns empty map when eventId is null
00:03 +47 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/dashboard/dashboard_repository_test.dart: DashboardRepository getMetrics calls correct RPC function with correct params
00:03 +48 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/dashboard/dashboard_repository_test.dart: DashboardRepository getRecentActivity returns empty list when eventId is null
00:03 +49 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/dashboard/dashboard_repository_test.dart: DashboardRepository getStats returns empty map when eventId is null
00:03 +50 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/dashboard/dashboard_repository_test.dart: DashboardRepository getStats calls correct RPC function with correct params
00:03 +51 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/dashboard/dashboard_repository_test.dart: DashboardRepository Null Guard Security ALL methods return empty when eventId is null
00:03 +52 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository getEvents returns empty list when organizationId is null
00:03 +53 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository getEvents returns empty list when organizationId is not provided
00:03 +54 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository createEvent includes organization_id when provided
00:03 +55 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns cached events when cache is valid
00:03 +56 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +57 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +58 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +59 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +60 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +61 -5: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +61 -6: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +61 -6: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/tickets/ticket_repository_test.dart: TicketRepository createTicket calls create_ticket edge function with correct body [E]
  Error al crear ticket. Intente nuevamente.
  package:imagine_access/features/tickets/data/ticket_repository.dart 100:7  TicketRepository.createTicket
  test\features\tickets\ticket_repository_test.dart 62:41                    main.<fn>.<fn>.<fn>

00:04 +62 -6: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +62 -7: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +62 -7: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/tickets/ticket_repository_test.dart: TicketRepository createTicket queues operation on retryable network errors [E]
  Error al crear ticket. Intente nuevamente.
  package:imagine_access/features/tickets/data/ticket_repository.dart 100:7  TicketRepository.createTicket
  test\features\tickets\ticket_repository_test.dart 110:41                   main.<fn>.<fn>.<fn>

00:04 +63 -7: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +63 -8: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +63 -8: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/tickets/ticket_repository_test.dart: TicketRepository resendTicket calls resend_ticket_email edge function [E]
  Error crítico al reenviar ticket
  package:imagine_access/features/tickets/data/ticket_repository.dart 241:7  TicketRepository.resendTicket
  test\features\tickets\ticket_repository_test.dart 155:26                   main.<fn>.<fn>.<fn>

00:04 +64 -8: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +64 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +64 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/tickets/ticket_repository_test.dart: TicketRepository voidTicket calls void_ticket edge function [E]
  Error crítico al anular ticket
  package:imagine_access/features/tickets/data/ticket_repository.dart 270:7  TicketRepository.voidTicket
  test\features\tickets\ticket_repository_test.dart 189:26                   main.<fn>.<fn>.<fn>

00:04 +65 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:04 +66 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/features/events/event_repository_test.dart: EventRepository cache behavior returns stale cache when remote fetch fails
00:09 +67 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: (setUpAll)
00:09 +68 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: (setUpAll)
00:09 +69 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: (setUpAll)
00:09 +70 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: (setUpAll)
00:09 +71 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: (setUpAll)
00:09 +72 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: (setUpAll)
00:09 +73 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: (setUpAll)
00:09 +74 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: (setUpAll)
00:09 +75 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: (setUpAll)
00:09 +76 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: (setUpAll)
supabase.supabase_flutter: INFO: ***** Supabase init completed *****
00:09 +77 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: App Integration Tests App launches successfully
00:09 +78 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: App Integration Tests App launches successfully
00:09 +79 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: App Integration Tests App launches successfully
00:09 +80 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: App Integration Tests App launches successfully
00:09 +81 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/widget_test.dart: Material widgets render
00:10 +82 -9: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: App Integration Tests Welcome shows both access options
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following TestFailure was thrown running a test:
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Admin / RRPP": []>
   Which: means none were found but one was expected

When the exception was thrown, this was the stack:
#4      main.<anonymous closure>.<anonymous closure> (file:///C:/Users/mendi/Desktop/PERSONAL%20PROYECTS/imagine-access-main/test/integration/app_flow_test.dart:36:7)
<asynchronous suspension>
#5      testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:15)
<asynchronous suspension>
#6      TestWidgetsFlutterBinding._runTestBody (package:flutter_test/src/binding.dart:1952:5)
<asynchronous suspension>
<asynchronous suspension>
(elided one frame from package:stack_trace)

This was caught by the test expectation on the following line:
  file:///C:/Users/mendi/Desktop/PERSONAL%20PROYECTS/imagine-access-main/test/integration/app_flow_test.dart line 36
The test description was:
  Welcome shows both access options
════════════════════════════════════════════════════════════════════════════════════════════════════
00:10 +82 -10: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/widget_test.dart: Basic layout widgets work
00:10 +82 -10: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/integration/app_flow_test.dart: App Integration Tests Welcome shows both access options [E]
  Test failed. See exception logs above.
  The test description was: Welcome shows both access options

00:10 +83 -10: C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/widget_test.dart: Basic layout widgets work
00:10 +84 -10: Some tests failed.

Failing tests:
  C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should format PYG without decimals
  C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should format USD with 2 decimals
  C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should format default currency correctly
  C:/Users/mendi/Desktop/PERSONAL PROYECTS/imagine-access-main/test/core/utils/currency_helper_test.dart: CurrencyHelper format should handle negative numbers
  ... and 6 more
```

---

## 3. `flutter build web`

Comando ejecutado:

```
flutter build web --dart-define=SUPABASE_URL=https://placeholder.supabase.co --dart-define=SUPABASE_ANON_KEY=placeholder_key_at_least_20_chars
```

**Resultado: exit code 0 — el build COMPILA Y TERMINA CON ÉXITO.** Esto contradice
directamente la expectativa del Step 4 del brief ("`flutter build web` debe fallar…
bloqueantes B2, B3 y B4"). `build/web/` se generó completo y funcional
(`main.dart.js` de 5.128.569 bytes, `flutter_service_worker.js`, `manifest.json`,
`assets/`, `canvaskit/`, etc.).

```
Compiling lib\main.dart for the Web...
Warning: In index.html:37: Flutter's service worker is deprecated and will be removed in a future Flutter release. See https://github.com/flutter/flutter/issues/156910 for more details.
Warning: In index.html:46: "FlutterLoader.loadEntrypoint" is deprecated. Use "FlutterLoader.load" instead. See https://docs.flutter.dev/platform-integration/web/initialization for more details.
Wasm dry run findings:
Found incompatibilities with WebAssembly.

package:web_socket_channel/html.dart 6:1 - dart:html unsupported (0)
file:///C:/Users/mendi/AppData/Local/Pub/Cache/hosted/pub.dev/image-4.5.4/lib/src/exif/ifd_directory.dart 174:26 - avoid_double_and_int_checks lint violation: Explicit check for double or int. (13)
file:///C:/Users/mendi/AppData/Local/Pub/Cache/hosted/pub.dev/image-4.5.4/lib/src/exif/ifd_directory.dart 183:26 - avoid_double_and_int_checks lint violation: Explicit check for double or int. (13)

Consider addressing these issues to enable wasm builds. See docs for more info: https://docs.flutter.dev/platform-integration/web/wasm

Use --no-wasm-dry-run to disable these warnings.
Font asset "CupertinoIcons.ttf" was tree-shaken, reducing it from 257628 to 1472 bytes (99.4% reduction). Tree-shaking can be disabled by providing the --no-tree-shake-icons flag when building your app.
Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 19568 bytes (98.8% reduction). Tree-shaking can be disabled by providing the --no-tree-shake-icons flag when building your app.
Compiling lib\main.dart for the Web...                             78,5s
√ Built build\web
```

**Por qué el build no falla pese a B2/B3/B4:** `flutter build web` sin flags compila al
target JS (dartdevc/dart2js), no a WASM. `dart:io` y `dart:html` siguen soportados —
aunque deprecados — en ese target; el propio comando lo confirma con el "Wasm dry run"
(que es sólo informativo y se ejecuta siempre, no bloquea nada): señala `dart:html`
como incompatible únicamente **para WASM**, no para el build JS que de hecho se generó.
No se verificó en esta tarea si el bundle generado corre correctamente en un navegador real
(pantalla en blanco de B1, crash en runtime de `InternetAddress.lookup` de B2 cada 5s,
etc.) — eso requiere servir `build/web/` y abrirlo en un navegador, fuera del alcance de
los tres comandos de esta tarea.

---

## 4. Confrontación con el spec §2

Por instrucción explícita de la tarea, los hallazgos C3, C4, C5, C6, M2 y M3 no son
observables desde build/analyze/test y no se fuerzan a un veredicto; se listan al final
sin evaluar.

| # | Hallazgo | Veredicto | Evidencia / explicación |
|---|---|---|---|
| B1 | Loader eliminado en Flutter 3.27+, pantalla en blanco | **DISTINTO A LO ESPERADO** | `_flutter.loader.loadEntrypoint()` (`web/index.html:46`) sigue existiendo y funcionando en Flutter 3.44.8 — no fue eliminado, sólo está deprecado (warning literal del build en esa misma línea). El build no falla. La consecuencia "pantalla en blanco" no se verificó (requiere abrir el bundle en un navegador; fuera de alcance de esta tarea). |
| B2 | `dart:io` (`InternetAddress.lookup` cada 5s) en `connectivity_provider.dart:3` | **DISTINTO A LO ESPERADO** | El import y el uso están confirmados exactamente en esa línea. Pero `flutter build web` compila con éxito pese a esto — `dart:io` no bloquea el target JS por defecto. El riesgo pasa a ser de runtime (posible `UnsupportedError` cada 5s en el navegador real), no verificado en esta tarea. |
| B3 | `dart:io` (`SocketException`/`HttpException`) en `error_handler.dart:2,52,66` | **DISTINTO A LO ESPERADO** | Mismo patrón que B2: confirmado en código exactamente en esas líneas, no bloquea el build. Los 4 tests de `error_handler_test.dart` pasan porque `flutter test` corre en la VM de Dart (no en el target web), donde `dart:io` funciona normalmente — esto no prueba nada sobre el comportamiento en navegador. |
| B4 | `dart:html` / import condicional `dart.library.html` | **DISTINTO A LO ESPERADO** | Confirmado exactamente: `event_report_service_web.dart:2` y el import condicional en `event_report_service.dart:13`. `flutter analyze` lo marca como `info` (deprecated_member_use), y el "Wasm dry run" del build lo marca como incompatible con WASM — pero el build JS por defecto compila sin error. |
| C1 | ZXing desde `unpkg.com` en runtime | **CONFIRMADO** | `mobile_scanner-7.2.0/lib/src/web/zxing/zxing_barcode_reader.dart`: `String get scriptUrl => 'https://unpkg.com/@zxing/library@0.21.3';` — coincide exactamente. |
| C2 | `printing` carga pdf.js desde unpkg; dependencia muerta | **CONFIRMADO** | `printing-5.14.3/lib/printing_web.dart`: `_pdfJsCdnPath = 'https://unpkg.com/pdfjs-dist'`. `printPreview()` (`event_report_service.dart:400`) no tiene ningún llamador en `lib/` — confirmado con grep, dependencia efectivamente muerta. |
| M1 | `.env` como asset servido en `/assets/.env` | **CONFIRMADO** | `pubspec.yaml:75-77` declara `.env`, `.env.dev`, `.env.staging` como assets; tras el build aparecen en `build/web/assets/.env` (y `.dev`/`.staging`). El `.env` local sólo contiene `SUPABASE_URL` y `SUPABASE_ANON_KEY`, como dice el hallazgo. |
| M4 | `flutter_native_splash` con `web: false` → pantalla blanca durante carga | **CONFIRMADO** (config); consecuencia visual no verificada en navegador | `pubspec.yaml:126` tiene `web: false` literal. `web/index.html` no tiene ningún markup de splash en `<body>` — sólo el script de carga — consistente con que no hay nada que mostrar hasta que cargue `main.dart.js`. |
| M5 | 7 `HapticFeedback` no-op + linterna muerta (`hasTorch: false` fijo) | **DISTINTO A LO ESPERADO** (menor) | `hasTorch()` en `mobile_scanner-7.2.0/lib/src/web/barcode_reader.dart:69-72` retorna `Future<bool>.value(false)` fijo — confirmado igual que el hallazgo. El botón de linterna existe en `scanner_screen.dart` (~línea 230). Pero el conteo de `HapticFeedback` en `scanner_screen.dart` da **6**, no 7 (8 en total contando `neon_button.dart` y `login_screen.dart`, que no son el escáner). |
| M6 | Sin ignorar: `build_old/`, `ios/build/`, logs, `UsersHp.git-credentials-imagine` | **DISTINTO A LO ESPERADO** (parcial) | `build_old/`, `ios/build/`, `ios/build_temp_old/` siguen sin trackear y sin ignorar (confirmado, aparecen como `??` en `git status`). Pero `*.log` y `*.git-credentials*` **ya están** en `.gitignore` (líneas 3 y 72) — contradice el "sin ignorar" del hallazgo para esa parte, aunque los archivos concretos (`flutter_01.log`, `flutter_02.log`, `UsersHp.git-credentials-imagine`) siguen físicamente presentes y sin trackear en el repo. |

### No observables desde build (no se fuerza veredicto)

C3 (manejo de actualización del service worker), C4 (cola offline en `localStorage`), C5
(clave de cifrado de `flutter_secure_storage_web` en el mismo `localStorage`), C6 (CORS de
Edge Functions con un solo `ALLOWED_ORIGIN`), M2 (`manifest.json`/iconos scaffold), M3
(deep links sin fallback SPA) — ninguno es observable desde `flutter analyze`/`test`/`build
web`; requieren runtime en navegador o inspección de infraestructura de Supabase/Hostinger,
fuera del alcance de esta tarea.

---

## 5. Hallazgos que no se reprodujeron / requieren replanteo

1. **`flutter build web` no falla.** El Step 4 del brief asumía que fallaría por B2, B3 y
   B4. Compiló con éxito (exit 0) produciendo un `build/web/` completo. Los cuatro
   bloqueantes (B1-B4) existen tal como los describe el spec a nivel de código, pero
   ninguno bloquea la compilación por defecto (target JS). Esto puede reducir el alcance de
   la Etapa 1 del plan (§11): "desbloquear build" ya está hecho hoy; lo que falta verificar
   es si la app **arranca y funciona** en un navegador real, no si compila.
2. **`flutter test` no pasa limpio.** 10 de 94 tests individuales fallan (84 pasan), todos
   preexistentes y sin relación con `dart:io`/`dart:html` (ver tabla de la sección 2). El
   Step 4 del brief decía "debería pasar los 14 tests", cifra que en realidad cuenta
   archivos de test, no casos individuales.
3. **M6 parcialmente resuelto.** `.gitignore` ya tiene `*.log` y `*.git-credentials*`; sólo
   falta agregar `build_old/` (y las carpetas nativas `ios/build/`, `ios/build_temp_old/`,
   que de todos modos se eliminan en la Etapa de purga de nativo, §3.1).
4. **M5 con conteo menor:** 6 `HapticFeedback` en `scanner_screen.dart`, no 7 (8 contando
   toda la app). No cambia la naturaleza del hallazgo, sólo el número exacto.
