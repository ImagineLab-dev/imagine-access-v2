# Revisión de seguridad

**Fecha:** 2026-07-28
**Alcance:** PWA en `imaginecloud.digital` y Supabase autohospedado en el VPS.

Lo que sigue está **verificado ejecutando pruebas contra producción**, no leído del código.
Donde no pude verificar, lo digo.

---

## Crítico — corregido durante esta revisión

### Registro abierto sin límite, con creación automática de organizaciones

**Comprobado:** se creó una cuenta desde fuera, con un correo descartable, sin ninguna
credencial previa. Funcionó.

La cadena completa era:

1. `DISABLE_SIGNUP=false` → cualquiera en internet puede registrarse.
2. El trigger `on_profile_auto_org` crea **una organización por cada perfil**.
3. Cada registro dispara un correo de verificación **por el SMTP propio**.

O sea: un bot podía generar cuentas y organizaciones ilimitadas, llenar la base, y —lo más
caro— quemar la reputación de envío de `imaginecloud.digital` hasta que Hostinger
suspendiera el buzón. Un dominio marcado como emisor de spam deja de entregar **también los
tickets**, que es el producto.

**Corregido:** límites de tasa en GoTrue, pasados por `docker-compose.override.yml` porque
el compose oficial no los expone.

```
GOTRUE_RATE_LIMIT_EMAIL_SENT=10     # correos por hora
GOTRUE_RATE_LIMIT_VERIFY=10
GOTRUE_RATE_LIMIT_OTP=10
GOTRUE_RATE_LIMIT_TOKEN_REFRESH=30
```

**Verificado:** 12 registros seguidos → los 10 primeros pasaron, el 11 y el 12 recibieron
`429`. Las 11 cuentas de prueba se eliminaron; quedan las 2 reales.

**Esto acota, no cierra.** Diez cuentas por hora siguen siendo 240 por día. Mientras no
haya facturación, nadie debería auto-registrarse: lo correcto es `DISABLE_SIGNUP=true` y
que las cuentas se creen solo por invitación desde `create_user`. Es una decisión de
producto, por eso no se aplicó.

---

## Crítico — corregido el 07/08/2026

### Cualquiera con la clave pública podía regalarse suscripciones pagas

Lo encontró una auditoría adversarial del aislamiento entre organizaciones —diez
agentes, simulando sesiones reales a nivel de base de datos, cada uno intentando
*romper* la separación—. El aislamiento entre tenants resultó **sólido** (16/16
lecturas cruzadas bloqueadas, todas las escrituras cruzadas bloqueadas, 18/18
intentos de escalar a superadmin bloqueados, `anon`/`authenticated` sin
`bypassrls`). Pero aparecieron dos túneles de escritura de **facturación**, uno
crítico.

**`apply_subscription_payment` era invocable por `anon`.** La función es
`SECURITY DEFINER` (owner `postgres`, superusuario: salta RLS). Con `EXECUTE`
para `anon`, cualquiera con la clave pública —la que viaja en el bundle, sin
login— podía otorgarle a **cualquier** organización una suscripción anual y
reactivar orgs vencidas.

Reproducido contra la org de un cliente real, revertido:

```
9º2:  trial → annual, vence 2027  + un evento de pago falso insertado
      (ejecutado como anon, sin sesión)
```

**Causa raíz: deriva de producción, no un bug de código.** La migración otorga la
función **solo a `service_role`**. Alguien le dio `EXECUTE` a `anon` a mano
después de correr la migración. El único control era el trigger
`guard_billing_columns`, que trata `auth.uid() IS NULL` como camino confiable —y
el rol `anon` de PostgREST también produce `uid` NULL, así que caía en el bypass.

**`record_email_sent`**, misma deriva y severidad alta: `anon` podía inflar el
contador de emails de otra org (empujarla sobre su cupo) o bajar el propio en
negativo.

**Corregido:** `REVOKE ALL ... FROM anon, authenticated` en las dos, dejándolas
solo para `service_role`. El webhook de dLocal usa `service_role`, así que ningún
pago real se rompe. Verificado: el mismo exploit ahora da `permission denied`.
Queda como migración `20260807170000_cerrar_fugas_facturacion_y_org.sql` para que
un reset no reintroduzca la deriva.

