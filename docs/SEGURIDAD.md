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

---

## Pendiente, por orden de riesgo

### 1. Panel de Easypanel expuesto en el puerto 3000

`http://72.60.51.162:3000` responde desde internet. Es el panel que administra **todos** los
sistemas de clientes del VPS: chillberry, el CRM, las landings. Comprometerlo es
comprometer todo.

Debería quedar detrás de un túnel SSH, o al menos restringido por IP en el firewall.

### 2. Sin captcha en registro ni login

GoTrue soporta hCaptcha y Turnstile (`GOTRUE_SECURITY_CAPTCHA_ENABLED`). Es la defensa
real contra bots; los límites de tasa solo encarecen el ataque.

### 3. PIN de dispositivo en localStorage

En web queda legible por cualquier XSS, en teléfonos personales del personal de puerta. El
reemplazo por un token de sesión con expiración está diseñado en
`docs/superpowers/specs/2026-07-27-pwa-migration-design.md` §6, sin implementar.

### 4. Acceso SSH por root

Se entra como `root` con clave. Funciona, pero un usuario sin privilegios con `sudo` y
`PermitRootLogin no` reduce el daño de una clave filtrada.

### 5. Credenciales expuestas en el chat de esta sesión

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
