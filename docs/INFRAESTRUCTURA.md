# Infraestructura — Imagine Access

## Dónde vive cada cosa

| | Dónde | Servidor |
|---|---|---|
| PWA | `https://imaginecloud.digital` | Hosting compartido Hostinger, `u475398526`, IP `62.72.62.225` |
| Backend | `https://api.imaginecloud.digital` | VPS `srv969105`, IP `72.60.51.162` |

El VPS es **compartido con otros sistemas en producción** (chillberry, imagine-crm,
license-server, landings). Cualquier cosa que se haga ahí los afecta.

## Supabase autohospedado

- Raíz: `/opt/supabase-imagine/`
- Compose: `supabase-src/docker/` (clon oficial de `supabase/supabase`)
- Secretos: `secrets.env` y `supabase-src/docker/.env`, ambos `chmod 600`
- Traefik: `/etc/easypanel/traefik/config/supabase-imagine.yaml`

**Exposición de red.** El compose oficial publica Kong en 8000/8443 y el pooler en
5432/6543. En una IP pública eso deja Postgres accesible desde internet. El
`docker-compose.override.yml` lo corrige: Kong no publica nada —Traefik lo alcanza por la
red overlay `easypanel` y le agrega TLS— y el pooler escucha solo en `127.0.0.1`.

Ojo con `COMPOSE_FILE` en el `.env`: si lista un solo archivo, el override **no se carga**
y esas protecciones se pierden en silencio. Debe decir
`COMPOSE_FILE=docker-compose.yml:docker-compose.override.yml`.

### Operación

```bash
cd /opt/supabase-imagine/supabase-src/docker
docker compose ps                    # estado
docker compose logs -f auth          # logs de un servicio
docker compose restart kong          # reiniciar uno
docker compose up -d                 # aplicar cambios del compose
```

Studio (panel de administración) no está expuesto a internet a propósito. Para entrar,
túnel SSH:

```bash
ssh -L 3001:localhost:8000 root@72.60.51.162
# y abrir http://localhost:3001 con DASHBOARD_USERNAME / DASHBOARD_PASSWORD del .env
```

## Esquema

El orden que funciona es **master → migraciones → master**:

```bash
cd /opt/supabase-imagine/supabase-src/docker
PGPASS=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
psql() { docker exec -i -e PGPASSWORD="$PGPASS" supabase-db psql -U postgres -d postgres; }

psql < /opt/supabase-imagine/schema/master_no_tx.sql
for f in /opt/supabase-imagine/schema/supabase/migrations/*.sql; do psql < "$f"; done
psql < /opt/supabase-imagine/schema/master_no_tx.sql
```

Dos cosas que hacen falta saber:

- `00_MASTER_SCHEMA_FINAL.sql` viene envuelto en `BEGIN/COMMIT`. Un solo error revierte
  las ~200 sentencias anteriores y deja la base vacía. Por eso se usa `master_no_tx.sql`,
  que es el mismo archivo sin la transacción.
- El master no es autocontenido: sus policies usan `public.is_admin()`, que crea la
  migración `20260311200000_remove_owner_role.sql`. De ahí la tercera pasada.

Estado esperado al terminar: 10 tablas (todas con RLS), 26 policies, 25 funciones.

## Backups

Diarios a las 03:15 por `/etc/cron.d/supabase-imagine-backup`, con 14 días de retención en
`/opt/supabase-imagine/backups/`.

El script usa `pg_dumpall`, no `pg_dump`: incluye los roles del cluster. Restaurar solo los
datos sin los roles deja permisos rotos y RLS que no aplica — peor que no tener backup,
porque aparenta haber funcionado. Aborta si el dump sale sospechosamente chico, si el gzip
no valida, o si tiene menos de 10 `CREATE TABLE`.

### Restaurar de verdad

**Esto no está probado end-to-end.** Lo verificado es que el dump contiene el esquema
completo (10 tablas, 25 funciones, 26 policies, 36 índices restauran idénticos). El
procedimiento real de recuperación hay que ensayarlo una vez, en frío, antes de
necesitarlo:

