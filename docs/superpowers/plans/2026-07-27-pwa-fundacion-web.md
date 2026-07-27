# Imagine Access PWA — Plan 1: Fundación web

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dejar el proyecto compilando y corriendo como app web, con el escáner de QR
funcionando sin CDN externo, y medir su rendimiento real en iPhone y Android para decidir
si la migración completa a PWA es viable.

**Architecture:** Se eliminan los cuatro bloqueantes de compilación web (`dart:io`,
`dart:html`, loader obsoleto) introduciendo una capa `lib/core/platform/` cuyas piezas
dependientes del navegador quedan detrás de interfaces chicas, de modo que la lógica se
pueda testear en la VM de Dart sin Chrome. Se purgan los cinco targets nativos y las
dependencias que ya no aplican. Finalmente se self-hostea ZXing para que el escáner
funcione offline, y se instrumenta para medir latencia en dispositivos reales.

**Tech Stack:** Flutter (web), Dart, Riverpod, go_router, Supabase, `package:web` +
`dart:js_interop`, `mobile_scanner`, ZXing-js.

## Global Constraints

- **Rama de trabajo:** `pwa-migration`. Ya existe y tiene los dos commits del spec.
- **Flutter stable con Dart >= 3.11.0 < 4.0.0** — lo exige `pubspec.yaml:12`. Equivale a
  Flutter 3.38 o superior.
- **Target único: web.** No se agrega código con `kIsWeb`, imports condicionales ni
  `dart:io`. Si algo necesita una rama por plataforma, es señal de que está mal planteado.
- **Cero dependencias de CDN en runtime.** Todo activo de terceros se sirve desde el
  propio origen. La CSP de producción será `default-src 'self'` (spec §8.1).
- **Configuración por `--dart-define`,** nunca por archivo `.env` empaquetado como asset.
- **Color de marca:** `#0B0F16`. Nunca el `#0175C2` del scaffold de Flutter.
- **Locales soportados:** `en`, `es`, `pt`. Todo texto visible pasa por `AppLocalizations`.
- **`flutter test` no debe sumar fallos nuevos.** Medido en la Tarea 1 sobre árbol limpio:
  **84 de 94 tests pasan; 10 ya fallan** (5 en `currency_helper_test.dart`, 4 en
  `ticket_repository_test.dart`, 1 en `event_repository_test.dart`). Son preexistentes y
  ajenos a esta migración; arreglarlos no es parte de este plan. La regla es que ninguna
  tarea aumente ese número. Las Tareas 4 y 6 reescriben `error_handler_test.dart` y
  `env_test.dart` a propósito —cambia lo que esos módulos deben hacer— y la Tarea 3 suma
  tests nuevos. Cualquier otro test que se rompa es una regresión.
- **Commits:** prefijo convencional en inglés (`feat:`, `fix:`, `chore:`, `docs:`,
  `refactor:`, `test:`), descripción en español. Un commit por tarea.
- **Contrato público que no se rompe:** `connectivityStatusProvider`
  (`StreamProvider<AppConnectivity>`) y el enum `AppConnectivity` siguen exportándose desde
  `lib/core/offline/connectivity_provider.dart`. Los consumen `lib/main.dart:187` y
  `lib/core/ui/offline_sync_banner.dart:45`.

---

## Estructura de archivos

**Se crean:**

| Archivo | Responsabilidad |
|---|---|
| `lib/core/platform/connectivity_signals.dart` | Interfaz de las señales del navegador (`navigator.onLine`, eventos, sonda). Sin dependencias de `package:web`, para poder testear en VM. |
| `lib/core/platform/browser_connectivity_signals.dart` | Implementación real sobre `package:web`. |
| `lib/core/platform/connectivity_service.dart` | Lógica de decisión online/offline y el enum `AppConnectivity`. Testeable en VM. |
| `lib/core/platform/file_download.dart` | Descarga de bytes en el navegador vía `package:web`. |
| `test/core/platform/connectivity_service_test.dart` | Tests de la lógica de conectividad con un doble. |
| `web/js/zxing-0.21.3.min.js` | ZXing self-hosteado. |
| `docs/superpowers/spike-escaner-resultados.md` | Resultados medidos del spike (Tarea 10). |

**Se modifican:**

| Archivo | Cambio |
|---|---|
| `web/index.html` | Loader moderno (B1) |
| `lib/core/offline/connectivity_provider.dart` | Delega en la capa nueva; pierde `dart:io` (B2) |
| `lib/core/utils/error_handler.dart` | Clasificación por string; pierde `dart:io` (B3) |
| `test/core/utils/error_handler_test.dart` | Pierde `dart:io`; cubre errores de fetch del navegador |
| `lib/features/dashboard/data/event_report_service.dart` | Sin import condicional, sin `kIsWeb`, sin `printing` (B4, C2) |
| `lib/core/config/env.dart` | Solo `String.fromEnvironment` (M1) |
| `lib/main.dart` | Sin `dotenv` (M1) |
| `test/core/config/env_test.dart` | Ajustado a la nueva `Env` |
| `pubspec.yaml` | Dependencias y assets |
| `.gitignore` | Entradas faltantes (M6) |
| `lib/features/scanner/presentation/scanner_screen.dart` | Sin linterna (M5); instrumentación de latencia |

**Se borran:**

`lib/features/dashboard/data/event_report_service_stub.dart`,
`lib/features/dashboard/data/event_report_service_web.dart`,
`android/`, `ios/`, `macos/`, `windows/`, `linux/`,
`deploy_app.ps1`, `deploy_ios.sh`, `generate_keystore.ps1`,
`build_old/`, `flutter_01.log`, `flutter_02.log`,
`UsersHp.git-credentials-imagine`,
`.env`, `.env.dev`, `.env.staging`.

---

## Desvíos respecto del spec

Dos, ambos simplifican el trabajo. Se aplican en este plan y hay que reflejarlos en el spec:

1. **`printing` se elimina en vez de self-hostear pdf.js (spec §7.2, C2).** Solo la usa
   `EventReportService.printPreview()` (`event_report_service.dart:400`), método que no
   invoca nadie — el único consumidor del servicio es `exportAndShare`, desde
   `admin_dashboard_view.dart:240`. El PDF usa las fuentes Helvetica por defecto de
   `package:pdf`, no `PdfGoogleFonts`. Borrar el método y la dependencia elimina C2 sin
   self-hostear nada.
2. **`flutter_secure_storage` y `app_links` se conservan en este plan** (el spec §3.2 los
   da de baja). Ambos compilan en web y darlos de baja exige reescribir la autenticación
   de dispositivos, que es la etapa 3. Se van en el Plan 2.
3. **El módulo `feedback.dart` del spec §3.3 queda para el Plan 2.** Las 7 llamadas a
   `HapticFeedback` del escáner son no-op en la mayoría de navegadores, pero no bloquean
   el spike: la app ya da retroalimentación visual fuerte con `_ResultOverlay`, que ocupa
   la pantalla completa en verde o rojo (`scanner_screen.dart:200-202`). Se mide la
   latencia de detección, que es lo que decide la viabilidad; el pulido del feedback viene
   después.

---

### Task 1: Instalar Flutter y capturar el build de referencia

Confirma cuáles de los hallazgos de la auditoría son reales. La auditoría se hizo por
análisis estático porque no había SDK en la máquina; esta tarea produce la evidencia.

**Files:**
- Create: `docs/superpowers/baseline-build.md`

**Interfaces:**
- Consumes: nada.
- Produces: el archivo `docs/superpowers/baseline-build.md` con la salida real de
  `flutter analyze`, `flutter test` y `flutter build web`. Las tareas 2 a 7 se validan
  contra esos errores.

