# Imagine Access → PWA — Diseño

**Fecha:** 2026-07-27
**Estado:** aprobado, pendiente de plan de implementación
**Destino:** `https://imaginecloud.digital/` (Hostinger, LiteSpeed)

---

## 1. Objetivo y alcance

Convertir Imagine Access de app Flutter multiplataforma a **PWA web-only**, con paridad
funcional completa incluido el escaneo de QR en puerta y la cola offline.

**Decisiones tomadas durante el brainstorming:**

| Decisión | Valor |
|---|---|
| Alcance | Paridad total, incluido escáner en puerta con offline |
| Targets nativos | Se abandonan — la PWA reemplaza a Android e iOS |
| Dispositivos de puerta | BYOD: mezcla Android/Chrome e iPhone/Safari |
| Hosting | Hostinger, raíz de `imaginecloud.digital` |
| WordPress actual | Se reemplaza (requiere backup previo, ver §8) |
| PIN de dispositivo | Se cambia por token de sesión con expiración (§6) |
| Carpetas nativas | Tag `pre-pwa-native` y borrado |
| Stack | Se migra el Flutter existente, no se reescribe (§1.1) |

### 1.1 Por qué se mantiene Flutter y no se reescribe en un stack web

"PWA" describe cómo se instala y se comporta la app en el navegador (manifest + service
worker + HTTPS), no el lenguaje. Flutter compila a JS/WASM y produce una PWA válida. La
decisión real evaluada fue si convenía reescribir en React/Next + TypeScript.

**A favor de migrar (opción elegida):**

- Son 14.4k LOC de lógica ya depurada: wizard de tickets (875), creación de eventos (1070),
  generación de PDF (746), guards multi-tenant, cola offline, i18n en 3 idiomas, integración
  con 15 Edge Functions. Los últimos commits del repo son correcciones finas sobre esa
  lógica (packs promocionales, precios, timezone, validación) — bugs que costaron encontrar
  y que un rewrite reintroduce.
- Las debilidades reales de Flutter web —SEO, primera carga anónima, contenido de texto
  denso— **no aplican**: es una herramienta interna detrás de login, tipo app, que el
  personal instala una vez por evento y queda cacheada por el service worker.
- Estimación: 3-5 semanas contra 6-10 de un rewrite.

**En contra (aceptado conscientemente):** Flutter web es un impuesto técnico permanente —
rendering en canvas, rarezas de Safari, huecos del ecosistema de plugins. Si el producto
pasara a ser público con SEO y landing, la decisión debería revisarse.

**El argumento más fuerte del rewrite quedó neutralizado:** en JS hay librerías de QR
mejores que el ZXing que arrastra `mobile_scanner`, pero Flutter web puede llamar
JavaScript directo vía `dart:js_interop`. Se puede envolver `zxing-wasm` o
`BarcodeDetector` en un shim chico y usarlo desde el scanner de Flutter (ver §4.2).

**Fuera de alcance:** auditoría de RLS (ver §10), detección de duplicados en validación
offline (limitación preexistente, §5), rendimiento del `refreshSession()` previo a cada
Edge Function.

---

## 2. Estado de partida (auditoría)

Proyecto Flutter, 71 archivos Dart / ~14.4k LOC, Riverpod + go_router + Supabase
(15 Edge Functions), i18n es/en/pt, 14 tests.

> **Nota de verificación:** los hallazgos siguientes provienen de análisis estático del
> código fuente del proyecto y de los paquetes en pub cache. **No fueron confirmados con
> `flutter build web`** — Flutter no está instalado en la máquina de desarrollo actual.
> La etapa 0 existe para confirmarlos.

### Bloqueantes (impiden compilar o arrancar en web)

| # | Hallazgo | Ubicación |
|---|---|---|
| B1 | `_flutter.loader.loadEntrypoint()` fue eliminado en Flutter 3.27+; el proyecto pide Dart >=3.11. Pantalla en blanco. | `web/index.html` |
| B2 | `dart:io` — `InternetAddress.lookup` cada 5s | `lib/core/offline/connectivity_provider.dart:3` |
| B3 | `dart:io` — `SocketException` / `HttpException` para clasificar errores | `lib/core/utils/error_handler.dart:2,52,66` |
| B4 | `dart:html` (deprecado, incompatible con WASM) y condicional `if (dart.library.html)` | `lib/features/dashboard/data/event_report_service_web.dart:2`, `event_report_service.dart:13` |

