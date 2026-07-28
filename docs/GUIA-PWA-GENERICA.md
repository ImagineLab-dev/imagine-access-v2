# PWA instalable en Android y iPhone — guía genérica

Los pasos, sin depender de ningún framework. Sirve para React, Vue, Angular, HTML plano o
lo que sea: lo que hace instalable a una PWA es el navegador, no la herramienta con la que
se construyó.

Requisito previo innegociable: **HTTPS**. Sin certificado válido no hay service worker ni
instalación. `localhost` es la única excepción, para desarrollo.

---

## 1. Iconos

Cinco archivos, desde un PNG cuadrado de 1024×1024:

| Archivo | Tamaño | Para qué |
|---|---|---|
| `icon-192.png` | 192 | Uso general |
| `icon-512.png` | 512 | Splash y tiendas |
| `icon-maskable-192.png` | 192 | Android con forma adaptable |
| `icon-maskable-512.png` | 512 | Android con forma adaptable |
| `apple-touch-icon.png` | 180 | iOS, que **ignora el manifest** |

Dos cosas que rompen si se ignoran:

**Sin canal alfa.** Componer sobre un color sólido antes de guardar. Varios lanzadores
pintan la transparencia de negro.

**Los maskable necesitan margen.** El contenido tiene que ocupar ~72% del lienzo: los
lanzadores recortan hasta un 10% por lado para adaptarlo a su forma (círculo, cuadrado
redondeado, gota). Un icono a sangre queda con el logo cortado.

---

## 2. manifest.json

```json
{
  "id": "/",
  "name": "Nombre completo de la app",
  "short_name": "Corto",
  "description": "Una línea de qué hace.",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "display_override": ["standalone", "minimal-ui"],
  "orientation": "portrait-primary",
  "background_color": "#0B0F16",
  "theme_color": "#0B0F16",
  "lang": "es",
  "icons": [
    { "src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "icons/icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "icons/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ],
  "shortcuts": [
    { "name": "Acción principal", "url": "/accion", "icons": [{ "src": "icons/icon-192.png", "sizes": "192x192" }] }
  ],
  "screenshots": [
    { "src": "screenshots/movil.png", "sizes": "1080x1920", "type": "image/png", "form_factor": "narrow" },
    { "src": "screenshots/escritorio.png", "sizes": "1920x1080", "type": "image/png", "form_factor": "wide" }
  ]
}
```

Lo que más impacto tiene:

- **`id`** fija la identidad. Sin él, cambiar `start_url` crea una app "nueva" y el usuario
  termina con dos iconos.
- **`background_color`** es lo que se ve mientras carga. Si no coincide con la marca, el
  arranque parpadea en otro color.
- **`screenshots`** habilitan el diálogo de instalación enriquecido de Chrome. Sin ellos
  sale una barra genérica y mucha menos gente instala.
- **`scope`** limita qué URLs quedan dentro de la app. Salir del scope abre el navegador.

Enlazarlo en el HTML:

```html
<link rel="manifest" href="/manifest.json">
```

---

## 3. Meta tags

```html
<meta name="viewport" content="width=device-width, initial-scale=1.0,
      maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
<meta name="theme-color" content="#0B0F16">

<!-- iOS ignora casi todo el manifest y usa estos -->
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Nombre corto">
<link rel="apple-touch-icon" href="/icons/apple-touch-icon.png">
```

`maximum-scale=1.0` evita el zoom accidental con el teléfono en la mano.
`viewport-fit=cover` usa el área completa en iPhone con notch.

---

## 4. Service worker

Sin esto **no es una PWA**: es una web con un icono en el escritorio.

```js
// sw.js
const CACHE = 'app-v1';                    // cambiar en cada deploy
const SHELL = ['/', '/app.js', '/app.css', '/manifest.json', '/icons/icon-192.png'];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // 'reload' salta la caché HTTP: sin esto se precachea una versión vieja
    // del propio archivo que se quiere actualizar.
    await cache.addAll(SHELL.map((f) => new Request(f, { cache: 'reload' })));
  })());
  // NO skipWaiting acá: se espera a que el usuario acepte (ver punto 5).
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const n of await caches.keys()) {
      if (n !== CACHE) await caches.delete(n);   // limpiar versiones viejas
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // La API NUNCA se cachea. Servir datos viejos suele ser peor que no
  // servir nada, y es la causa de bugs imposibles de reproducir.
  if (url.pathname.startsWith('/api/')) return;
  if (url.origin !== self.location.origin) return;

  // Navegación: red primero, caché de respaldo. El fallback a '/' es lo que
  // hace que las rutas internas funcionen sin conexión.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).catch(async () => (await caches.match(req)) || caches.match('/'))
    );
    return;
  }

  // Estáticos: caché primero.
  event.respondWith((async () => {
    const hit = await caches.match(req);
    if (hit) return hit;
    const res = await fetch(req);
    if (res.ok && res.type === 'basic') (await caches.open(CACHE)).put(req, res.clone());
    return res;
  })());
});

self.addEventListener('message', (e) => {
  if (e.data?.type === 'SKIP_WAITING') self.skipWaiting();
});
```

