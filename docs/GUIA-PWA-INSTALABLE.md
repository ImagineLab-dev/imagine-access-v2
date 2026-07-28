# Cómo hacer una PWA Flutter instalable en Android y iPhone

Todo lo que hizo falta en Imagine Access, en orden, con el porqué de cada cosa.
Reutilizable en cualquier proyecto Flutter web.

Casi nada de esto está en la documentación oficial de Flutter, y varias piezas solo
aparecieron probando en un dispositivo real.

---

## 0. Lo primero: Flutter ya no genera un service worker

Desde 3.29 el `flutter_service_worker.js` que produce el build es una lápida de ~800 bytes
cuyo único trabajo es **auto-desinstalarse**:

```js
self.addEventListener('activate', (event) => {
  await self.registration.unregister();
```

(ver `github.com/flutter/flutter/issues/156910`)

Sin escribir uno propio, la app **no abre sin conexión**. Es el punto de partida: sin
service worker es una web instalable, no una PWA.

---

## 1. Flags de build que cambian todo

```bash
flutter build web --release \
  --no-web-resources-cdn \
  --pwa-strategy=none \
  --dart-define=API_URL=... --dart-define=API_KEY=...
```

**`--no-web-resources-cdn`** — Flutter carga CanvasKit desde `www.gstatic.com` **por
defecto**. Sin este flag la app no funciona offline y una CSP estricta la bloquea entera:
pantalla en blanco sin error obvio. Es el equivalente a que el motor de render viva en
internet.

**`--pwa-strategy=none`** — evita que `flutter_bootstrap.js` intente registrar el service
worker que ya no existe. Si el archivo falta y hay fallback SPA, el servidor devuelve
`index.html` y el navegador rechaza el registro con `unsupported MIME type ('text/html')`.

**`--dart-define`** — nunca un `.env` como asset. En web los assets de Flutter se sirven
por HTTP: un `.env` empaquetado queda público en `/assets/.env`.

---

## 2. Iconos

Cuatro archivos, generados desde un PNG de 1024×1024:

| Archivo | Tamaño | Propósito |
|---|---|---|
| `Icon-192.png` | 192 | `any` |
| `Icon-512.png` | 512 | `any` |
| `Icon-maskable-192.png` | 192 | `maskable` |
| `Icon-maskable-512.png` | 512 | `maskable` |
| `apple-touch-icon-180.png` | 180 | iOS ignora el manifest y usa este |

Dos detalles que rompen si se ignoran:

**Sin canal alfa.** Componer sobre el color de marca antes de guardar. Varios lanzadores
renderizan la transparencia como negro.

**Los maskable necesitan margen.** El contenido debe ocupar ~72% del lienzo: los
lanzadores recortan hasta un 10% por lado para adaptarlo a su forma. Un icono a sangre
queda con el logo cortado.

```python
def maskable(img, size, bg):
    canvas = Image.new('RGBA', (size, size), bg)
    inner = int(size * 0.72)
    canvas.alpha_composite(img.resize((inner, inner), Image.LANCZOS),
                           ((size - inner) // 2,) * 2)
    return canvas.convert('RGB')   # sin alfa
```

---

## 3. manifest.json

Lo que Flutter genera por defecto no alcanza. Lo que importa de verdad:

```json
{
  "id": "/",
  "name": "Nombre completo",
  "short_name": "Corto",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "display_override": ["standalone", "minimal-ui"],
  "background_color": "#0B0F16",
  "theme_color": "#0B0F16",
  "icons": [ ... ],
  "shortcuts": [ ... ],
  "screenshots": [ ... ]
}
```

- **`id`** fija la identidad de la app. Sin él, cambiar `start_url` crea una app "nueva" y
  el usuario termina con dos iconos.
- **`background_color`** es lo que se ve mientras carga. Si queda el azul de Flutter por
  defecto, el arranque parpadea en un color que no es el de la marca.
- **`screenshots`** son lo que habilita el diálogo de instalación enriquecido de Chrome.
  Sin ellos aparece una barra genérica y mucho menos gente instala.
- **`shortcuts`** son las acciones al mantener presionado el icono.

---

## 4. El service worker