- [ ] **Step 1: Instalar el SDK de Flutter**

Si `flutter --version` ya responde, saltear al Step 2.

```powershell
git clone https://github.com/flutter/flutter.git -b stable "$env:USERPROFILE\flutter"
$env:Path = "$env:USERPROFILE\flutter\bin;$env:Path"
flutter --version
```

Para que persista entre sesiones, agregar `%USERPROFILE%\flutter\bin` al PATH del usuario
en Variables de Entorno de Windows.

- [ ] **Step 2: Verificar que la versión cumple el piso del proyecto**

Run: `flutter --version`
Expected: Dart en 3.11.0 o superior. Si es menor, `flutter upgrade`. Con Dart < 3.11 el
proyecto no resuelve dependencias y el resto del plan no aplica.

- [ ] **Step 3: Habilitar web y resolver dependencias**

```powershell
flutter config --enable-web
flutter pub get
```

- [ ] **Step 4: Capturar el estado de referencia**

Ejecutar los tres comandos y guardar la salida completa de cada uno:

```powershell
flutter analyze                          > analyze.txt 2>&1
flutter test                             > test.txt 2>&1
flutter build web --dart-define=SUPABASE_URL=https://placeholder.supabase.co --dart-define=SUPABASE_ANON_KEY=placeholder_key_at_least_20_chars > build.txt 2>&1
```

Expected: `flutter build web` **falla**. Los errores esperados son los bloqueantes B2, B3 y
B4 del spec — `dart:io` no disponible en `connectivity_provider.dart` y `error_handler.dart`,
`dart:html` en `event_report_service_web.dart`. `flutter test` debería pasar los 14 tests.

- [ ] **Step 5: Escribir el documento de referencia**

Crear `docs/superpowers/baseline-build.md` con: versión de Flutter y Dart, el resultado de
cada comando, y una tabla que confronte cada hallazgo del spec §2 con lo observado —
`CONFIRMADO`, `NO SE REPRODUCE`, o `DISTINTO A LO ESPERADO` con la explicación.

Cualquier hallazgo que salga `NO SE REPRODUCE` se reporta al usuario antes de seguir; su
tarea correspondiente puede sobrar.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/baseline-build.md
git commit -m "docs: build de referencia previo a la migración web"
```

---

### Task 2: Loader moderno en index.html

Resuelve B1. `_flutter.loader.loadEntrypoint()` fue eliminado en Flutter 3.27+; con el SDK
actual la app queda en pantalla en blanco. El reemplazo es `flutter_bootstrap.js`, que
Flutter genera durante el build y que además cablea el service worker solo.

**Files:**
- Modify: `web/index.html` (reemplazo completo)

**Interfaces:**
- Consumes: nada.
- Produces: `web/index.html` sin JS de arranque propio. La Tarea 8 le agrega una etiqueta
  `<script>` en el `<head>`.

- [ ] **Step 1: Reemplazar el contenido completo de `web/index.html`**

```html
<!DOCTYPE html>
<html lang="es">
<head>
  <base href="$FLUTTER_BASE_HREF">

  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <meta name="description" content="Imagine Access — Control de acceso a eventos y gestión de tickets.">
  <meta name="theme-color" content="#0B0F16">

  <!-- iOS: instalación en pantalla de inicio -->
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="Imagine Access">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">

  <link rel="icon" type="image/png" href="favicon.png"/>
  <link rel="manifest" href="manifest.json">

  <title>Imagine Access</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
```

El `maximum-scale=1.0, user-scalable=no` evita el zoom accidental al escanear con el
teléfono en la mano. `viewport-fit=cover` hace que la app use el área completa en iPhone
con notch.

- [ ] **Step 2: Verificar que el build genera el bootstrap**

Run: `flutter build web --dart-define=SUPABASE_URL=https://placeholder.supabase.co --dart-define=SUPABASE_ANON_KEY=placeholder_key_at_least_20_chars`
Expected: sigue fallando por B2/B3/B4 (se arreglan en las tareas 3 a 5), **pero** el error
ya no menciona `loadEntrypoint`. Si el build llegara a completar, confirmar que existe
`build/web/flutter_bootstrap.js`.

- [ ] **Step 3: Commit**

```bash
git add web/index.html
git commit -m "fix: migrar index.html al loader flutter_bootstrap.js"
```

---

### Task 3: Capa de conectividad web

Resuelve B2. `InternetAddress.lookup('google.com')` no existe en web, y hacerle un lookup a
Google cada 5 segundos tampoco es lo que queremos: la señal que importa es si **nuestro
backend** responde.

El diseño separa las señales del navegador (no testeables en VM) de la lógica de decisión
(sí testeable), para no depender de `flutter test --platform chrome`.

**Files:**
- Create: `lib/core/platform/connectivity_signals.dart`
- Create: `lib/core/platform/connectivity_service.dart`
- Create: `lib/core/platform/browser_connectivity_signals.dart`
- Create: `test/core/platform/connectivity_service_test.dart`
- Modify: `lib/core/offline/connectivity_provider.dart`

**Interfaces:**
- Consumes: `Env.supabaseUrl` de `lib/core/config/env.dart`.
- Produces:
  - `enum AppConnectivity { online, offline }` en `connectivity_service.dart`,
    reexportado por `connectivity_provider.dart` para no romper a sus consumidores.
  - `abstract class ConnectivitySignals` con `bool get isOnline`,
    `Stream<void> get onOnline`, `Stream<void> get onOffline`, `Future<bool> probe()`.
  - `class ConnectivityService` con constructor
    `ConnectivityService(ConnectivitySignals signals, {Duration probeInterval})` y
    `Stream<AppConnectivity> watch()`.
  - `class BrowserConnectivitySignals` con constructor
    `BrowserConnectivitySignals({required String probeUrl, Duration probeTimeout})`.
  - `connectivityStatusProvider` sigue siendo `StreamProvider<AppConnectivity>`.

- [ ] **Step 1: Escribir la interfaz de señales**

Crear `lib/core/platform/connectivity_signals.dart`:

```dart
/// Señales crudas del navegador de las que se deriva el estado de conectividad.
///
/// Se extrae detrás de una interfaz para que [ConnectivityService] —donde vive
/// la lógica— pueda testearse en la VM de Dart, donde `package:web` no existe.
abstract class ConnectivitySignals {
  /// Espejo de `navigator.onLine`.
  ///
  /// Es una condición necesaria pero no suficiente: da `true` cuando el equipo
  /// está conectado a un portal cautivo o a un router sin salida a internet.
  bool get isOnline;

  /// Emite cuando el navegador dispara el evento `online`.
  Stream<void> get onOnline;

  /// Emite cuando el navegador dispara el evento `offline`.
  Stream<void> get onOffline;

  /// Comprueba si el backend responde de verdad.
  ///
  /// Devuelve `true` si contestó (cualquier respuesta HTTP cuenta como
  /// alcanzable) y `false` ante cualquier fallo o timeout.
  Future<bool> probe();
}
```

- [ ] **Step 2: Escribir los tests de la lógica**