Conviene generar la lista `SHELL` y el nombre del caché **en el build**, a partir de un
hash del contenido. Mantenerlos a mano garantiza que algún día se olviden.

---

## 5. Flujo de actualización

Sin esto un dispositivo queda con una versión vieja **para siempre**.

```js
navigator.serviceWorker.register('/sw.js').then((reg) => {
  if (reg.waiting) mostrarBanner(reg.waiting);

  reg.addEventListener('updatefound', () => {
    const nuevo = reg.installing;
    nuevo?.addEventListener('statechange', () => {
      // 'installed' CON un controller activo = hay versión nueva esperando.
      // Sin controller es la primera instalación: no hay nada que avisar.
      if (nuevo.state === 'installed' && navigator.serviceWorker.controller) {
        mostrarBanner(nuevo);
      }
    });
  });

  // Para dispositivos que quedan abiertos días sin recargar.
  setInterval(() => reg.update().catch(() => {}), 60 * 60 * 1000);
});

let recargando = false;
navigator.serviceWorker.addEventListener('controllerchange', () => {
  if (recargando) return;        // Chrome lo dispara más de una vez
  recargando = true;
  location.reload();
});

// El banner llama: worker.postMessage({ type: 'SKIP_WAITING' })
```

**Banner en vez de recarga automática.** Recargar sola en medio de una operación —un
formulario a medio llenar, una transacción— es peor que esperar.

---

## 6. Cabeceras de caché

Es la trampa más cara, y la que menos se revisa.

Si un archivo **no lleva un hash en el nombre**, no puede ser `immutable`. Marcarlo así
significa que el navegador nunca lo vuelve a pedir y **ningún deploy llega a los usuarios
ya instalados**. El síntoma es desconcertante: el archivo correcto está en el servidor,
verificado con `curl`, pero el navegador sigue con el viejo.

```apache
# Los que definen qué versión corre: nunca se cachean
<FilesMatch "^(index\.html|sw\.js|manifest\.json)$">
  Header set Cache-Control "no-cache, no-store, must-revalidate"
</FilesMatch>

# Nombres estables con contenido cambiante: revalidar
<FilesMatch "\.(js|css|json|wasm)$">
  Header set Cache-Control "no-cache"
</FilesMatch>

# SOLO lo que lleva la versión o el hash EN EL NOMBRE
<FilesMatch "\.[a-f0-9]{8,}\.(js|css)$">
  Header set Cache-Control "public, max-age=31536000, immutable"
</FilesMatch>

# Imágenes y fuentes: unas horas no rompe nada
<FilesMatch "\.(png|jpe?g|svg|webp|woff2?)$">
  Header set Cache-Control "public, max-age=86400"
</FilesMatch>
```

`no-cache` **no** significa "no cachear": guarda el archivo y pregunta si cambió. Con ETag
son respuestas 304 de pocos bytes. El offline lo resuelve el service worker, no esta capa.

Y si la app tiene rutas del lado del cliente, el fallback SPA o refrescar da 404:

```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} -f [OR]
RewriteCond %{REQUEST_FILENAME} -d
RewriteRule ^ - [L]
RewriteRule ^ index.html [L]
```

Equivalente en nginx:

```nginx
location / { try_files $uri $uri/ /index.html; }
location = /sw.js { add_header Cache-Control "no-cache, no-store, must-revalidate"; }
```

---

## 7. Pantalla de carga

El fondo por defecto de una página es **blanco**. Si la app tarda en arrancar, el usuario
ve un destello blanco y después un salto brusco al tema oscuro.

```css
html, body { margin: 0; background-color: #0B0F16; }   /* lo primero de todo */
```