Precachear el shell, red primero para navegación, y **nunca cachear la API**.

```js
self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    // 'reload' salta la caché HTTP del navegador: sin esto se precachea
    // una versión vieja del propio archivo que se quiere actualizar.
    await cache.addAll(FILES.map((f) => new Request(f, { cache: 'reload' })));
  })());
  // NO skipWaiting acá: se espera a que el usuario acepte.
});
```

**Tres decisiones que importan:**

**No cachear la API.** En un sistema transaccional servir datos viejos es peor que no
servir nada. Solo el shell.

**No precachear `canvaskit/`.** Flutter empaqueta **seis variantes** del renderer
(`canvaskit`, `chromium`, `skwasm`, `skwasm_heavy`, `wimp`,
`experimental_webparagraph`) que suman ~28 MB, y el navegador descarga **una**.
Precachearlas todas convierte la primera visita en 34 MB. Dejando que el handler
cache-first guarde la que efectivamente se pide, el precache baja a ~5 MB. La
contrapartida: la app funciona offline recién después de una carga online exitosa — que es
el flujo real de todos modos.

**Fallback de navegación a `/`.** Es lo que hace que las rutas del router funcionen sin
conexión.

También conviene borrar del build los `*.symbols` — son ~8 MB de símbolos de depuración
que no se sirven.

---

## 5. Flujo de actualización

Sin esto, un dispositivo queda con una versión vieja para siempre.

```js
registration.addEventListener('updatefound', () => {
  const installing = registration.installing;
  installing.addEventListener('statechange', () => {
    // 'installed' CON un controller activo = hay versión nueva esperando.
    // Sin controller es la primera instalación: no hay nada que avisar.
    if (installing.state === 'installed' && navigator.serviceWorker.controller) {
      mostrarBanner(installing);   // el usuario decide cuándo
    }
  });
});

let recargando = false;
navigator.serviceWorker.addEventListener('controllerchange', () => {
  if (recargando) return;          // Chrome lo dispara más de una vez
  recargando = true;
  window.location.reload();
});
```

Banner en vez de recarga automática: recargar sola en medio de una operación es peor que
esperar. Y conviene un `registration.update()` horario, para dispositivos que quedan
abiertos días.

---

## 6. Cabeceras de caché — la trampa más cara

**Un build de Flutter web casi no tiene nombres con hash de contenido.** `main.dart.js` y
`flutter_bootstrap.js` se llaman igual en cada deploy, con contenido distinto.

```apache
# MAL: el navegador nunca los vuelve a pedir. Ningún deploy llega a los usuarios.
<FilesMatch "\.(js|css|wasm)$">
  Header set Cache-Control "public, max-age=31536000, immutable"
</FilesMatch>
```

Esto pasó de verdad: un fix desplegado y verificado en el servidor seguía sin aparecer en
el navegador. Lo correcto:

```apache
<FilesMatch "\.(js|css|wasm|html|json|bin)$">
  Header set Cache-Control "no-cache"          # revalida, no "no cachea"
</FilesMatch>

<FilesMatch "^(index\.html|sw\.js|manifest\.json)$">
  Header set Cache-Control "no-cache, no-store, must-revalidate"
</FilesMatch>

# Solo lo que lleva la versión EN EL NOMBRE
<FilesMatch "-[0-9]+\.[0-9]+\.[0-9]+\.min\.js$">
  Header set Cache-Control "public, max-age=31536000, immutable"
</FilesMatch>
```

`no-cache` no significa "no cachear": guarda el archivo y pregunta si cambió. Con ETag son
304 de pocos bytes. El offline lo resuelve el service worker, no esta capa.

Y el fallback SPA, o refrescar en cualquier ruta da 404:

```apache
RewriteCond %{REQUEST_FILENAME} -f [OR]
RewriteCond %{REQUEST_FILENAME} -d
RewriteRule ^ - [L]
RewriteRule ^ index.html [L]
```

---

## 7. Pantalla de carga

El fondo por defecto de una página es **blanco** y el bundle pesa varios MB: el arranque es
un destello blanco de segundos seguido de un salto brusco.