Crear `test/core/platform/connectivity_service_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/platform/connectivity_service.dart';
import 'package:imagine_access/core/platform/connectivity_signals.dart';

class FakeSignals implements ConnectivitySignals {
  bool online = true;
  bool probeSucceeds = true;
  int probeCalls = 0;

  final _online = StreamController<void>.broadcast();
  final _offline = StreamController<void>.broadcast();

  @override
  bool get isOnline => online;

  @override
  Stream<void> get onOnline => _online.stream;

  @override
  Stream<void> get onOffline => _offline.stream;

  @override
  Future<bool> probe() async {
    probeCalls++;
    return probeSucceeds;
  }

  void emitOnline() {
    online = true;
    _online.add(null);
  }

  void emitOffline() {
    online = false;
    _offline.add(null);
  }

  Future<void> dispose() async {
    await _online.close();
    await _offline.close();
  }
}

void main() {
  late FakeSignals signals;
  late ConnectivityService service;

  setUp(() {
    signals = FakeSignals();
    service = ConnectivityService(
      signals,
      probeInterval: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    await signals.dispose();
  });

  test('reporta online cuando el navegador está online y el backend responde',
      () async {
    signals.online = true;
    signals.probeSucceeds = true;

    await expectLater(
      service.watch(),
      emitsInOrder(<AppConnectivity>[AppConnectivity.online]),
    );
  });

  test('reporta offline sin sondear cuando navigator.onLine es false', () async {
    signals.online = false;

    final first = await service.watch().first;

    expect(first, AppConnectivity.offline);
    expect(signals.probeCalls, 0,
        reason: 'sondear con el navegador offline es tráfico desperdiciado');
  });

  test('reporta offline ante portal cautivo: navegador online, backend no responde',
      () async {
    signals.online = true;
    signals.probeSucceeds = false;

    final first = await service.watch().first;

    expect(first, AppConnectivity.offline);
    expect(signals.probeCalls, greaterThan(0));
  });

  test('no repite el mismo estado dos veces seguidas', () async {
    signals.online = true;
    signals.probeSucceeds = true;

    final seen = <AppConnectivity>[];
    final sub = service.watch().listen(seen.add);

    await Future<void>.delayed(const Duration(milliseconds: 180));
    await sub.cancel();

    expect(seen, <AppConnectivity>[AppConnectivity.online],
        reason: 'varias sondas exitosas seguidas son un solo evento online');
  });

  test('reevalúa al recibir el evento online del navegador', () async {
    signals.online = false;

    final seen = <AppConnectivity>[];
    final sub = service.watch().listen(seen.add);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    signals.probeSucceeds = true;
    signals.emitOnline();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();

    expect(seen, <AppConnectivity>[
      AppConnectivity.offline,
      AppConnectivity.online,
    ]);
  });
}
```

- [ ] **Step 3: Correr los tests y verificar que fallan**

Run: `flutter test test/core/platform/connectivity_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:imagine_access/core/platform/connectivity_service.dart'`

- [ ] **Step 4: Implementar el servicio**

Crear `lib/core/platform/connectivity_service.dart`:

```dart
import 'dart:async';

import 'connectivity_signals.dart';

/// Estado de conectividad tal como lo consume la app.
enum AppConnectivity { online, offline }

/// Deriva [AppConnectivity] a partir de las [ConnectivitySignals] del navegador.
///
/// `navigator.onLine` en `false` es concluyente: no hay red y no vale la pena
/// gastar una sonda. En `true` no lo es —un portal cautivo también da `true`—
/// así que se confirma con una sonda al backend.
class ConnectivityService {
  ConnectivityService(
    this._signals, {
    this.probeInterval = const Duration(seconds: 30),
  });

  final ConnectivitySignals _signals;
  final Duration probeInterval;

  Stream<AppConnectivity> watch() {
    late final StreamController<AppConnectivity> controller;
    final subscriptions = <StreamSubscription<void>>[];
    Timer? timer;
    AppConnectivity? last;
    var evaluating = false;

    Future<void> evaluate() async {
      if (evaluating || controller.isClosed) return;
      evaluating = true;
      try {
        final AppConnectivity status;
        if (!_signals.isOnline) {
          status = AppConnectivity.offline;
        } else {
          status = await _signals.probe()
              ? AppConnectivity.online
              : AppConnectivity.offline;
        }
        if (status != last && !controller.isClosed) {
          last = status;
          controller.add(status);
        }
      } finally {
        evaluating = false;
      }
    }

    controller = StreamController<AppConnectivity>(
      onListen: () {
        subscriptions.add(_signals.onOnline.listen((_) => evaluate()));
        subscriptions.add(_signals.onOffline.listen((_) => evaluate()));
        timer = Timer.periodic(probeInterval, (_) => evaluate());
        unawaited(evaluate());
      },
      onCancel: () async {
        timer?.cancel();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream;
  }
}
```

- [ ] **Step 5: Correr los tests y verificar que pasan**

Run: `flutter test test/core/platform/connectivity_service_test.dart`
Expected: PASS, los 5 tests.

- [ ] **Step 6: Implementar las señales del navegador**

Crear `lib/core/platform/browser_connectivity_signals.dart`:

```dart
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'connectivity_signals.dart';

/// [ConnectivitySignals] sobre las APIs reales del navegador.
///
/// No tiene tests unitarios a propósito: es una capa de traducción sin lógica.
/// Se verifica en el navegador, en la Tarea 7.
class BrowserConnectivitySignals implements ConnectivitySignals {
  BrowserConnectivitySignals({
    required this.probeUrl,
    this.probeTimeout = const Duration(seconds: 5),
  });

  /// URL a la que se le hace la sonda. Debe responder sin autenticación.
  final String probeUrl;
  final Duration probeTimeout;

  @override
  bool get isOnline => web.window.navigator.onLine;

  @override
  Stream<void> get onOnline => _windowEvents('online');

  @override
  Stream<void> get onOffline => _windowEvents('offline');

  @override
  Future<bool> probe() async {
    try {
      // `mode: 'no-cors'` a propósito: solo interesa saber si hay camino de
      // red hasta el backend, no leer la respuesta. Evita depender de que el
      // endpoint mande cabeceras CORS — si no las mandara, un fetch normal
      // tiraría excepción y reportaríamos "offline" estando online.
      //
      // La contrapartida es que la respuesta es opaca (`status == 0`), así
      // que el indicador de alcanzabilidad es que la promesa **resuelva**,
      // no el código de estado.
      await web.window
          .fetch(
            probeUrl.toJS,
            web.RequestInit(method: 'GET', mode: 'no-cors', cache: 'no-store'),
          )
          .toDart
          .timeout(probeTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  Stream<void> _windowEvents(String type) {
    late final StreamController<void> controller;
    final listener = ((web.Event _) {
      if (!controller.isClosed) controller.add(null);
    }).toJS;

    controller = StreamController<void>.broadcast(
      onListen: () => web.window.addEventListener(type, listener),
      onCancel: () => web.window.removeEventListener(type, listener),
    );

    return controller.stream;
  }
}
```

- [ ] **Step 7: Cablear el provider**

Reemplazar el contenido completo de `lib/core/offline/connectivity_provider.dart`:

```dart
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../platform/browser_connectivity_signals.dart';
import '../platform/connectivity_service.dart';
import 'offline_queue_service.dart';

export '../platform/connectivity_service.dart' show AppConnectivity;

/// Endpoint de salud de GoTrue: responde sin apikey y es liviano.
String _probeUrl() => '${Env.supabaseUrl}/auth/v1/health';

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService(
    BrowserConnectivitySignals(probeUrl: _probeUrl()),
  );
});

final connectivityStatusProvider = StreamProvider<AppConnectivity>((ref) {
  return ref.watch(connectivityServiceProvider).watch();
});

/// Observa la conectividad y procesa la cola offline al recuperar conexión.
final offlineAutoSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AppConnectivity>>(connectivityStatusProvider,
      (previous, next) {
    final wasOffline = previous?.valueOrNull == AppConnectivity.offline;
    final isOnline = next.valueOrNull == AppConnectivity.online;

    if (wasOffline && isOnline) {
      if (kDebugMode) {
        dev.log('Connection restored — processing offline queue',
            name: 'OfflineAutoSync');
      }
      final queue = ref.read(offlineQueueProvider);
      queue.processQueue(client: Supabase.instance.client).then((result) {
        if (kDebugMode) {
          dev.log(
              'Offline sync: ${result.succeeded} ok, ${result.failed} failed, ${result.remaining} remaining',
              name: 'OfflineAutoSync');
        }
      });
    }
  });
});
```