> **La trampa que casi lo esconde.** Un verificador reprodujo el exploit y al
> leer el resultado *como el atacante* vio 0 filas —parecía falso positivo—.
> Pero la escritura SÍ había ocurrido: una policy de SELECT le ocultaba al
> atacante la fila que él mismo acababa de escribir. Hubo que leer el estado como
> superusuario para verlo. Es la misma trampa del 204-sobre-0-filas, del otro
> lado.

### Cualquier miembro podía editar el nombre de su propia organización

La policy `ALL` "Users see own organization" era permisiva y redundante (ya
existía "Org member read" para el SELECT), pero al ser `ALL` autorizaba también
UPDATE y DELETE a **cualquier** miembro de la org —incluido un rol bajo como
`rrpp`, ni dueño ni admin—. No cruzaba organizaciones (siempre la propia), pero
un miembro cualquiera no debería poder renombrar la entidad. **Corregido:**
borrada la policy `ALL`; INSERT/UPDATE/DELETE quedan solo para el dueño, el SELECT
intacto. Verificado en transacción revertida antes de aplicar.

### Nota sobre `users_profile` self-update

La auditoría marcó que su `WITH CHECK (user_id = uid())` no impide, a nivel RLS,
que alguien se suba el rol. Es correcto marcarlo, pero **un `WITH CHECK` no puede
arreglarlo**: solo ve la fila nueva, no la vieja, así que no puede exigir "el rol
no cambió". La herramienta correcta es el trigger `guard_profile_self_update`,
que compara viejo contra nuevo y ya aborta la escalada —verificado: un admin no
puede auto-ascenderse—. La defensa es sólida; su único riesgo es depender de un
solo trigger. Pendiente: una prueba de regresión que falle si ese trigger se cae.

### Deriva de permisos, el patrón de fondo

`anon` tiene `EXECUTE` sobre **las 30 funciones** `SECURITY DEFINER`, no solo las
dos corregidas. La mayoría se protege sola (`is_superadmin` lee la tabla, los
`get_*` filtran por org, las `superadmin_*` se auto-verifican), por eso el resto
del aislamiento aguantó. Pero el hecho de que `anon` pueda *invocarlas* todas es
deriva: las migraciones no lo declaran. Pendiente de bajo riesgo: revocar `anon`
de las que no lo necesitan como defensa en profundidad, y auditar por qué
producción derivó (¿un `GRANT ... TO PUBLIC` corrido a mano? ¿un restore?).

---

## Crítico — corregido el 06/08/2026

### Los límites de tasa se saltaban con una cabecera

Apareció auditando otra cosa: al medir qué IP recibía `meta_evento` para mandarle a Meta.

`X-Forwarded-For` la escribe **el cliente**, y Traefik **agrega** la dirección real detrás en
vez de reemplazarla. El código leía el primer elemento. Medido contra producción:

| Se manda | La función recibía | Y usaba |
|---|---|---|
| `X-Forwarded-For: 8.8.8.8` | `8.8.8.8, 72.60.51.162, 10.11.84.6` | **`8.8.8.8`** |
| `X-Real-IP: 1.2.3.4` | (Traefik la pisa) | `72.60.51.162` ✅ |

Cambiando la cabecera en cada pedido, cada uno caía en un cubo distinto y **ningún límite de
tasa del sistema se aplicaba**. Alcanza a las 16 funciones, e incluye:

- El bloqueo por intentos fallidos de `login_device` —lo único que frena la fuerza bruta
  contra los PIN de cuatro dígitos de los teléfonos de puerta—, que además tenía su **propia
  copia** del mismo defecto.
- Los topes de `create_user` y `create_ticket`.
- El `client_ip_address` que se le manda a Meta, que se podía ensuciar con IP ajenas.

**Corregido:** `ipObservada` en `_shared/rate_limiter.ts` lee la cadena **desde la derecha**,
descartando las direcciones de la propia infraestructura; lo que el cliente inventa queda a
la izquierda y no se elige nunca. `login_device` pasó a usar la versión compartida.