Y quitar el splash **cuando la app dibuja**, no en el evento `load` —que ocurre mucho antes
de que haya algo en pantalla—, observando la aparición del primer contenido real:

```js
new MutationObserver((_, obs) => {
  if (document.querySelector('#app > *')) {   // ajustar al selector real
    obs.disconnect();
    // Dos frames: el elemento existe un instante antes de estar pintado, y sin
    // esta espera se alcanza a ver un fotograma en blanco.
    requestAnimationFrame(() => requestAnimationFrame(ocultarSplash));
  }
}).observe(document.body, { childList: true, subtree: true });
```

Conviene un `setTimeout` de respaldo: si la app falla al arrancar, es preferible mostrar el
error que dejar el splash para siempre.

---

## 8. Invitación a instalar — dos caminos que NO son intercambiables

### Android y escritorio

```js
let evento = null;

window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();          // sin esto sale la barra genérica del navegador
  evento = e;
  mostrarBotonInstalar();
});

async function instalar() {
  if (!evento) return;
  evento.prompt();
  const { outcome } = await evento.userChoice;
  if (outcome !== 'accepted') noInsistirPorUnTiempo();
  evento = null;
}

window.addEventListener('appinstalled', () => ocultarBoton());
```

### iOS

**No dispara `beforeinstallprompt` NUNCA, en ningún navegador.** Chrome, Edge y Firefox en
iPhone son WebKit por dentro: todos exigen el mismo gesto manual.

Por eso **la detección va por sistema operativo, no por marca de navegador**. Preguntar "¿es
Chrome?" da verdadero en iPhone y mostraría un botón que no puede funcionar.

```js
function esIOS() {
  if (/iphone|ipod|ipad/i.test(navigator.userAgent)) return true;
  // iPadOS 13+ se presenta como Mac; la pantalla táctil lo delata.
  return navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
}

function yaInstalada() {
  return window.navigator.standalone === true ||                 // iOS
         window.matchMedia('(display-mode: standalone)').matches; // el resto
}

if (esIOS() && !yaInstalada()) mostrarInstruccionesIOS();
```

Las instrucciones tienen que decir **"el botón Compartir del navegador"**. Sin esa
aclaración mucha gente busca un botón de compartir dentro de la app y no lo encuentra. Y el
ícono conviene dibujarlo en SVG: el emoji cambia según la versión de iOS y no se parece al
botón real.

```
Tocá el botón Compartir del navegador  ⬆️  y elegí «Añadir a pantalla de inicio».
```

**En iOS instalar no es opcional si guardás datos.** Una PWA en la pantalla de inicio queda
**exenta del borrado a los 7 días de inactividad** que Safari aplica a los sitios normales.
Sin instalar, lo que haya en IndexedDB o localStorage puede desaparecer solo entre un uso y
el siguiente.

---

## 9. Checklist de verificación

Nada de esto se comprueba leyendo código. Hay que abrir el navegador:

- [ ] DevTools → Application → **Manifest**: sin errores, iconos visibles
- [ ] DevTools → Application → **Service Workers**: activado y controlando la página
- [ ] Lighthouse → categoría PWA: instalable
- [ ] Consola limpia: sin errores de CSP ni de MIME type
- [ ] **Instalar, cerrar, modo avión, abrir**: tiene que cargar
- [ ] **Desplegar un cambio y confirmar que llega** a un dispositivo ya instalado
- [ ] `curl -sI .../app.js | grep -i cache-control` — que no diga `immutable` si el nombre
      no lleva hash
- [ ] Refrescar en una ruta interna: no debe dar 404
- [ ] **iPhone real**: el aviso aparece y las instrucciones se entienden

Los dos del medio son los que más se saltean y los que fallan.

---

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| No aparece la opción de instalar | Falta HTTPS, el manifest tiene errores, o no hay service worker |
| Instala pero no abre sin conexión | El service worker no precachea el shell |
| Los deploys no llegan a quien ya instaló | `immutable` sobre archivos sin hash en el nombre |
| Se ve un icono negro | Los PNG tienen canal alfa |
| El logo sale cortado en Android | Los maskable no dejan el margen del 20% |
| Refrescar da 404 | Falta el fallback SPA en el servidor |
| Destello blanco al abrir | El fondo no está pintado desde el primer byte |
| El botón instalar no hace nada en iPhone | Se detectó por navegador y no por sistema operativo |