- [ ] **Step 8: Agregar `package:web` a las dependencias**

En `pubspec.yaml`, dentro de `dependencies:`, en orden alfabético cerca de `uuid`:

```yaml
  web: ^1.1.0
```

Run: `flutter pub get`

- [ ] **Step 9: Verificar que la suite completa pasa**

Run: `flutter test`
Expected: PASS. Los 14 tests previos más los 5 nuevos. `connectivity_provider.dart` ya no
importa `dart:io`.

- [ ] **Step 10: Commit**

```bash
git add lib/core/platform/ lib/core/offline/connectivity_provider.dart test/core/platform/ pubspec.yaml pubspec.lock
git commit -m "feat: conectividad web con sonda al backend, sin dart:io"
```

---

### Task 4: Clasificación de errores sin dart:io

Resuelve B3. `SocketException` y `HttpException` no existen en web. Además —y esto importa
más que el error de compilación— **los mensajes de fallo de red del navegador son
distintos en cada uno**, así que sin agregarlos la detección de "sin conexión" se rompería
en silencio justo donde más se necesita:

| Navegador | Mensaje ante fallo de red |
|---|---|
| Chrome / Edge | `Failed to fetch` |
| Safari | `Load failed` |
| Firefox | `NetworkError when attempting to fetch resource` |

**Files:**
- Modify: `lib/core/utils/error_handler.dart:2` (import) y `:48-72` (clasificación)
- Modify: `test/core/utils/error_handler_test.dart` (reemplazo completo)

**Interfaces:**
- Consumes: nada.
- Produces: `ErrorHandler.analyzeError(dynamic)` sigue devolviendo `NetworkError`. La firma
  y el enum `NetworkErrorType` no cambian; solo cambia cómo se clasifica.

- [ ] **Step 1: Escribir los tests que fallan**

Reemplazar el contenido completo de `test/core/utils/error_handler_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/utils/error_handler.dart';

void main() {
  group('ErrorHandler.analyzeError — fallos de red del navegador', () {
    test('clasifica "Failed to fetch" de Chrome como noConnection', () {
      final result = ErrorHandler.analyzeError(
        Exception('ClientException: Failed to fetch, uri=https://x.supabase.co'),
      );

      expect(result.type, NetworkErrorType.noConnection);
      expect(result.isRetryable, isTrue);
    });

    test('clasifica "Load failed" de Safari como noConnection', () {
      final result = ErrorHandler.analyzeError(
        Exception('ClientException: Load failed, uri=https://x.supabase.co'),
      );

      expect(result.type, NetworkErrorType.noConnection);
      expect(result.isRetryable, isTrue);
    });

    test('clasifica el NetworkError de Firefox como noConnection', () {
      final result = ErrorHandler.analyzeError(
        Exception('NetworkError when attempting to fetch resource.'),
      );

      expect(result.type, NetworkErrorType.noConnection);
      expect(result.isRetryable, isTrue);
    });

    test('clasifica timeouts como retryable', () {
      final result = ErrorHandler.analyzeError(
        Exception('TimeoutException after 0:00:30.000000'),
      );

      expect(result.type, NetworkErrorType.timeout);
      expect(result.isRetryable, isTrue);
    });
  });

  group('ErrorHandler.analyzeError — errores HTTP', () {
    test('clasifica 401', () {
      final result = ErrorHandler.analyzeError('401 Unauthorized');

      expect(result.type, NetworkErrorType.unauthorized);
      expect(result.statusCode, 401);
      expect(result.isRetryable, isFalse);
    });

    test('clasifica 403', () {
      final result = ErrorHandler.analyzeError('403 Forbidden');

      expect(result.type, NetworkErrorType.forbidden);
      expect(result.statusCode, 403);
    });

    test('clasifica 404', () {
      final result = ErrorHandler.analyzeError('404 Not Found');

      expect(result.type, NetworkErrorType.notFound);
      expect(result.statusCode, 404);
    });

    test('clasifica errores de servidor como retryable', () {
      final result = ErrorHandler.analyzeError('503 server error');

      expect(result.type, NetworkErrorType.serverError);
      expect(result.isRetryable, isTrue);
    });
  });

  group('ErrorHandler.analyzeError — desconocidos', () {
    test('no marca como retryable lo que no reconoce', () {
      final result = ErrorHandler.analyzeError(Exception('random failure'));

      expect(result.type, NetworkErrorType.unknown);
      expect(result.isRetryable, isFalse);
      expect(result.message, isNotEmpty);
    });

    test('devuelve el string tal cual cuando el error es un String', () {
      final result = ErrorHandler.analyzeError('algo raro pasó');

      expect(result.type, NetworkErrorType.unknown);
      expect(result.message, 'algo raro pasó');
    });
  });
}
```

- [ ] **Step 2: Correr los tests y verificar que fallan**

Run: `flutter test test/core/utils/error_handler_test.dart`
Expected: FAIL — los tres tests de fallo de red del navegador dan `unknown` en vez de
`noConnection`, porque `error_handler.dart` todavía no conoce esos mensajes.

- [ ] **Step 3: Quitar el import de `dart:io`**

En `lib/core/utils/error_handler.dart`, borrar la línea 2:

```dart
import 'dart:io';
```

- [ ] **Step 4: Reemplazar los dos primeros bloques de clasificación**

En `lib/core/utils/error_handler.dart`, reemplazar el bloque de las líneas 51-72 (desde el
comentario `// Error de conexión (sin internet)` hasta el cierre del bloque de timeout):

```dart
    // Error de conexión (sin internet).
    //
    // En web el mensaje depende del navegador y no hay una excepción tipada
    // que los unifique, así que se matchea por texto:
    //   Chrome/Edge → "Failed to fetch"
    //   Safari      → "Load failed"
    //   Firefox     → "NetworkError when attempting to fetch resource"
    if (errorString.contains('failed to fetch') ||
        errorString.contains('load failed') ||
        errorString.contains('networkerror') ||
        errorString.contains('network error') ||
        errorString.contains('socket') ||
        errorString.contains('failed host lookup') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection closed')) {
      return const NetworkError(
        type: NetworkErrorType.noConnection,
        message: 'Sin conexión a internet. Verifique su red.',
        isRetryable: true,
      );
    }

    // Timeout
    if (errorString.contains('timeout')) {
      return const NetworkError(
        type: NetworkErrorType.timeout,
        message: 'La operación tardó demasiado. Intente nuevamente.',
        isRetryable: true,
      );
    }
```

Nota: se saca `errorString.contains('network')` a secas, que era demasiado amplio —
capturaba cualquier mensaje con la palabra "network" y lo daba por falta de conexión. Se
reemplaza por `networkerror` y `network error`, que son los textos reales.

- [ ] **Step 5: Correr los tests y verificar que pasan**

Run: `flutter test test/core/utils/error_handler_test.dart`
Expected: PASS, los 10 tests.