**Probado** con 42 pruebas en `_shared/rate_limiter.test.ts` (`node` sin instalar nada) y
de punta a punta **desde una máquina externa**: 35 pedidos con 35 IP falsas distintas, primer
`429` en el número 31 —o sea, los 35 en el mismo cubo, el de la IP real—.

> **Trampa al reproducirlo.** Un `curl` hecho *en el propio VPS* sale por el bridge de Docker,
> así que Traefik escribe una IP privada y la falsificación sí funciona. Hay que probar desde
> afuera. Es también el límite conocido del arreglo, documentado en el código: desde adentro
> del servidor se puede falsear, y se acepta porque cerrarlo obliga a leer una posición fija
> del encabezado, que se rompe si alguien agrega otro proxy y deja a todos los clientes
> compartiendo un solo cubo.

> **Segunda trampa.** Copiar el archivo no alcanza: el runtime de Deno cachea los módulos y
> los workers nuevos reusan la caché. Sin `docker restart supabase-edge-functions` el código
> viejo sigue corriendo. Se verificó instrumentando y leyendo los logs, no suponiendo.

---

## Verificado y correcto

| Superficie | Estado |
|---|---|
| Postgres (5432) | **Cerrado** desde internet. Solo loopback |
| Pooler (6543) | **Cerrado** |
| Kong (8000/8443) | **Cerrado**. Solo entra por Traefik con TLS |
| `/assets/.env` | 404 — verificado por contenido, no por código de estado |
| Studio | No expuesto. Requiere túnel SSH |
| TLS | Let's Encrypt, HSTS `max-age=31536000` |
| Cabeceras | CSP, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy` con `camera=(self)` |
| Secretos del stack | `chmod 600` |
| RLS — lectura anónima | **Verificado.** Con la clave anon sin autenticar, las 10 tablas devuelven vacío |
| RLS — lectura entre organizaciones | **Verificado.** Usuario autenticado de otra organización ve 0 filas en `tickets`, `events`, `organizations`, `users_profile`, `checkins` y `devices` |
| RLS — escritura entre organizaciones | **Verificado.** Como usuario de otra organización: INSERT de ticket en evento ajeno → 403; UPDATE de evento, UPDATE de organización y DELETE de evento → 0 filas alteradas |

> **Trampa al repetir estas pruebas.** PostgREST devuelve **204** en un `UPDATE` o
> `DELETE` aunque RLS haya filtrado todas las filas: la operación "tuvo éxito" sobre cero
> registros. Mirar solo el código de estado da un falso positivo de vulnerabilidad. Hay que
> contar filas en la base antes y después.

**Fuerza bruta contra el login de dispositivos:** `login_device` tiene bloqueo tras 5
intentos fallidos por combinación alias+IP, con 10 minutos de espera. Pero el contador vive
**en memoria del isolate** de la Edge Function: cuando el isolate recicla —cosa que pasa
sola— el contador se pierde. Un atacante paciente lo sortea esperando. Para cerrarlo hay que
mover el contador a Postgres.

> Hasta el 06/08/2026 ni siquiera hacía falta esperar: la IP con la que se armaba la clave
> del bloqueo la elegía el atacante. Ver *Los límites de tasa se saltaban con una cabecera*.
> Medido el 06/08: los contadores en memoria **sí duran** entre pedidos —30 pasan y el 31 da
> `429`—, así que el reciclado del isolate es esporádico, no por pedido.

---

## Pendiente, por orden de riesgo

### 1. El puerto 3000 del panel — cerrado el 06/08/2026

**Resuelto.** Se deja el detalle porque explica de dónde salió `panel.imaginecloud.digital`.

El panel de Easypanel administra **todos** los sistemas de clientes del VPS —chillberry, el
CRM, las landings—, y se servía únicamente por `http://72.60.51.162:3000`, sin cifrado: la
contraseña de administrador viajaba en texto plano en cada inicio de sesión.

Verificado que **sí exige autenticación** (`401 UNAUTHORIZED` sin credenciales), así que no
era una puerta abierta. El problema era el transporte.