```bash
cd /opt/supabase-imagine/supabase-src/docker
docker compose down                       # SIN -v todavía
cp -r volumes/db/data /opt/backup-manual  # red de seguridad
docker compose down -v
rm -rf volumes/db/data
docker compose up -d db
# esperar a que supabase-db esté healthy
zcat /opt/supabase-imagine/backups/supabase_XXXX.sql.gz | \
  docker exec -i -e PGPASSWORD="$PGPASS" supabase-db psql -U supabase_admin -d postgres
docker compose up -d
```

Se restaura como `supabase_admin`, no como `postgres`: `postgres` no es superusuario en
Supabase y no puede tocar los esquemas `auth` ni `storage`.

### Qué protege qué

Hay dos capas, y ninguna cubre sola lo que hace falta:

| | Frecuencia | Dónde | Sirve para |
|---|---|---|---|
| Dumps de `pg_dumpall` | Diaria, 03:15 | Mismo disco del VPS | Restaurar la base sola, sin tocar el resto |
| Backups del VPS (Hostinger) | **Semanal** | Infraestructura de Hostinger | Sobrevivir a la pérdida del servidor |

Verificado el 2026-07-27: el VPS tiene backups automáticos de Hostinger en
`node1011-br-cam-1-pbs`, con copias del 19 y del 26 de julio.

**El hueco real está en la intersección.** Si la base se corrompe un martes:

- El dump del día existe y tiene la granularidad correcta, pero está en el mismo disco: no
  sirve si lo que falla es el disco o el servidor.
- El backup del VPS sí está afuera, pero es del domingo —se pierden dos días— y restaura la
  máquina **entera**: volvería atrás también chillberry, el CRM y el resto de los sistemas
  de clientes que conviven ahí. No es una opción realista para recuperar solo Postgres.

Cerrar eso requiere copiar el dump diario fuera del VPS. Hay espacio de sobra para
retenerlos localmente —132 GB libres, y cada dump pesa decenas de KB— así que el problema
no es capacidad sino ubicación.

## Correo

`tickets@imaginecloud.digital` por SMTP de Hostinger, configurado en el `.env` del stack.
Cubre tanto los tickets (Edge Functions) como los códigos de verificación y recuperación
de contraseña (GoTrue) — a diferencia del Supabase en la nube, donde eran dos lugares
distintos.

DNS del dominio: MX a Hostinger, SPF, DKIM en los selectores `hostingermail-a/b/c`, y
DMARC en `p=none`. Subir DMARC a `quarantine` cuando haya historial de envíos limpio.

## Runbook — "la app carga pero no trae datos"

Síntoma: el sitio abre y el login anda, pero nada que lea datos responde. En la
consola del navegador, peticiones a `api.imaginecloud.digital/rest/...` que
cuelgan o terminan en 504. `/auth/...` funciona.

Es la firma de **PostgREST inalcanzable por el bridge de Docker**. La causa
raíz que ya pasó una vez (04/08/2026): una regla de firewall que descarta
`tcp dport 3000` para todo salvo `lo`, y como PostgREST escucha internamente en
el 3000, se come el tráfico interno Kong → PostgREST.

Diagnóstico en 2 minutos (no repetir el via crucis de 30 pasos):

```bash
# 1. ¿El servidor está sano y es solo /rest/?  (auth rápido, rest cuelga)
curl -s -m8 -o /dev/null -w "auth  %{http_code} %{time_total}s\n" https://api.imaginecloud.digital/auth/v1/health
curl -s -m8 -o /dev/null -w "rest  %{http_code} %{time_total}s\n" -H "apikey: $ANON" \
  "https://api.imaginecloud.digital/rest/v1/organizations?select=id&limit=1"

# 2. ¿PostgREST está bien en sí?  loopback responde 200 => el proceso está OK,
#    el problema es la RED para llegarle.
docker run --rm --network container:supabase-rest curlimages/curl -s -m6 \
  -o /dev/null -w "loopback %{http_code}\n" -H "apikey: $ANON" \
  "http://localhost:3000/organizations?select=id&limit=1"

# 3. LA REGLA. Si el DROP tiene paquetes contados, es esto:
iptables -L DOCKER-USER -n -v --line-numbers | grep 3000
```