- [ ] **Step 6: Correr la suite completa**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/core/utils/error_handler.dart test/core/utils/error_handler_test.dart
git commit -m "fix: clasificar errores de red del navegador sin dart:io"
```

---

### Task 5: Descarga de PDF con package:web

Resuelve B4 y C2. Se elimina el par stub/web con import condicional (ya no hay más de una
plataforma) y se elimina `printing`, que solo la usaba un método muerto.

**Files:**
- Create: `lib/core/platform/file_download.dart`
- Delete: `lib/features/dashboard/data/event_report_service_stub.dart`
- Delete: `lib/features/dashboard/data/event_report_service_web.dart`
- Modify: `lib/features/dashboard/data/event_report_service.dart:1-13` (imports),
  `:383-403` (`exportAndShare` y `printPreview`)
- Modify: `pubspec.yaml` (baja de `printing`)

**Interfaces:**
- Consumes: `package:web`, agregado en la Tarea 3.
- Produces: `void downloadBytes(Uint8List bytes, String fileName, {String mimeType})` en
  `lib/core/platform/file_download.dart`.
- `EventReportService.exportAndShare(String eventId, String eventName, AppLocalizations l10n)`
  conserva su firma; la llama `admin_dashboard_view.dart:240`.
- `EventReportService.printPreview(...)` **deja de existir**.

- [ ] **Step 1: Confirmar que `printPreview` no tiene consumidores**

Run: `grep -rn "printPreview" lib test`
Expected: solo la declaración en `event_report_service.dart:400`. Si aparece cualquier otra
línea, **parar** y reportarlo — la premisa de esta tarea sería falsa.

- [ ] **Step 2: Escribir el módulo de descarga**

Crear `lib/core/platform/file_download.dart`:

```dart
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Dispara la descarga de [bytes] en el navegador con el nombre [fileName].
///
/// Crea un blob temporal y un ancla oculta que se clickea por código. La URL
/// del objeto se revoca enseguida para no filtrar memoria: la descarga ya
/// quedó iniciada en ese punto.
void downloadBytes(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();

  web.URL.revokeObjectURL(url);
}
```

- [ ] **Step 3: Borrar los archivos del import condicional**

```bash
git rm lib/features/dashboard/data/event_report_service_stub.dart
git rm lib/features/dashboard/data/event_report_service_web.dart
```

- [ ] **Step 4: Arreglar los imports de `event_report_service.dart`**

Reemplazar las líneas 1 a 13 de `lib/features/dashboard/data/event_report_service.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:imagine_access/core/platform/file_download.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
```

Salen: `package:flutter/foundation.dart show kIsWeb`, `package:share_plus/share_plus.dart`,
`package:printing/printing.dart`, y el bloque del import condicional.

> `share_plus` sale **de este archivo**, no del proyecto: sigue en uso en
> `ticket_list_screen.dart:487` para compartir tickets por texto.

- [ ] **Step 5: Reemplazar `exportAndShare` y borrar `printPreview`**

Reemplazar el bloque de las líneas 383 a 403 de
`lib/features/dashboard/data/event_report_service.dart`:

```dart
  Future<void> exportAndShare(
      String eventId, String eventName, AppLocalizations l10n) async {
    final bytes = await generatePdf(eventId, eventName, l10n);
    final fileName =
        'reporte_${_sanitize(eventName)}_${DateTime.now().millisecondsSinceEpoch}.pdf';

    downloadBytes(bytes, fileName, mimeType: 'application/pdf');
  }
```

`printPreview` se borra por completo. El parámetro `l10n` de `exportAndShare` se conserva
porque `generatePdf` lo necesita.

- [ ] **Step 6: Dar de baja `printing`**

En `pubspec.yaml`, borrar de `dependencies:`:

```yaml
  printing: ^5.14.3
```

Run: `flutter pub get`

- [ ] **Step 7: Verificar que no quedan referencias**

Run: `grep -rn "printing\|Printing\|kIsWeb\|dart:html\|share_plus" lib/features/dashboard/`
Expected: sin resultados.

- [ ] **Step 8: Verificar análisis y tests**

```powershell
flutter analyze
flutter test
```
Expected: `flutter analyze` sin errores. `flutter test` PASS.

- [ ] **Step 9: Commit**

```bash
git add -A lib/features/dashboard/data/ lib/core/platform/file_download.dart pubspec.yaml pubspec.lock
git commit -m "refactor: descarga de PDF con package:web y baja de printing"
```

---

### Task 6: Configuración por --dart-define

Resuelve M1. `.env` se empaqueta como asset de Flutter, así que en web queda servido en
`/assets/.env`, descargable por cualquiera. Hoy solo tiene el URL y el anon key de Supabase
—públicos por diseño— pero `.env.example` documenta `SERVICE_ROLE_KEY`, `QR_SECRET_KEY` y
`SMTP_PASS` en el mismo formato. La forma de que eso nunca se filtre es que el archivo deje
de existir en el bundle.

**Files:**
- Modify: `lib/core/config/env.dart` (reemplazo completo)
- Modify: `lib/main.dart:8` (import), `:63-77` (carga de dotenv)
- Modify: `test/core/config/env_test.dart` (reemplazo completo)
- Modify: `pubspec.yaml` (baja de `flutter_dotenv`, baja de los assets `.env`)
- Modify: `.env.example` (separar variables de app y de Edge Functions)
- Delete: `.env`, `.env.dev`, `.env.staging`

**Interfaces:**
- Consumes: nada.
- Produces: `Env.supabaseUrl` y `Env.supabaseAnonKey` siguen siendo getters `String` que
  lanzan `Exception` si el valor falta o es un placeholder. Los consumen `main.dart:81-82`
  y `connectivity_provider.dart` (Tarea 3).

- [ ] **Step 1: Escribir los tests**

Reemplazar el contenido completo de `test/core/config/env_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/config/env.dart';

