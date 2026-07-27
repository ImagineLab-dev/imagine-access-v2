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

**Los backups viven en el mismo disco que la base.** Si el VPS se pierde, se pierden los
dos. Copiarlos fuera del servidor es lo próximo pendiente.

## Correo

`tickets@imaginecloud.digital` por SMTP de Hostinger, configurado en el `.env` del stack.
Cubre tanto los tickets (Edge Functions) como los códigos de verificación y recuperación
de contraseña (GoTrue) — a diferencia del Supabase en la nube, donde eran dos lugares
distintos.

DNS del dominio: MX a Hostinger, SPF, DKIM en los selectores `hostingermail-a/b/c`, y
DMARC en `p=none`. Subir DMARC a `quarantine` cuando haya historial de envíos limpio.

## Pendientes conocidos

- **Backups fuera del servidor.** Hoy están en el mismo disco que la base.
- **El procedimiento de restauración no se ensayó en frío.**
- **`crm.imaginecloud.digital` da 502**, y es previo a esta migración: Easypanel lo rutea a
  `crm_imagine-crm`, un servicio que no existe — el CRM corre como `imagine_app`.
- **Sin monitoreo.** Nadie se entera si Postgres se cae en medio de un evento.
- **CORS de origen único.** `_shared/cors.ts` acepta un solo `ALLOWED_ORIGIN`, así que
  producción y `localhost` no conviven.
- **Roboto se baja de `fonts.gstatic.com`.** Permitido en la CSP; el fix real es
  empaquetar la fuente como asset.
- **PIN de dispositivo en localStorage.** Diseño acordado en
  `docs/superpowers/specs/2026-07-27-pwa-migration-design.md` §6, sin implementar.