### Críticos (compilan, rompen funcionalidad núcleo)

| # | Hallazgo | Evidencia |
|---|---|---|
| C1 | El escáner carga ZXing desde `https://unpkg.com/@zxing/library@0.21.3` en runtime → sin internet no arranca | `mobile_scanner-7.2.0/lib/src/web/zxing/zxing_barcode_reader.dart:60` |
| C2 | `printing` carga pdf.js desde `https://unpkg.com/pdfjs-dist` | `printing-5.14.3/lib/printing_web.dart:52` |
| | ↳ **Resolución revisada:** `printing` resultó ser dependencia muerta — solo la usa `EventReportService.printPreview()`, que no invoca nadie. Se elimina el método y la dependencia en vez de self-hostear pdf.js. | `event_report_service.dart:400` |
| C3 | Sin manejo de actualización del service worker → dispositivos pegados a versiones viejas | — |
| C4 | Cola offline en `SharedPreferences` → `localStorage` en web (5MB, purgable por el navegador) | `lib/core/offline/offline_queue_service.dart:41` |
| C5 | `flutter_secure_storage_web` cifra con una clave guardada en el mismo localStorage → legible por XSS. Guarda `last_access_token` y **`auth_device_pin`** | `lib/main.dart:89`, `lib/features/auth/presentation/auth_controller.dart:105,123` |
| C6 | CORS de Edge Functions acepta un solo `ALLOWED_ORIGIN`; hay ~17 `functions.invoke()` en cliente | `supabase/functions/_shared/cors.ts` |

### Medios

| # | Hallazgo |
|---|---|
| M1 | `.env` va como asset de Flutter → servido en `/assets/.env`. Hoy solo contiene `SUPABASE_URL` y `SUPABASE_ANON_KEY` (públicas por diseño), pero `.env.example` documenta `SERVICE_ROLE_KEY`, `QR_SECRET_KEY` y `SMTP_PASS` en el mismo archivo |
| M2 | `manifest.json` e iconos son el scaffold de Flutter (`#0175C2` en vez de `#0B0F16`; faltan `id`, `scope`, `display_override`, `shortcuts`, `screenshots`) |
| M3 | Deep links `/ticket/:id` y `/event/:slug` requieren fallback SPA en el hosting o dan 404 al refrescar |
| M4 | `flutter_native_splash` con `web: false` → pantalla blanca durante la carga del bundle |
| M5 | 7 llamadas a `HapticFeedback` (no-op en web) y botón de linterna muerto — `mobile_scanner` devuelve `hasTorch: false` fijo en web |
| M6 | Sin ignorar: `build_old/`, `ios/build/`, `flutter_01.log`, `flutter_02.log`. `UsersHp.git-credentials-imagine` contiene tokens de GitHub en texto plano (no trackeado) |

---

## 3. Arquitectura tras la migración

### 3.1 Qué se elimina

Precedido de `git tag pre-pwa-native` sobre el commit actual, en un commit propio:

- `android/` `ios/` `macos/` `windows/` `linux/`
- `deploy_app.ps1`, `deploy_ios.sh`, `generate_keystore.ps1`, `ios/strip_provenance_build.sh`
- `build_old/`, `ios/build/`, `ios/build_temp_old/`, `flutter_01.log`, `flutter_02.log`
- `UsersHp.git-credentials-imagine`
- Documentación de release nativa: `FLAVORS.md`, `PLAY_STORE_ANDROID_RELEASE.md`,
  `RELEASE_GUIDE.md`, `INSTRUCTIONS_WINDOWS.md` (se reemplazan por un `DEPLOY.md` de PWA)

Además, `.gitignore` gana `build_old/`, `*.log` y `*.git-credentials*` para que M6 no se
repita.

### 3.2 Dependencias

**Fuera:** `flutter_secure_storage`, `app_links`, `flutter_dotenv`, `printing`,
`flutter_launcher_icons` (dev), `flutter_native_splash` (dev).

**Dentro:** `web` (js interop), `idb_shim` (IndexedDB).