/// `String.fromEnvironment` se resuelve en tiempo de compilación, así que
/// estos tests describen el comportamiento con los valores que reciba la
/// corrida. Para ejercitar el camino feliz:
///
///   flutter test --dart-define=SUPABASE_URL=https://real.supabase.co \
///                --dart-define=SUPABASE_ANON_KEY=una_clave_de_mas_de_veinte_chars
void main() {
  group('Env', () {
    test('falla con un mensaje accionable cuando falta configuración', () {
      const url = String.fromEnvironment('SUPABASE_URL');

      if (url.isEmpty) {
        expect(
          () => Env.supabaseUrl,
          throwsA(predicate(
            (e) => e.toString().contains('--dart-define=SUPABASE_URL'),
            'el mensaje le dice al desarrollador exactamente qué hacer',
          )),
        );
      } else {
        expect(Env.supabaseUrl, url);
      }
    });

    test('rechaza valores placeholder', () {
      expect(Env.isPlaceholder('https://your-project.supabase.co'), isTrue);
      expect(Env.isPlaceholder('https://tu-proyecto.supabase.co'), isTrue);
      expect(Env.isPlaceholder('YOUR_SUPABASE_URL'), isTrue);
      expect(Env.isPlaceholder('https://abcdefgh.supabase.co'), isFalse);
    });

    test('rechaza claves demasiado cortas para ser reales', () {
      expect(Env.isTooShort('corta'), isTrue);
      expect(Env.isTooShort('una_clave_de_mas_de_veinte_caracteres'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Correr los tests y verificar que fallan**

Run: `flutter test test/core/config/env_test.dart`
Expected: FAIL — `Env.isPlaceholder` y `Env.isTooShort` no existen todavía.

- [ ] **Step 3: Reescribir `env.dart`**

Reemplazar el contenido completo de `lib/core/config/env.dart`:

```dart
/// Configuración de la app, provista en tiempo de compilación.
///
/// Deliberadamente **no** se lee de un archivo `.env`: en web los assets de
/// Flutter se sirven por HTTP, así que un `.env` empaquetado queda público en
/// `/assets/.env`. Todo entra por `--dart-define`.
///
/// Build:
/// ```
/// flutter build web --release \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=xxxx
/// ```
class Env {
  const Env._();

  static const _placeholders = <String>[
    'your-project.supabase.co',
    'tu-proyecto.supabase.co',
    'your-anon-key',
    'tu-anon-key',
    'YOUR_SUPABASE_URL',
    'YOUR_SUPABASE_ANON_KEY',
  ];

  /// `true` si [value] es uno de los valores de ejemplo de `.env.example`.
  static bool isPlaceholder(String value) =>
      _placeholders.any(value.contains);

  /// `true` si [value] es demasiado corto para ser una credencial real.
  static bool isTooShort(String value) => value.length < 20;

  static String get supabaseUrl =>
      _require(const String.fromEnvironment('SUPABASE_URL'), 'SUPABASE_URL');

  static String get supabaseAnonKey {
    final value = _require(
      const String.fromEnvironment('SUPABASE_ANON_KEY'),
      'SUPABASE_ANON_KEY',
    );
    if (isTooShort(value)) {
      throw Exception('SUPABASE_ANON_KEY parece inválida (demasiado corta).');
    }
    return value;
  }

  static String _require(String raw, String name) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw Exception(
        '$name no está configurada. Compilá con --dart-define=$name=...',
      );
    }
    if (isPlaceholder(value)) {
      throw Exception(
        '$name tiene un valor de ejemplo. Reemplazalo por el valor real.',
      );
    }
    return value;
  }
}
```

- [ ] **Step 4: Correr los tests y verificar que pasan**

Run: `flutter test test/core/config/env_test.dart`
Expected: PASS, los 3 tests.

- [ ] **Step 5: Sacar dotenv de `main.dart`**

En `lib/main.dart`, borrar la línea 8:

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
```

Y borrar el bloque completo de las líneas 62 a 77 — desde el comentario
`// Load environment file based on flavor` hasta el cierre del `try/catch` de
`dotenv.load`. El `switch` sobre `appFlavor` para elegir el archivo desaparece con él.

- [ ] **Step 6: Sacar la dependencia y los assets**

En `pubspec.yaml`, borrar de `dependencies:`:

```yaml
  flutter_dotenv: ^5.2.1
```

Y de la sección `flutter: assets:`, borrar las tres primeras entradas, dejando:

```yaml
  assets:
    - assets/logos/
```

Run: `flutter pub get`

- [ ] **Step 7: Borrar los archivos de entorno**

```bash
rm .env .env.dev .env.staging
```

Están en `.gitignore` (líneas 59-60), así que no estaban versionados. Guardar los valores
de `.env` en el gestor de contraseñas antes de borrarlo: son los que van en el
`--dart-define` de ahora en adelante.

- [ ] **Step 8: Separar `.env.example`**

Reemplazar el contenido completo de `.env.example`:

```bash
# ==========================================================================
# Imagine Access — variables de ejemplo
# ==========================================================================
# NADA de esto se empaqueta en la app. Se dividen en dos grupos con destinos
# distintos, y mezclarlos es un incidente de seguridad esperando pasar.

# --------------------------------------------------------------------------
# GRUPO 1 — App web. Van por --dart-define en el build.
# Quedan visibles en el bundle JS; es correcto, la barrera real es RLS.
# --------------------------------------------------------------------------
# flutter build web --release \
#   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
#   --dart-define=SUPABASE_ANON_KEY=xxxx

SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY

# --------------------------------------------------------------------------
# GRUPO 2 — Edge Functions. Se cargan como secrets en Supabase.
# NUNCA en --dart-define, NUNCA como asset de Flutter.
# supabase secrets set QR_SECRET_KEY=...
# --------------------------------------------------------------------------

SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY
QR_SECRET_KEY=YOUR_QR_SECRET_KEY
SMTP_HOST=smtp.hostinger.com
SMTP_PORT=587
SMTP_USER=tickets@imaginelab.shop
SMTP_PASS=YOUR_SMTP_PASSWORD
SMTP_DEBUG=false
ALLOWED_ORIGIN=https://imaginecloud.digital
ENVIRONMENT=production
```

- [ ] **Step 9: Verificar**

```powershell
flutter analyze
flutter test
```
Expected: `flutter analyze` sin errores. `flutter test` PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/core/config/env.dart lib/main.dart test/core/config/env_test.dart pubspec.yaml pubspec.lock .env.example
git commit -m "refactor: configuración por dart-define en vez de .env empaquetado"
```

---

### Task 7: Purga de targets nativos y primer arranque en el navegador

Resuelve M6 y la §3.1 del spec. Además es la primera vez que la app corre de verdad en un
navegador — hasta acá solo compilaba.

**Files:**
- Delete: `android/`, `ios/`, `macos/`, `windows/`, `linux/`, `deploy_app.ps1`,
  `deploy_ios.sh`, `generate_keystore.ps1`, `build_old/`, `flutter_01.log`,
  `flutter_02.log`, `UsersHp.git-credentials-imagine`
- Modify: `.gitignore`
- Modify: `pubspec.yaml` (baja de `flutter_launcher_icons` y `flutter_native_splash`)

**Interfaces:**
- Consumes: todo lo de las tareas 2 a 6.
- Produces: un `build/web/` que arranca en el navegador. Es la base de la Tarea 8.

- [ ] **Step 1: Etiquetar el estado con soporte nativo**

```bash
git tag pre-pwa-native -m "Último estado con targets Android/iOS/desktop, previo a la migración a PWA"
```

Este tag es la vuelta atrás. Sin él, el borrado del paso siguiente no tiene red.

- [ ] **Step 2: Revisar y borrar el archivo de credenciales**

```bash
cat UsersHp.git-credentials-imagine
```

Contiene tokens de GitHub en texto plano. Confirmar que ninguno esté en uso —y si lo está,
revocarlo en GitHub— antes de borrar:

```bash
rm UsersHp.git-credentials-imagine
```

- [ ] **Step 3: Borrar los targets nativos y los scripts de release**

```bash
git rm -r --quiet android ios macos windows linux
git rm --quiet deploy_app.ps1 deploy_ios.sh generate_keystore.ps1
rm -rf build_old flutter_01.log flutter_02.log
```

- [ ] **Step 4: Actualizar `.gitignore`**

Agregar al final de `.gitignore`:

```gitignore
# Artefactos de builds anteriores
build_old/
*.log

# Nunca versionar credenciales
*.git-credentials*
```

- [ ] **Step 5: Dar de baja las herramientas de empaquetado nativo**

En `pubspec.yaml`, borrar de `dev_dependencies:`:

```yaml
  flutter_launcher_icons: ^0.14.4
  flutter_native_splash: ^2.4.7
```

Y borrar las dos secciones de configuración del final del archivo, desde el comentario
`# Launcher Icons Configuration` hasta el final: los bloques `flutter_launcher_icons:` y
`flutter_native_splash:` completos. Los iconos web se regeneran en el Plan 3.

Run: `flutter pub get`

- [ ] **Step 6: Confirmar que solo queda el target web**

Run: `flutter build web --dart-define=SUPABASE_URL=https://placeholder.supabase.co --dart-define=SUPABASE_ANON_KEY=placeholder_key_at_least_20_chars`
Expected: **el build completa sin errores.** Es el primer build exitoso del plan.

Si falla, el error apunta a un bloqueante que las tareas 2-6 no cubrieron. Anotarlo, no
improvisar un arreglo: volver al diagnóstico.

- [ ] **Step 7: Arrancar la app en Chrome con credenciales reales**

```powershell
flutter run -d chrome --dart-define=SUPABASE_URL=<url real> --dart-define=SUPABASE_ANON_KEY=<key real>
```

Verificar en este orden:
1. La app carga y llega a la pantalla de bienvenida — no queda en blanco.
2. Login con un usuario admin real funciona.
3. El dashboard trae datos de Supabase.
4. Con la consola de red del navegador, cortar la conexión (DevTools → Network → Offline):
   el `OfflineSyncBanner` naranja aparece en menos de 35 segundos.
5. Restaurar la conexión: el banner desaparece.
6. Exportar el PDF de un evento desde el dashboard de admin: el archivo se descarga.

Los puntos 4 y 5 verifican la Tarea 3 en el navegador real, que es donde vive el código que
no tiene tests unitarios. El punto 6 verifica la Tarea 5.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: eliminar targets nativos, la app pasa a ser solo web"
```

---

### Task 8: Self-hostear ZXing

Resuelve C1. `mobile_scanner` descarga ZXing desde `https://unpkg.com/@zxing/library@0.21.3`
en tiempo de ejecución (`mobile_scanner-7.2.0/lib/src/web/zxing/zxing_barcode_reader.dart:60`),
así que **sin internet el escáner no arranca** — justo el escenario de una puerta con wifi
malo. El plugin salta esa descarga si ya existe un `<script>` con el id
`mobile-scanner-barcode-reader` en el DOM (`barcode_reader.dart:84`), que es el mecanismo
que usa esta tarea.

**Files:**
- Create: `web/js/zxing-0.21.3.min.js`
- Modify: `web/index.html` (una etiqueta `<script>` en el `<head>`)

**Interfaces:**
- Consumes: el `web/index.html` de la Tarea 2.
- Produces: escáner que funciona sin acceso a unpkg. Base de la Tarea 9.

- [ ] **Step 1: Descargar la librería**

Debe ser exactamente la versión `0.21.3`, la misma que espera el plugin.

```powershell
New-Item -ItemType Directory -Force web\js
Invoke-WebRequest -Uri "https://unpkg.com/@zxing/library@0.21.3/umd/index.min.js" -OutFile "web\js\zxing-0.21.3.min.js"
```

- [ ] **Step 2: Verificar que el archivo es válido**

```powershell
(Get-Item web\js\zxing-0.21.3.min.js).Length
Get-Content web\js\zxing-0.21.3.min.js -TotalCount 1
```

Expected: tamaño de varios cientos de KB, y la primera línea es JavaScript minificado —no
HTML de una página de error. Si empieza con `<`, la descarga falló y bajó una página de
error.

- [ ] **Step 3: Inyectar el script en `index.html`**

En `web/index.html`, agregar justo antes de `</head>`:

```html
  <!--
    ZXing self-hosteado. mobile_scanner lo bajaría de unpkg.com en runtime, lo
    que rompe el escaneo sin internet — el caso de uso principal en la puerta.
    El plugin salta su propia descarga si encuentra un script con este id
    (mobile_scanner/lib/src/web/barcode_reader.dart:84). El id es contrato con
    el plugin: no cambiarlo.
  -->
  <script id="mobile-scanner-barcode-reader" src="js/zxing-0.21.3.min.js"></script>
```

- [ ] **Step 4: Verificar que el escáner carga sin salir a unpkg**

```powershell
flutter run -d chrome --dart-define=SUPABASE_URL=<url real> --dart-define=SUPABASE_ANON_KEY=<key real>
```

Con DevTools → Network abierto y el filtro en `unpkg`:
1. Loguearse y navegar a `/scanner`.
2. Dar permiso de cámara.
3. **No debe haber ninguna request a `unpkg.com`.** Si aparece una, el script no se cargó
   —revisar el id y la ruta— y la tarea no está lista.
4. Escanear un QR de ticket válido y confirmar que se detecta.

- [ ] **Step 5: Verificar que funciona sin conexión**

Con la app ya cargada, en DevTools → Network poner **Offline**, recargar la página, e ir a
`/scanner`. La cámara tiene que abrir y el lector inicializar. La validación va a fallar
—no hay red— y encolarse, que es lo correcto; lo que se verifica acá es que **el lector
arranca**, que antes era imposible sin internet.

- [ ] **Step 6: Commit**

```bash
git add web/js/zxing-0.21.3.min.js web/index.html
git commit -m "fix: self-hostear ZXing para que el escáner funcione offline"
```

---

### Task 9: Instrumentar la latencia del escáner

Prepara la medición de la Tarea 10. Sin instrumentación, "¿anda rápido?" se responde con
impresiones; con ella, con números.

Aprovecha para eliminar el botón de linterna (M5), que en web nunca puede funcionar:
`mobile_scanner` devuelve `hasTorch: false` fijo (`barcode_reader.dart:73-75`), así que hoy
es un botón que no hace nada.

**Files:**
- Modify: `lib/features/scanner/presentation/scanner_screen.dart:30-40` (estado),
  `:62-72` (`_onDetect`), `:228-240` (botón de linterna)

**Interfaces:**
- Consumes: el escáner funcionando de la Tarea 8.
- Produces: un overlay de depuración, visible solo en debug, con la latencia de detección.
  Lo lee la Tarea 10.

- [ ] **Step 1: Agregar el estado de medición**

En `lib/features/scanner/presentation/scanner_screen.dart`, dentro de
`_ScannerScreenState`, junto a los campos existentes (después de `Map<String, dynamic>? _scanResult;`):

```dart
  /// Instante en que la cámara quedó lista, o en que terminó el último escaneo.
  /// Es el punto cero para medir cuánto tarda el lector en enganchar un código.
  DateTime? _detectionWindowStart;

  /// Latencias medidas en esta sesión, en milisegundos.
  final List<int> _detectionLatencies = <int>[];
```

- [ ] **Step 2: Medir en `_onDetect`**

En `_onDetect`, reemplazar el cuerpo del método (líneas 62-72) por:

```dart
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    _isProcessing = true; // Set synchronously before async gap

    final start = _detectionWindowStart;
    if (start != null) {
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      _detectionLatencies.add(elapsed);
      _detectionWindowStart = null;
      if (kDebugMode) {
        dev.log('Detección en ${elapsed}ms (n=${_detectionLatencies.length})',
            name: 'ScannerLatency');
      }
    }

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        _processCode(barcode.rawValue!);
        break; // Process only first code
      }
    }
  }
```

Agregar al inicio del archivo, junto a los imports existentes:

```dart
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart' show kDebugMode;
```

- [ ] **Step 3: Reiniciar la ventana de medición al volver a escanear**

Cada medición cuenta desde que el escáner queda listo para el código siguiente, que es lo
que percibe la persona parada en la puerta.

Reemplazar `_resetScanner()`, líneas 189-194:

```dart
  void _resetScanner() {
    setState(() {
      _scanResult = null;
      _isProcessing = false;
      _detectionWindowStart = DateTime.now();
    });
  }
```

Y en `initState`, agregar como última línea del método, después de
`WidgetsBinding.instance.addObserver(this);`:

```dart
    _detectionWindowStart = DateTime.now();
```

- [ ] **Step 4: Mostrar las estadísticas en pantalla en modo debug**

En el `Stack` del `build` (línea 206), agregar como último hijo — después del `Positioned`
del "Footer Status" que termina en la línea 294, y antes del `]` que cierra `children`:

```dart
              if (kDebugMode && _detectionLatencies.isNotEmpty)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Text(
                      'n=${_detectionLatencies.length}  '
                      'últ=${_detectionLatencies.last}ms  '
                      'med=${(_detectionLatencies.reduce((a, b) => a + b) / _detectionLatencies.length).round()}ms  '
                      'máx=${_detectionLatencies.reduce((a, b) => a > b ? a : b)}ms',
                      style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ),
```

- [ ] **Step 5: Eliminar el botón de linterna**

Es un control muerto en web: `mobile_scanner` devuelve `hasTorch: false` fijo, así que el
botón nunca cambia de estado ni enciende nada.

Borrar el bloque completo de las líneas 223-241, desde el comentario `// Flash Toggle`
hasta el `),` que cierra ese `Positioned`:

```dart
          // Flash Toggle
          Positioned(
            top: 50,
            right: 20,
            child: ValueListenableBuilder(
              valueListenable: _cameraController,
              builder: (context, value, child) {
                return IconButton(
                  icon: Icon(
                      value.torchState == TorchState.on
                          ? Icons.flash_on
                          : Icons.flash_off,
                      color: Colors.white,
                      size: 30),
                  onPressed: () => _cameraController.toggleTorch(),
                );
              },
            ),
          ),
```

También borrar `torchEnabled: false,` del constructor de `MobileScannerController` en
`initState` (línea 39), que queda sin sentido.

Verificar que no queden referencias:

Run: `grep -n "torch\|Torch\|flash" lib/features/scanner/presentation/scanner_screen.dart`
Expected: sin resultados.

- [ ] **Step 6: Verificar**

```powershell
flutter analyze
flutter test
flutter run -d chrome --dart-define=SUPABASE_URL=<url real> --dart-define=SUPABASE_ANON_KEY=<key real>
```

En `/scanner`: escanear tres QR seguidos y confirmar que el overlay verde de abajo a la
izquierda muestra `n=3` y tres latencias. Confirmar que el botón de linterna ya no está.

- [ ] **Step 7: Commit**

```bash
git add lib/features/scanner/presentation/scanner_screen.dart
git commit -m "feat: medir latencia de detección y quitar la linterna, muerta en web"
```

---

### Task 10: Spike en dispositivos reales y decisión go/no-go

Es la razón de ser de este plan. El spec §4.2 fija el criterio: **detección consistente por
debajo de 1.5 segundos**. Si el iPhone no llega y ninguna contingencia lo salva, "paridad
total con escáner en puerta" no se sostiene y hay que replantear el alcance con el usuario
antes de escribir los planes 2 y 3.

**Files:**
- Create: `docs/superpowers/spike-escaner-resultados.md`

**Interfaces:**
- Consumes: el escáner instrumentado de la Tarea 9.
- Produces: el documento de resultados, que determina si se escriben los planes 2 y 3 tal
  como están o si hay que volver al diseño.

- [ ] **Step 1: Servir el build por HTTPS en la red local**

`getUserMedia` exige contexto seguro. `localhost` califica, pero un teléfono en la LAN
llega por IP, que **no** califica. Sin HTTPS la cámara no abre y el spike no se puede hacer.

```powershell
flutter build web --profile --dart-define=SUPABASE_URL=<url real> --dart-define=SUPABASE_ANON_KEY=<key real>
npx --yes local-ssl-proxy --source 8443 --target 8000 &
cd build\web
npx --yes http-server -p 8000
```

Se usa `--profile` y no `--release` para que `kDebugMode` siga activo y el overlay de
latencia se vea.

Abrir `https://<IP de la PC>:8443` en cada teléfono y aceptar la advertencia de certificado.

- [ ] **Step 2: Preparar los códigos de prueba**

Se necesitan cuatro QR reales del entorno de la app, no QR genéricos:

1. Un ticket válido sin usar — **impreso en papel**.
2. El mismo ticket **en la pantalla de otro teléfono**.
3. Un ticket ya validado.
4. Un ticket de otro evento.

Además, un QR con texto arbitrario (por ejemplo `hola mundo`) para el caso de código
ilegible o ajeno.

- [ ] **Step 3: Medir en iPhone con Safari**

Por cada combinación de la tabla, escanear **10 veces** y anotar del overlay la mediana y
el máximo:

| Condición | Mediana (ms) | Máx (ms) | Fallos de 10 |
|---|---|---|---|
| Papel, luz de interior buena | | | |
| Papel, luz baja | | | |
| Pantalla de teléfono, brillo alto | | | |
| Pantalla de teléfono, brillo bajo | | | |

Anotar también el modelo de iPhone y la versión de iOS.

- [ ] **Step 4: Medir en Android con Chrome**

La misma tabla, mismo procedimiento. Anotar modelo y versión de Android.

- [ ] **Step 5: Correr la matriz funcional**

En **ambos** teléfonos, y anotando el resultado observado, no el esperado:

| Caso | iPhone/Safari | Android/Chrome |
|---|---|---|
| Ticket válido → acepta | | |
| Ticket ya usado → rechaza con el motivo correcto | | |
| Ticket de otro evento → rechaza | | |
| QR de texto arbitrario → error controlado, no crashea | | |
| Escaneo sin conexión → encola y avisa | | |
| Reconexión → la cola se procesa sola | | |

Los primeros cuatro casos son los que distinguen "probé el happy path" de "está probado".

- [ ] **Step 6: Medir el tiempo de carga inicial**

Con la caché del navegador vacía y el throttling de red en **Fast 4G**, medir el tiempo
desde que se abre la URL hasta que la pantalla de bienvenida es interactiva. Anotar también
el peso total transferido. Alimenta el riesgo "bundle pesado en 4G" del spec §10.

- [ ] **Step 7: Escribir el documento de resultados**

Crear `docs/superpowers/spike-escaner-resultados.md` con las cuatro tablas completas, los
modelos y versiones de los dispositivos, y un veredicto explícito:

- **GO** — la mediana en iPhone está por debajo de 1500 ms en todas las condiciones y la
  matriz funcional pasa completa. Se escriben los planes 2 y 3 según el spec.
- **GO CON CONTINGENCIA** — el criterio se incumple solo en condiciones de luz baja o
  pantalla. Se aplica la contingencia 1 del spec §4.2 (bajar resolución y recortar a un ROI
  central) y se vuelve a medir antes de seguir.
- **NO GO** — el criterio se incumple de forma amplia. Se escala a la contingencia 2 (shim
  de `dart:js_interop` a `zxing-wasm`), que es un plan aparte y hay que estimarlo.

Escribir los números medidos, no impresiones. Si algún caso no se pudo probar, decirlo
explícitamente en vez de dejarlo en blanco.

- [ ] **Step 8: Commit y reportar al usuario**

```bash
git add docs/superpowers/spike-escaner-resultados.md
git commit -m "docs: resultados del spike de escáner en dispositivos reales"
```

Presentar al usuario el veredicto con los números que lo respaldan. **No avanzar a los
planes 2 y 3 sin su confirmación** — si el veredicto es NO GO, la primera decisión del
proyecto (paridad total con escáner en puerta) queda en revisión.

---

## Estado al terminar este plan

- La app compila y corre en el navegador, sin `dart:io`, sin `dart:html`, sin imports
  condicionales y sin ningún CDN externo en runtime.
- Los cinco targets nativos y cuatro dependencias que ya no aplican están fuera, con el
  tag `pre-pwa-native` como vuelta atrás.
- La configuración va por `--dart-define`; no hay `.env` publicado como asset.
- El escáner funciona sin internet, y hay números reales de su rendimiento en iPhone y
  Android.

**Todavía no es una PWA instalable.** Faltan el manifest real, los iconos de marca, el
splash, el flujo de actualización del service worker (Plan 3), la cola offline en IndexedDB
y el token de sesión de dispositivo (Plan 2).
