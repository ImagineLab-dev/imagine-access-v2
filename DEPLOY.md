# Deploy — Imagine Access PWA

**Destino:** `https://imaginecloud.digital`
**Hosting:** Hostinger compartido, cuenta `u475398526`, dominio addon.
**Raíz en el servidor:** `/home/u475398526/domains/imaginecloud.digital/public_html`

---

## Compilar y empaquetar

```bash
python tool/build_web.py --url https://TU-PROYECTO.supabase.co --key TU_ANON_KEY
python tool/package_web.py
```

Sale un zip en `dist/imagineaccess_YYYYMMDD_HHMMSS.zip` (~13 MB).

`build_web.py` hace lo que `flutter build web` no:

- Inyecta las credenciales por `--dart-define`. Nunca como asset: en web los assets se
  sirven por HTTP y un `.env` empaquetado queda público en `/assets/.env`.
- Reescribe el precache manifest de `sw.js` con la lista real de archivos y un hash de su
  contenido. Ese hash nombra el caché, así que cada deploy invalida el anterior solo.
- Borra el `flutter_service_worker.js` de Flutter, que desde 3.29 es una lápida que llama
  `registration.unregister()` y desregistraría el nuestro.
- Descarta ~8 MB de símbolos de depuración.
- Sustituye el host de Supabase en la CSP del `.htaccess`.

`package_web.py` verifica que estén los archivos críticos antes de dejarte subir algo roto.

---

## Subir

### Paso bloqueante: respaldar lo que hay

La raíz tiene hoy un WordPress. Está prácticamente vacío —tema por defecto, un post
"Hello world!", WooCommerce sin poblar— **pero tiene configurada una pasarela Pagopar**,
que puede ser trabajo real de alguien.

Antes de pisar nada: hPanel → Archivos → Copias de seguridad → generar y **descargar**
una copia de archivos y base de datos. Verificá que el archivo bajó y pesa lo esperado.
Una copia que no descargaste no es un respaldo.

### Opción A — MCP de Hostinger

El MCP ya está configurado en `~/.claude.json` con el token correcto. Requiere reiniciar
Claude Code para que tome efecto. Después:

> Deploy el zip de `dist/` a imaginecloud.digital

### Opción B — hPanel a mano

1. hPanel → Archivos → Administrador de archivos
2. Entrar a `domains/imaginecloud.digital/public_html`
3. Borrar el contenido del WordPress (ya respaldado)
4. Subir el zip y extraerlo ahí
5. Confirmar que `.htaccess` quedó en la raíz — los administradores de archivos suelen
   ocultar los archivos que empiezan con punto; hay que activar "mostrar ocultos"

---

## Verificar después de subir

```bash
curl -sI https://imaginecloud.digital/ | head -1                    # 200
curl -s -o /dev/null -w "%{http_code}\n" https://imaginecloud.digital/scanner   # 200, no 404
curl -s -o /dev/null -w "%{http_code}\n" https://imaginecloud.digital/assets/.env  # 404
curl -sI https://imaginecloud.digital/sw.js | grep -i cache-control  # no-cache
```

`/scanner` devolviendo 404 significa que el `.htaccess` no está tomando efecto y el
fallback SPA no funciona: refrescar en cualquier ruta va a romper.

Y en el navegador, con DevTools:

- Application → Manifest: sin errores, íconos visibles
- Application → Service Workers: `sw.js` activado
- Network filtrando `unpkg`: **cero requests**
- Instalar la app, cerrarla, poner el equipo en modo avión y abrirla: debe cargar

Ese último es el que prueba que el service worker hace su trabajo. Ojo: **funciona recién
después de una carga online exitosa**, porque `canvaskit/` se cachea en tiempo de
ejecución y no en el precache — Flutter empaqueta 6 variantes del renderer (~28 MB) y el
navegador baja una sola.

---

## Configuración del backend

Aparte del deploy, en Supabase:

```bash
supabase secrets set SMTP_USER=tickets@imaginecloud.digital
supabase secrets set 'SMTP_PASS=...'          # comillas simples: la password lleva # y *
supabase secrets set ALLOWED_ORIGIN=https://imaginecloud.digital
```

`ALLOWED_ORIGIN` no es opcional: `_shared/cors.ts` lanza si no está seteado en un entorno
que no sea local, y las ~17 Edge Functions que llama el cliente dejarían de responder.

---

## Pendientes conocidos

- **CORS de origen único.** `_shared/cors.ts` acepta un solo `ALLOWED_ORIGIN`, así que no
  podés tener producción y `localhost` a la vez. Para desarrollo local hay que cambiarlo a
  una allowlist.
- **Falta DKIM** en `imaginecloud.digital`. Hay MX y SPF, pero sin DKIM y con DMARC en
  `p=none`, los tickets tienen bastante chance de caer en spam. Se activa en hPanel → Emails.
- **PIN de dispositivo en localStorage.** En web el PIN de puerta queda legible por XSS.
  El diseño acordado lo reemplaza por un token de sesión con expiración; está especificado
  en `docs/superpowers/specs/2026-07-27-pwa-migration-design.md` §6, sin implementar.
- **RLS sin auditar.** Con el anon key público en el bundle, RLS es la única barrera real.