**Se quedan:** `mobile_scanner` (con ZXing self-hosteado), `pdf`,
`share_plus` (se usa en `ticket_list_screen.dart:487` para compartir tickets por texto),
`shared_preferences` (preferencias chicas —
tema, idioma, evento seleccionado — más el token de sesión de dispositivo de §6),
`supabase_flutter`, `go_router`,
`flutter_riverpod`, `fl_chart`, `flutter_svg`, `flutter_animate`, `intl`, `uuid`.

`flutter_dotenv` sale: la configuración pasa a `--dart-define` en el build. Esto resuelve
M1 de raíz — deja de existir un `.env` publicado como asset. El anon key sigue siendo
visible en el bundle JS; eso es inevitable y correcto, la barrera real es RLS.

### 3.3 Capa nueva `lib/core/platform/`

Cuatro módulos, cada uno con una responsabilidad única, interfaz chica y testeable en
aislamiento:

| Módulo | Reemplaza | Interfaz | Implementación |
|---|---|---|---|
| `connectivity.dart` | B2 | `Stream<AppConnectivity> watch()` | `navigator.onLine` + eventos `online`/`offline`, más un HEAD periódico (30s) al endpoint de Supabase para detectar wifi-sin-internet |
| `queue_store.dart` | C4 | `read()` / `write()` / `clear()` sobre `List<PendingOperation>` | IndexedDB vía `idb_shim`, más `navigator.storage.persist()` al arrancar |
| `file_download.dart` | B4 | `void download(Uint8List bytes, String fileName, String mimeType)` | `package:web` + `dart:js_interop` |
| `feedback.dart` | M5 | `success()` / `failure()` / `tap()` | Vibration API cuando existe, más beep de audio y flash visual siempre |

**Consumidores:**
- `connectivity_provider.dart` pasa a delegar en `platform/connectivity.dart` y pierde
  `dart:io`. El `offlineAutoSyncProvider` no cambia.
- `offline_queue_service.dart` deja de usar `SharedPreferences` y pasa a `queue_store`.
  No hay migración de datos: web arranca vacío.
- `event_report_service.dart` pierde el import condicional; se borran
  `event_report_service_stub.dart` y `event_report_service_web.dart`, reemplazados por
  `platform/file_download.dart`.
- `error_handler.dart` pierde `dart:io` y clasifica por `ClientException` de
  `package:http` y por status code.
- `scanner_screen.dart` cambia sus 7 `HapticFeedback` por `feedback.dart`.

---

## 4. Escáner de QR

### 4.1 Self-hosting de ZXing (resuelve C1)

`web/js/zxing-0.21.3.min.js` servido localmente, inyectado en `index.html` como:

```html
<script id="mobile-scanner-barcode-reader" src="js/zxing-0.21.3.min.js"></script>
```

`mobile_scanner` salta la descarga desde unpkg si un script con ese id ya está en el DOM
(`barcode_reader.dart:84`). Con esto el escáner funciona offline y la CSP puede cerrarse
a `'self'`.

### 4.2 Spike de rendimiento (etapa 2)

`BarcodeDetector` **no** entra en el camino crítico: no existe en Safari, así que sólo
optimizaría Android, y el riesgo está en el iPhone.

El spike mide latencia real de escaneo en iPhone/Safari y Android/Chrome, con QR impresos
y en pantalla, con luz buena y mala, contra una cola simulada de personas.

**Criterio de aceptación:** detección en menos de 1.5s de forma consistente.

**Contingencias si Safari no llega, en orden:**

1. Bajar la resolución del video y recortar a un ROI central — ZXing procesa mucho menos píxel.
2. **Shim de `dart:js_interop` a `zxing-wasm`.** No estamos atados al ZXing que trae
   `mobile_scanner`: Flutter web puede llamar cualquier librería JS. Un módulo chico
   (~50 líneas) que exponga `Future<String?> decode(ImageData)` sobre `zxing-wasm` —port a
   WASM, notablemente más rápido que zxing-js— reemplaza al lector del plugin manteniendo
   el resto (cámara, permisos, ciclo de vida, UI). El mismo shim puede usar
   `BarcodeDetector` cuando existe (Chrome/Android) y caer a WASM en Safari.
