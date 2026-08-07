/**
 * Service worker de Imagine Access.
 *
 * Existe porque Flutter dejó de generar uno que cachee: desde 3.29 el
 * `flutter_service_worker.js` que produce el build es una lápida de ~800 bytes
 * que llama `registration.unregister()` para desinstalarse
 * (github.com/flutter/flutter/issues/156910). Sin esto la app no abre sin
 * internet, que es justo el escenario de una puerta con wifi malo.
 *
 * La línea PRECACHE_MANIFEST la reescribe `tool/build_web.py` en cada build con
 * la lista real de archivos y un hash del contenido. No editarla a mano.
 */
'use strict';

// __PRECACHE_MANIFEST__
const PRECACHE_MANIFEST = { version: 'dev', files: [] };

const CACHE_NAME = `imagine-access-${PRECACHE_MANIFEST.version}`;

/**
 * Orígenes cuyas respuestas NUNCA se cachean.
 *
 * Servir datos viejos en un sistema de validación de tickets es peor que no
 * servir nada: un ticket ya usado podría aparecer como válido. Toda llamada a
 * Supabase va siempre a la red, y si falla, falla — la cola offline de la app
 * es la que se encarga de reintentarla.
 */
function isApiRequest(url) {
  return url.hostname.endsWith('.supabase.co') ||
         url.pathname.startsWith('/auth/v1/') ||
         url.pathname.startsWith('/rest/v1/') ||
         url.pathname.startsWith('/functions/v1/');
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    // `PRECACHE_MANIFEST.files` es solo el SHELL liviano, NO todo el build.
    // `main.dart.js` (~5 MB) queda afuera a propósito: bloquear el install con
    // él hacía que en iPhone la instalación no terminara antes de que iOS
    // suspenda la app, el SW nuevo nunca quedara "esperando", y la
    // actualización no se aplicara sola —el "si o si hay que forzar
    // actualización"—. main.dart.js se cachea igual en el handler de `fetch`
    // (caché en runtime) porque la página lo pide al cargar. Ver
    // `tool/build_web.py` → INSTALL_EXCLUDE.
    //
    // `reload` evita que el propio caché HTTP del navegador nos devuelva una
    // versión vieja de un archivo justo mientras estamos precacheando.
    await cache.addAll(
      PRECACHE_MANIFEST.files.map((f) => new Request(f, { cache: 'reload' })),
    );
  })());
  // No se llama skipWaiting acá a propósito: el SW nuevo espera a que el
  // usuario acepte actualizar. En un dispositivo de puerta, recargar sin aviso
  // en mitad de una validación es peor que esperar.
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(
      names
        .filter((n) => n.startsWith('imagine-access-') && n !== CACHE_NAME)
        .map((n) => caches.delete(n)),
    );
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  if (isApiRequest(url)) return;      // a la red siempre, sin tocar caché
  if (url.origin !== self.location.origin) return;

  // Navegación: red primero para tomar despliegues nuevos apenas salen, con el
  // shell cacheado como respaldo. El fallback a '/' es lo que hace que las
  // rutas del router (/scanner, /tickets, /ticket/:id) funcionen offline.
  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        return await fetch(request);
      } catch (_) {
        const cache = await caches.open(CACHE_NAME);
        return (await cache.match(request)) ||
               (await cache.match('/')) ||
               Response.error();
      }
    })());
    return;
  }

  // Estáticos: caché primero. Son inmutables dentro de una versión del SW —
  // cuando cambian, cambia el hash del manifest y con él el nombre del caché.
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const hit = await cache.match(request);
    if (hit) return hit;

    try {
      const response = await fetch(request);
      if (response && response.status === 200 && response.type === 'basic') {
        cache.put(request, response.clone());
      }
      return response;
    } catch (err) {
      return Response.error();
    }
  })());
});

// Canal con la app: permite preguntar la versión y forzar la activación cuando
// el usuario acepta actualizar desde el banner.
self.addEventListener('message', (event) => {
  if (!event.data) return;
  if (event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  } else if (event.data.type === 'GET_VERSION') {
    event.ports[0]?.postMessage({ version: PRECACHE_MANIFEST.version });
  }
});
