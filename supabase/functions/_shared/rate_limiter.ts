/**
 * In-memory rate limiter for Edge Functions.
 * Tracks requests per IP within a sliding window.
 */

const DEFAULT_MAX_REQUESTS = 60
const DEFAULT_WINDOW_MS = 60 * 1000 // 1 minute

type RateLimitEntry = {
    count: number
    windowStart: number
}

const buckets = new Map<string, RateLimitEntry>()

/** Saca los corchetes y el puerto: `[2a02::1]:443` y `1.2.3.4:5678`. */
function limpiar(valor: string): string {
    const v = valor.trim()
    const conCorchetes = v.match(/^\[([0-9a-fA-F:.]+)\](?::\d+)?$/)
    if (conCorchetes) return conCorchetes[1]
    const v4ConPuerto = v.match(/^(\d{1,3}(?:\.\d{1,3}){3}):\d+$/)
    if (v4ConPuerto) return v4ConPuerto[1]
    return v
}

/** ¿Es una dirección IPv4 con cuatro octetos en rango? */
function esIPv4(v: string): boolean {
    const partes = v.split('.')
    if (partes.length !== 4) return false
    return partes.every((p) => /^\d{1,3}$/.test(p) && Number(p) <= 255)
}

/** ¿Es una IPv6 plausible? Alcanza con la forma: Meta valida el resto. */
function esIPv6(v: string): boolean {
    return v.includes(':') && /^[0-9a-fA-F:.]+$/.test(v) && v.length >= 3
}

/**
 * ¿Es una dirección de la propia infraestructura, y no de un cliente de
 * internet? Se usa para saber dónde termina la parte confiable de la cadena.
 */
function esInterna(v: string): boolean {
    if (!v) return true
    if (v === '::1' || v === '::' || v === 'unknown') return true
    if (/^127\./.test(v)) return true
    if (/^10\./.test(v)) return true
    if (/^192\.168\./.test(v)) return true
    if (/^172\.(1[6-9]|2\d|3[01])\./.test(v)) return true
    if (/^169\.254\./.test(v)) return true // link-local IPv4
    if (/^f[cd][0-9a-f]{2}:/i.test(v)) return true // fc00::/7, ULA
    if (/^fe[89ab][0-9a-f]:/i.test(v)) return true // fe80::/10, link-local
    return false
}

/**
 * La IP que el proxy de confianza **observó**, ignorando lo que el cliente
 * diga de sí mismo.
 *
 * ESTO NO ES UN DETALLE. `X-Forwarded-For` lo puede escribir cualquiera, y
 * Traefik **agrega** la dirección real *después* de lo que mandó el cliente en
 * vez de reemplazarla. Comprobado contra producción el 06/08/2026:
 *
 *     enviando `X-Forwarded-For: 8.8.8.8`
 *     la función recibía `8.8.8.8, 72.60.51.162, 10.11.84.6`
 *
 * Leer el primer elemento —que es lo que se hacía— devuelve entonces lo que el
 * atacante quiso. Con eso se saltaban TODOS los límites de tasa del sistema
 * rotando una cabecera, incluido el bloqueo por intentos fallidos de
 * `login_device`, y se podía ensuciar el `client_ip_address` que se le manda a
 * Meta con direcciones ajenas.
 *
 * Por eso se lee **desde la derecha**: se descartan las direcciones de la propia
 * infraestructura —las que agregan Kong y Traefik— y la primera pública que
 * aparece es la que escribió Traefik, o sea el par TCP real. Lo que el cliente
 * haya inventado queda a la izquierda de esa, y nunca se elige.
 *
 * Se devuelve `null` cuando no hay ninguna utilizable, para que cada quien
 * decida qué hacer: el limitador usa un cubo común, Meta no recibe nada.
 *
 * LO QUE ESTO **NO** CUBRE
 *
 * Si el pedido nace *dentro* del servidor —otro contenedor, un cron del VPS—,
 * la dirección que escribe Traefik es privada, se descarta como infraestructura
 * y la lectura sigue hacia la izquierda, donde está lo que el cliente mandó.
 * O sea: desde adentro sí se puede falsear.
 *
 * Se deja así a propósito. La alternativa —tomar una posición fija en vez de
 * buscar por valor— cierra ese caso, pero si alguien mete otro proxy interno
 * adelante, la posición pasa a caer sobre una dirección privada y **todos** los
 * clientes comparten el cubo `'unknown'`: un pico de tráfico haría rebotar con
 * 429 a la gente en la puerta de un evento. Falsear desde adentro exige ya
 * estar corriendo código en el servidor; que no se validen entradas en plena
 * fiesta, no.
 */
export function ipObservada(req: Request): string | null {
    const forwarded = req.headers.get('x-forwarded-for')
    if (forwarded) {
        const partes = forwarded.split(',').map(limpiar).filter(Boolean)
        for (let i = partes.length - 1; i >= 0; i--) {
            if (!esInterna(partes[i])) return partes[i]
        }
        return null
    }
    // Sin `X-Forwarded-For` no hay cadena que recorrer. `X-Real-IP` la escribe
    // Traefik pisando lo que venga —verificado: mandarla falsa no tuvo efecto—
    // así que acá sí es confiable.
    const real = limpiar(req.headers.get('x-real-ip') ?? '')
    return real && !esInterna(real) ? real : null
}

/**
 * IP del cliente para agrupar por tasa. `'unknown'` es un cubo válido: cuando
 * no se puede distinguir a nadie, todos comparten el mismo límite, que es el
 * lado seguro para equivocarse.
 */
export function getClientIp(req: Request): string {
    return ipObservada(req) ?? 'unknown'
}

/**
 * La IP del cliente para el `client_ip_address` de la API de Conversiones, o
 * `null` si no hay ninguna válida.
 *
 * `getClientIp` sirve para limitar por tasa, donde la cadena `'unknown'` es un
 * cubo perfectamente válido. Pero como `client_ip_address` esa palabra es
 * basura: Meta espera una IPv4 o IPv6 y descarta cualquier otra cosa, así que
 * mandarla no solo no ayuda —ensucia el parámetro que justamente se quiere
 * mejorar—.
 *
 * Meta prefiere la IPv6 cuando existe. Acá no hay nada que elegir: el visitante
 * llega por una familia o por la otra, y `ipObservada` devuelve esa. Lo que
 * hace que lleguen por IPv6 es el registro `AAAA` de `api.imaginecloud.digital`
 * —sin él, ningún cliente puede—; ver `docs/INFRAESTRUCTURA.md` → *IPv6*.
 *
 * Nunca se lee del cuerpo del pedido ni de la parte de la cadena que el cliente
 * controla: si el navegador pudiera declarar su propia IP, el cotejo de Meta se
 * podría falsear con direcciones de terceros.
 */
export function ipParaMeta(req: Request): string | null {
    const ip = ipObservada(req)
    if (!ip) return null
    return esIPv6(ip) || esIPv4(ip) ? ip : null
}

export function isRateLimited(
    key: string,
    maxRequests = DEFAULT_MAX_REQUESTS,
    windowMs = DEFAULT_WINDOW_MS,
): boolean {
    const now = Date.now()
    const entry = buckets.get(key)

    if (!entry || now - entry.windowStart > windowMs) {
        buckets.set(key, { count: 1, windowStart: now })
        return false
    }

    entry.count++
    if (entry.count > maxRequests) {
        return true
    }

    return false
}

export function rateLimitResponse(corsHeaders: Record<string, string>): Response {
    return new Response(
        JSON.stringify({ error: 'Too many requests. Please try again later.' }),
        {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 429,
        },
    )
}