3. Aceptar que en iPhone la vía primaria sea `/document_search`, que ya existe en la app.

La contingencia 2 es la que sostiene la decisión de §1.1: la ventaja de un stack web en
cuanto a librerías de QR es recuperable sin reescribir la app.

Si ninguna alcanza, se replantea el alcance con el usuario antes de seguir.

### 4.3 Linterna

Se elimina el botón de linterna (`scanner_screen.dart:232-237`). `mobile_scanner`
devuelve `hasTorch: false` de forma fija en web.

---

## 5. Offline

- La cola de operaciones pendientes vive en IndexedDB (§3.3), con
  `navigator.storage.persist()` solicitado al arrancar.
- **Se cachea sólo el shell de la app.** No se cachean respuestas de Supabase: en un
  sistema de validación de tickets, servir datos viejos es peor que no servir nada. El
  `OfflineSyncBanner` existente cubre la UX de estado degradado.
- **Limitación preexistente que se hereda:** estando offline, `validate_ticket` se encola
  y el escáner acepta el ticket (`offline_queue_service.dart:159`), por lo que **no puede
  detectar un QR duplicado hasta sincronizar**. No lo introduce esta migración y no se
  resuelve acá, pero conviene tenerlo presente: en web el storage es más frágil que en
  nativo, así que el riesgo pesa más.

---

## 6. Autenticación de dispositivos de puerta

### 6.1 Problema

Hoy el PIN del dispositivo se persiste (`auth_controller.dart:123`) y se envía como
credencial a RPCs (`p_device_pin`). En nativo vive en Keychain/Android Keystore; en web
pasaría a localStorage, legible por cualquier XSS, en teléfonos personales del personal.
Es una credencial de larga vida sin expiración ni revocación.

### 6.2 Diseño: token de sesión de dispositivo

**Tabla nueva `device_sessions`:**

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid PK | |
| `device_id` | uuid FK → `devices` | |
| `organization_id` | uuid | denormalizado para el chequeo de scope |
| `token_hash` | text | SHA-256 del token; el token en claro nunca se guarda |
| `created_at` | timestamptz | |
| `expires_at` | timestamptz | 12h por defecto — cubre un turno |
| `last_seen_at` | timestamptz | |
| `revoked_at` | timestamptz nullable | |

Índice en `token_hash`. RLS: sin acceso directo desde el cliente; sólo las funciones
`SECURITY DEFINER` y el service role la tocan.

**Cambios:**

| Componente | Cambio |
|---|---|
| `supabase/functions/login_device/index.ts` | Tras validar alias+PIN, genera un token opaco (32 bytes aleatorios en hex), guarda su hash en `device_sessions` y devuelve el token en claro una sola vez, junto con `expires_at`. La verificación de PIN existente no cambia. |
| `supabase/functions/validate_ticket/index.ts` | Acepta `device_token` en vez de `pin` |
| `supabase/functions/device_dashboard/index.ts` | Ídem |
| `supabase/functions/manage_devices/index.ts` | Nueva acción `revoke_sessions` para un `device_id` |
| SQL `get_device_tickets` | `p_device_pin` → `p_device_token`; valida contra `device_sessions` (hash, no revocado, no vencido) y actualiza `last_seen_at` |
| SQL `search_tickets_unified` | Ídem |
| `lib/features/auth/presentation/auth_controller.dart` | `DeviceSession` pasa de `pin` a `token` + `expiresAt`; se persiste en `shared_preferences` (ya no hace falta almacenamiento "seguro" — el token es corto y revocable) |
| `lib/features/scanner/data/scanner_repository.dart:137` | `p_device_pin` → `p_device_token` |
| `lib/features/tickets/data/ticket_repository.dart:128,134,152` | Ídem; se borra la lectura de `_secureStorage` |

**Manejo de expiración:** si un RPC o Edge Function devuelve token inválido/vencido, el
cliente limpia la sesión y redirige a `/login?mode=door`. La pantalla de gestión de
dispositivos gana un botón de revocar sesiones.

**Migración:** los dispositivos existentes vuelven a loguearse con alias+PIN una vez. El
PIN sigue siendo la credencial de login; lo que cambia es qué se guarda después.