Existía una ruta HTTPS de Easypanel, pero su dominio `yk50nb.easypanel.host` no resuelve en
DNS público, así que nadie la usaba. Se agregó una propia:

- DNS: `panel.imaginecloud.digital` → `72.60.51.162`
- Traefik: `/etc/easypanel/traefik/config/panel-imaginecloud.yaml`, apuntando al mismo
  servicio interno `http://easypanel:3000`
- Verificado: HTTPS 200 con certificado Let's Encrypt propio, HTTP redirige con 301, y el
  API sigue devolviendo 401 sin credenciales

Con la ruta HTTPS en uso, el 3000 se cerró en las dos familias:

```bash
iptables  -A INPUT -s 127.0.0.1/32 -p tcp --dport 3000 -j ACCEPT
iptables  -A INPUT                 -p tcp --dport 3000 -j DROP
ip6tables -A INPUT -s ::1/128      -p tcp --dport 3000 -j ACCEPT   # 06/08
ip6tables -A INPUT                 -p tcp --dport 3000 -j DROP     # 06/08
```

**Verificado desde fuera del VPS**, no desde adentro: IPv4 da timeout, y por IPv6 el
contador del DROP sube. Easypanel sigue respondiendo 200 por loopback y por
`panel.imaginecloud.digital`.

La parte de IPv6 se agregó recién el 06/08 junto con el registro AAAA de `api`: hasta ese
día `ip6tables` estaba vacío y el 3000 estaba abierto por IPv6 aunque en IPv4 tuviera el
DROP puesto. Ver `docs/INFRAESTRUCTURA.md` → *IPv6*.

Copia versionada de la ruta en `deploy/traefik-panel-imaginecloud.yaml`.

### 2. Los puertos de Docker Swarm están abiertos a internet

Detectado el 06/08/2026 escaneando desde afuera del VPS:

| Puerto | Qué es | Desde internet |
|---|---|---|
| 2377 | Gestión del clúster Swarm | **abierto** |
| 7946 | Descubrimiento entre nodos (gossip) | **abierto** |

No es una puerta abierta —2377 exige TLS mutuo con el token de unión al clúster—, pero no
hay ninguna razón para que sean visibles: el Swarm es de un solo nodo, así que nadie los
necesita desde afuera. Es superficie de ataque regalada.

```bash
# cerrar en las dos familias, que son firewalls distintos
for p in 2377 7946; do
  iptables  -A INPUT -p tcp --dport $p -j DROP
  ip6tables -A INPUT -p tcp --dport $p -j DROP
done
iptables-save  > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6
```

Sin probar: verificar antes que los contenedores no dependan de esos puertos por la IP
pública del host.

### 3. Sin captcha en registro ni login

GoTrue soporta hCaptcha y Turnstile (`GOTRUE_SECURITY_CAPTCHA_ENABLED`). Es la defensa
real contra bots; los límites de tasa solo encarecen el ataque.

### 4. PIN de dispositivo en localStorage

En web queda legible por cualquier XSS, en teléfonos personales del personal de puerta. El
reemplazo por un token de sesión con expiración está diseñado en
`docs/superpowers/specs/2026-07-27-pwa-migration-design.md` §6, sin implementar.

### 5. Acceso SSH por root

Se entra como `root` con clave. Funciona, pero un usuario sin privilegios con `sudo` y
`PermitRootLogin no` reduce el daño de una clave filtrada.

### 6. Credenciales expuestas en el chat de esta sesión

El token de API de Hostinger y la contraseña del buzón `tickets@imaginecloud.digital`
pasaron por la conversación. **Ambos hay que rotarlos.** El token da control total sobre
dominios, DNS, hosting y VPS de la cuenta.

---

## Lo que esta revisión NO cubrió

- Inyección SQL en las funciones `SECURITY DEFINER`.
- Validación de entrada en las 15 Edge Functions.
- Dependencias con vulnerabilidades conocidas.
- El firmado de los QR (`QR_SECRET_KEY`) y si un token puede falsificarse.

Ninguna de esas se miró. Que no aparezcan acá no significa que estén bien.
