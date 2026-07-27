# Auditoría de UX, coherencia y bugs

**Fecha:** 2026-07-27
**Alcance:** app completa en producción sobre Supabase autohospedado.

---

## 1. El hallazgo principal: no hay onboarding

**No existe ningún onboarding, tour, tutorial ni guía de primer uso.** La búsqueda de
`onboarding|tutorial|walkthrough|firstRun|showcase` en todo `lib/` no devuelve nada.

Qué le pasa hoy a alguien que se registra:

1. Verifica su email y entra.
2. Cae en un dashboard vacío: cero eventos, cero tickets, métricas en cero.
3. Los estados vacíos son **solo texto**: `noEventsFound`, `noTicketsFound`. Sin botón,
   sin explicación, sin siguiente paso.
4. Nada le dice que lo primero es crear un evento, ni que sin evento activo el resto del
   sistema no hace nada.

Es el mayor obstáculo para que sea "intuitivo". Un sistema de control de acceso tiene un
orden obligatorio —evento → tipos de ticket → equipo → tickets → escanear— y hoy el
usuario tiene que deducirlo.

**Propuesta, de mayor a menor impacto:**

| # | Qué | Por qué |
|---|---|---|
| 1 | Estados vacíos con acción: "Todavía no tenés eventos" + botón **Crear evento** | Es el arreglo más barato y resuelve el 80% del problema |
| 2 | Checklist de primeros pasos en el dashboard, que se autocompleta | Hace visible el orden obligatorio sin bloquear |
| 3 | Tour de 3-4 pasos la primera vez, salteable | Para roles que no eligieron usar el sistema, como el personal de puerta |

## 2. Bugs de internacionalización

La app declara 3 idiomas con 526 claves sincronizadas, pero hay fugas.

### 2.1 Los errores de red siempre salen en español

`ErrorHandler.analyzeError()` devuelve mensajes **hardcodeados en español**:

```dart
message: 'Sin conexión a internet. Verifique su red.'
message: 'La operación tardó demasiado. Intente nuevamente.'
message: 'Sesión expirada. Por favor inicie sesión nuevamente.'
```

Existe `ErrorHandler.localizedMessage(context, type)`, que sí traduce — pero solo se usa
en `reset_password_screen.dart` y dentro de `showErrorSnackBar`. En el resto de la app,
un usuario en inglés o portugués recibe errores en español.

**Arreglo:** que `NetworkError.message` deje de existir como texto y que todos los puntos
de presentación usen `localizedMessage`.

### 2.2 Excepción cruda mostrada al usuario

`create_ticket_wizard.dart:174` hace:

```dart
content: Text(e.toString()),
```

Eso puede volcar un error técnico de PostgREST en pantalla durante la creación de un
ticket. Ya pasó en esta sesión: `PGRST200: Could not find a relationship...` es
exactamente el tipo de texto que terminaría a la vista.

### 2.3 Excepciones en español desde los repositorios

`settings_repository.dart` lanza mensajes fijos en español que llegan a la UI:

- `'Error inesperado al actualizar moneda'` (:68)
- `'Error al eliminar perfil'` (:191)
- `'Error al registrar dispositivo'` (:250)

## 3. Coherencia de navegación

El menú lateral tiene 3 ítems (Panel de Control, Eventos, Configuración). El escáner, la
creación de tickets y la lista de tickets **solo se alcanzan como tarjetas del dashboard**,
que además cambian según el rol.

Es un patrón defendible —pone lo importante donde el usuario aterriza— pero tiene un costo:
estando en cualquier otra pantalla, volver al escáner obliga a pasar por el dashboard. Para
alguien en la puerta que alterna entre escanear y buscar por documento, son dos toques de
más en cada ida y vuelta.

**Propuesta:** barra inferior de navegación para el rol `door` con Escáner y Buscar
documento siempre visibles.

## 4. Bugs ya corregidos en esta sesión

Se listan porque explican decisiones del código y porque varios solo aparecieron
probando en un navegador real:

| Bug | Efecto | Estado |
|---|---|---|
| `main.dart.js` con `immutable, 1 año` y nombre fijo | Ningún deploy llegaba a los usuarios | Corregido |
| Falta FK `tickets` → `users_profile` | Dashboard con 400 (`PGRST200`) | Corregido |
| Sonda de conectividad sin apikey | 401 repetido en consola | Corregido |
| Sin splash web, fondo blanco | Destello blanco de segundos al abrir | Corregido |
| CanvasKit desde `gstatic.com` | La app no renderizaba con la CSP puesta | Corregido |
| `dart:io` en el chequeo de conexión | Reportaba "sin conexión" siempre; la cola nunca sincronizaba | Corregido |
| `organizations` creada después de usarse | El esquema entero revertía y quedaba una base vacía | Corregido |

## 5. Riesgos abiertos

- **Validación offline sin detección de duplicados.** Sin conexión, `validate_ticket` se
  encola y el escáner acepta. El mismo QR puede entrar dos veces hasta que sincronice.
  Es preexistente y está documentado, pero en un evento real es un agujero de ingresos.
- **Sin monitoreo.** Si Postgres se cae durante un evento, nadie se entera.
- **Backups en el mismo disco que la base.**
- **PIN de dispositivo en localStorage**, legible por XSS.
- **`get_device_tickets` y `get_authorized_tickets` tienen sobrecargas duplicadas** (2 y 3
  versiones). PostgREST puede fallar con "function is not unique" si las firmas colisionan.
  No se manifestó todavía; conviene limpiar.

## 6. Orden sugerido

1. Estados vacíos con acción — barato, alto impacto
2. Unificar los mensajes de error por `localizedMessage` y sacar el `e.toString()`
3. Checklist de primeros pasos
4. Navegación inferior para el rol de puerta
5. Limpiar las sobrecargas de funciones SQL