### 6.3 `last_access_token`

Se elimina por completo. `supabase_flutter` ya persiste la sesión en el navegador, así que
la copia en "secure storage" no aportaba seguridad. Los sitios que lo leen
(`ticket_repository.dart:56,223,251`) pasan a usar `client.auth.currentSession?.accessToken`
directamente.

---

## 7. Capa PWA

### 7.1 `manifest.json`

Reescrito: `id`, `name`, `short_name`, `start_url: "/"`, `scope: "/"`,
`display: "standalone"`, `display_override: ["standalone", "minimal-ui"]`,
`theme_color` y `background_color` en `#0B0F16`, `orientation: "portrait-primary"`,
`lang`, `categories`, `shortcuts` (Escanear / Tickets / Dashboard) y `screenshots` (Chrome
requiere screenshots para mostrar el prompt de instalación enriquecido).

Iconos regenerados desde `assets/icon/app_icon.png` en 192 y 512, normal y maskable.

### 7.2 `index.html`

- Loader moderno: `{{flutter_js}}`, `{{flutter_build_config}}`, `_flutter.loader.load()` (resuelve B1)
- Splash inline sobre `#0B0F16` con el logo, removido en `onEntrypointLoaded` (resuelve M4)
- ~~`dartPdfJsBaseUrl` para pdf.js local~~ — innecesario: C2 se resuelve dando de baja
  `printing`, que no tiene consumidores reales (ver §2, C2)
- `<script id="mobile-scanner-barcode-reader">` (resuelve C1)
- `<meta name="theme-color" content="#0B0F16">` y meta tags `apple-mobile-web-app-*`

### 7.3 Actualización de la app (resuelve C3)

Cuando el service worker detecta una versión nueva, se muestra un banner "Hay una versión
nueva disponible" con un botón que hace `skipWaiting()` y recarga. Es innegociable en un
sistema de validación de accesos: sin esto, un dispositivo de puerta puede quedar corriendo
una versión vieja indefinidamente.

### 7.4 Instalación

- Android/Chrome: se captura `beforeinstallprompt` y se ofrece un botón "Instalar app".
- iOS/Safari: no dispara ese evento. Se detecta Safari iOS fuera de modo standalone y se
  muestra una hoja con instrucciones ("Compartir → Añadir a pantalla de inicio"). Además
  de la instalación, esto importa porque una PWA instalada en iOS no sufre el borrado de
  storage a los 7 días de inactividad.

---

## 8. Seguridad y deploy

### 8.1 Headers (`.htaccess`)

```
Content-Security-Policy:
  default-src 'self';
  script-src 'self' 'wasm-unsafe-eval';
  connect-src 'self' https://PROJECT.supabase.co wss://PROJECT.supabase.co;
  img-src 'self' data: blob:;
  worker-src 'self' blob:;
  frame-ancestors 'none';
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
X-Frame-Options: DENY
Permissions-Policy: camera=(self), geolocation=(), microphone=()
```

`PROJECT.supabase.co` se reemplaza por el host real de `SUPABASE_URL` al generar el
`.htaccess`; no se commitea el valor porque `.env` está en `.gitignore`.

Con todo self-hosteado no hace falta abrir la CSP a unpkg. Nota: Flutter genera JS inline
en `index.html`; hay que resolverlo con hash en la CSP o moviendo el script a un archivo.

### 8.2 Fallback SPA y caché

`.htaccess` con rewrite de cualquier ruta no-archivo a `/index.html` (resuelve M3), gzip y
brotli, y política de caché:

- Assets con hash: `max-age=31536000, immutable`
- `index.html`, `flutter_service_worker.js`, `manifest.json`: `no-cache`

Si `flutter_service_worker.js` se cachea, el flujo de actualización de §7.3 deja de
funcionar.

### 8.3 CORS (resuelve C6)

`supabase/functions/_shared/cors.ts` pasa de origen único a allowlist, comparando contra
el header `Origin` de la request: `https://imaginecloud.digital` y
`http://localhost:*` para desarrollo. Sin esto el desarrollo local queda roto contra las
15 Edge Functions.

### 8.4 Procedimiento de deploy

