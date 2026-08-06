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

export function getClientIp(req: Request): string {
    const forwarded = req.headers.get('x-forwarded-for')
    if (forwarded) {
        return forwarded.split(',')[0].trim()
    }
    return req.headers.get('x-real-ip')?.trim() || 'unknown'
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
 * La mejor IP del cliente para mandarle a Meta, o `null` si no hay ninguna
 * válida.
 *
 * `getClientIp` sirve para limitar por tasa, donde la cadena `'unknown'` es un
 * cubo perfectamente válido. Pero como `client_ip_address` de la API de
 * Conversiones esa palabra es basura: Meta espera una IPv4 o IPv6 y descarta
 * cualquier otra cosa, así que mandarla no solo no ayuda —ensucia el parámetro
 * que justamente se quiere mejorar—.
 *
 * Además elige **IPv6 por encima de IPv4** cuando la cadena de proxies trae las
 * dos, que es lo que Meta recomienda: identifica mejor al visitante.
 *
 * Nunca se lee del cuerpo del pedido. Si el navegador pudiera declarar su
 * propia IP, el cotejo de Meta se podría falsear.
 */
export function ipParaMeta(req: Request): string | null {
    const candidatos: string[] = []

    const forwarded = req.headers.get('x-forwarded-for')
    if (forwarded) {
        // El primero es el cliente; los que siguen son los proxies. Se miran
        // todos igual por si el primero viene vacío o mal formado.
        for (const parte of forwarded.split(',')) candidatos.push(parte.trim())
    }
    const real = req.headers.get('x-real-ip')?.trim()
    if (real) candidatos.push(real)

    // Se quitan los corchetes de la forma [::1]:puerto y el puerto de IPv4.
    const limpios = candidatos
        .map((c) => c.replace(/^\[|\]$/g, '').replace(/^(\d+\.\d+\.\d+\.\d+):\d+$/, '$1'))
        .filter(Boolean)

    const v6 = limpios.find(esIPv6)
    if (v6) return v6

    const v4 = limpios.find(esIPv4)
    return v4 ?? null
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