```css
html, body { background-color: #0B0F16; }   /* antes que cualquier otra cosa */
```

Y quitar el splash **cuando Flutter dibuja**, no en el evento `load` —que ocurre mucho
antes de que haya algo en pantalla—, observando la aparición de su superficie:

```js
new MutationObserver(() => {
  if (document.querySelector('flutter-view, flt-glass-pane')) ocultar();
}).observe(document.body, { childList: true, subtree: true });
```

Más dos `requestAnimationFrame` antes de ocultar: el elemento existe un instante antes de
tener contenido, y sin esa espera se ve un fotograma negro.

---

## 8. Instalación: dos caminos que NO son intercambiables

**Android y escritorio** disparan `beforeinstallprompt`. Se guarda el evento y se ofrece un
botón propio:

```js
window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();          // sin esto sale la barra genérica del navegador
  eventoGuardado = e;
  mostrarBotonInstalar();
});
```

**iOS no lo dispara NUNCA, en ningún navegador.** Chrome, Edge y Firefox en iPhone son
WebKit por dentro: todos exigen el mismo gesto manual. Por eso **la detección va por
sistema operativo, no por marca de navegador** — mirar "es Chrome" da verdadero en iPhone y
mostraría un botón que no puede funcionar.

```js
function esIOS() {
  if (/iphone|ipod|ipad/i.test(navigator.userAgent)) return true;
  // iPadOS 13+ se presenta como Mac; la pantalla táctil lo delata.
  return navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
}

function yaInstalada() {
  return window.navigator.standalone === true ||             // iOS
         window.matchMedia('(display-mode: standalone)').matches;
}
```

En iOS hay que **mostrar instrucciones**: "tocá el botón Compartir **del navegador** y
elegí Añadir a pantalla de inicio". Aclarar "del navegador" no es un detalle: mucha gente
busca un botón de compartir dentro de la app. Y el ícono conviene dibujarlo en SVG, no como
emoji — el emoji cambia según la versión de iOS y no se parece al botón real.

**En iOS instalar no es opcional.** Una PWA agregada a la pantalla de inicio queda **exenta
del borrado de datos a los 7 días de inactividad** que Safari aplica a los sitios normales.
Sin instalar, lo que haya en IndexedDB o localStorage puede desaparecer solo.

---

## 9. Meta tags de iOS

```html
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Nombre corto">
<link rel="apple-touch-icon" href="icons/Icon-192.png">
<meta name="viewport" content="width=device-width, initial-scale=1.0,
      maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
```

`maximum-scale=1.0` evita el zoom accidental con el teléfono en la mano. `viewport-fit=cover`
usa el área completa en iPhone con notch.

---

## 10. CSP

```
default-src 'self';
script-src 'self' 'wasm-unsafe-eval';
connect-src 'self' https://TU-API;
img-src 'self' data: blob:;
font-src 'self' data: https://fonts.gstatic.com;
worker-src 'self' blob:;
```

`'wasm-unsafe-eval'` lo exige CanvasKit: sin eso no instancia su módulo WebAssembly y la
app no dibuja nada.

`fonts.gstatic.com` es una concesión: CanvasKit baja Roboto de ahí como fuente de respaldo.
Se evita empaquetando la fuente como asset del proyecto.

---

## Checklist de verificación

Nada de esto se verifica leyendo código. Hay que abrir el navegador:

- [ ] DevTools → Application → Manifest: sin errores, iconos visibles
- [ ] DevTools → Application → Service Workers: activado
- [ ] Network filtrando `gstatic`: **cero requests** (si aparecen, falta `--no-web-resources-cdn`)
- [ ] Consola: sin errores de CSP ni de MIME type
- [ ] Instalar, cerrar, **modo avión**, abrir: tiene que cargar
- [ ] Desplegar un cambio y confirmar que **llega** al dispositivo ya instalado
- [ ] `curl -sI .../main.dart.js | grep -i cache-control` → `no-cache`
- [ ] Refrescar en una ruta interna: no debe dar 404
- [ ] iPhone real: el aviso de instalación aparece y el texto se entiende

El anteúltimo y el antepenúltimo son los que más se saltean, y son los que fallan.