1. **BLOQUEANTE — backup completo del WordPress actual** (archivos + base de datos) por
   hPanel, verificado y descargado, antes de tocar nada. Requiere confirmación explícita
   del usuario en el momento de ejecutarlo.
2. Build: `flutter build web --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
3. Subir `build/web/` a la raíz por hPanel/FTP, más el `.htaccess`.
4. Aplicar migración SQL y desplegar Edge Functions con `ALLOWED_ORIGIN=https://imaginecloud.digital`.
5. Verificación post-deploy (§9).

> El MCP de Hostinger de la sesión actual está autenticado en otra cuenta — sólo ve
> `clinivaec.com`. `imaginecloud.digital` está en Hostinger (confirmado por headers
> `platform: hostinger` / `panel: hpanel`, IP `62.72.62.225`) pero en una cuenta distinta.
> O se reconecta el MCP con la cuenta correcta, o el deploy lo hace el usuario a mano.

---

## 9. Testing

**Prerequisito:** instalar Flutter en la máquina de desarrollo. Hoy no está — `where.exe
flutter` no encuentra nada y `deploy_app.ps1:3` apunta a `C:\Users\Hp\...`, otra máquina.

**Automatizado:**
- Los 14 tests existentes tienen que seguir pasando. `test/core/utils/error_handler_test.dart`
  hay que actualizarlo porque cambia la clasificación de errores.
- Nuevos: `queue_store` sobre IndexedDB (persistencia, orden, borrado), `connectivity`
  (transiciones online/offline), y verificación del token de dispositivo (válido /
  vencido / revocado / inexistente).

**Manual en dispositivo real** — matriz completa, no sólo happy path:

| Caso | iPhone/Safari | Android/Chrome |
|---|---|---|
| QR válido | | |
| QR ya usado | | |
| QR de otro evento | | |
| QR ilegible/basura | | |
| Escaneo sin conexión (encola) | | |
| Reconexión con cola pendiente | | |
| Instalación en pantalla de inicio | | |
| Actualización de versión (banner + reload) | | |
| Deep link `/ticket/:id` con refresh | | |
| Exportación de PDF | | |

Ningún ítem se declara "verificado" sin la matriz completa; los parciales se reportan como
"probado en X e Y, no probado en Z".

---

## 10. Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| ZXing inusable en Safari | Rompe el caso de uso principal | Etapa 2 lo mide antes de construir encima; 3 contingencias en §4.2, siendo el shim de js_interop a `zxing-wasm` la que da margen real |
| iOS purga storage de la cola offline | Pérdida de validaciones pendientes | `navigator.storage.persist()`; instalada en pantalla de inicio, iOS no aplica el límite de 7 días |
| Bundle pesado en 4G en la puerta | Primera carga lenta | Medir en etapa 0; evaluar `skwasm` vs `canvaskit` |
| Reemplazar el WordPress es irreversible | Pérdida del sitio actual | Backup como paso bloqueante (§8.4) |
| RLS sin auditar | Con anon key público y app en el navegador, RLS es la única barrera | Fuera de alcance — se recomienda auditoría aparte antes de producción |
| Validación offline no detecta duplicados | Doble ingreso con un mismo QR | Preexistente; documentado, no resuelto acá |
| CSP rompe Flutter web por el JS inline | App no arranca en producción | Se prueba en staging antes de la raíz |

---

## 11. Etapas

| # | Etapa | Entregable verificable |
|---|---|---|
| 0 | Instalar Flutter, `flutter build web` de base, medir bundle | Lista confirmada de qué falla realmente vs. §2 |
| 1 | Desbloquear build: B1–B4, purga de nativo y deps (§3.1, §3.2) | `flutter build web` compila y la app arranca |
| 2 | **Spike del escáner** (§4) | Números de latencia en iPhone y Android; decisión go/no-go |
| 3 | Capa de plataforma (§3.3) + token de dispositivo (§6) | Cola en IndexedDB, conectividad y auth de puerta funcionando |
| 4 | Capa PWA (§7) | App instalable, con splash y flujo de actualización |
| 5 | Deploy (§8) | PWA en producción con la matriz de §9 pasada |

Cada etapa compila y se puede probar sola. Si el proyecto se detiene en cualquier punto,
lo entregado hasta ahí funciona.