Arreglo (restaura el tráfico interno, deja bloqueado el externo):

```bash
iptables -I DOCKER-USER 2 -i br+ -p tcp -m tcp --dport 3000 -j RETURN
iptables-save > /etc/iptables/rules.v4   # persistir para el reboot
```

## IPv6

Meta recomienda mandar `client_ip_address` en la API de conversiones, y prefiere
la IPv6 cuando existe. Sin AAAA en el dominio de la API, ningún cliente llega por
IPv6 y esa dirección nunca aparece.

Estado desde el 06/08/2026:

| Nombre | A | AAAA |
|---|---|---|
| `@` y `www` | `62.72.62.225` | `2a02:4780:13:1281:0:1c56:17e:3` (hosting compartido, ya estaba) |
| `api` | `72.60.51.162` | `2a02:4780:66:5e49::1` (VPS, agregado el 06/08) |

Verificado que la cadena entera responde por IPv6: Traefik → Kong → GoTrue y
PostgREST devuelven 200 con el nombre público.

### La trampa: `ip6tables` es un firewall aparte

`iptables` y `ip6tables` no comparten reglas. El VPS tenía `ip6tables` **vacío con
política ACCEPT**, así que todo lo que se creía cerrado por IPv4 estaba abierto por
IPv6 — incluido el 3000 de Easypanel, que en IPv4 tiene un DROP explícito.

Mientras el nombre no tuvo AAAA la dirección IPv6 no era pública y el hueco pasaba
inadvertido. Publicar el AAAA lo convierte en algo que se descubre con una consulta
de DNS. Por eso el espejo se aplicó **el mismo día**:

```bash
ip6tables -A INPUT -s ::1/128 -p tcp --dport 3000 -j ACCEPT
ip6tables -A INPUT          -p tcp --dport 3000 -j DROP
ip6tables-save > /etc/iptables/rules.v6   # NO usar netfilter-persistent save:
                                          # pisa también rules.v4
```

**Regla para el futuro: toda regla que se agregue a `iptables` hay que espejarla en
`ip6tables`.** Si no, se cierra media puerta.

Cuidado al verificar: un `curl` desde el propio VPS hacia su IP pública **no pasa por
`INPUT`** y devuelve 200 aunque la regla esté bien puesta. Para saber si algo está
realmente cerrado hay que probar desde afuera, o mirar los contadores de paquetes.

## Pendientes conocidos

- **El dump diario no sale del VPS.** Los backups de Hostinger son semanales y de la
  máquina entera, así que no cubren una recuperación puntual de la base.
- **El procedimiento de restauración no se ensayó en frío.**
- **`crm.imaginecloud.digital` da 502**, y es previo a esta migración: Easypanel lo rutea a
  `crm_imagine-crm`, un servicio que no existe — el CRM corre como `imagine_app`.
- **Sin monitoreo.** Nadie se entera si Postgres se cae en medio de un evento.
- **Colisión de puerto 3000 con Easypanel.** Un servicio de Easypanel usa el 3000 y su
  regla de firewall (DROP en `DOCKER-USER`) tumbó a PostgREST el 04/08/2026. El fix del
  runbook de arriba lo restaura, pero si Easypanel regenera `rules.v4` vuelve a romper. Fix
  permanente: que ese servicio use otro puerto, o que el DROP sea específico a `eth0` en vez
  de a todas las interfaces.
- **CORS de origen único.** `_shared/cors.ts` acepta un solo `ALLOWED_ORIGIN`, así que
  producción y `localhost` no conviven.
- **Roboto se baja de `fonts.gstatic.com`.** Permitido en la CSP; el fix real es
  empaquetar la fuente como asset.
- **PIN de dispositivo en localStorage.** Diseño acordado en
  `docs/superpowers/specs/2026-07-27-pwa-migration-design.md` §6, sin implementar.
