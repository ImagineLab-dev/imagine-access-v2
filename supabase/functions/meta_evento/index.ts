// Copia por servidor de los eventos que dispara la landing.
//
// La landing manda cada evento por dos caminos con el MISMO event_id: el píxel
// del navegador y esta función. Meta los une y cuenta uno solo. El del
// navegador se pierde cuando algo lo bloquea —extensiones, y sobre todo la
// prevención de rastreo de iOS—; el de acá no lo puede bloquear nadie.
//
// La medida que motivó esto: la campaña del 29/07/2026 tuvo 70 clics al enlace
// y 24 vistas de landing. Dos de cada tres llegadas se perdían.
//
// Es un endpoint PÚBLICO —tiene que serlo, lo llama gente sin cuenta— así que
// está acotado a propósito:
//
//   - solo los nombres de evento de la lista, para que no se pueda inyectar
//     Purchase y ensuciar la atribución con compras que nunca ocurrieron
//   - la URL de origen tiene que ser de nuestro dominio
//   - límite por IP
//   - el momento del evento se acota a una ventana razonable
//
// Nunca devuelve error al navegador aunque algo falle: es analítica, y un 500
// acá solo llenaría la consola de quien visita la página sin arreglar nada.

import { corsFor } from '../_shared/cors.ts'
import { getClientIp, isRateLimited } from '../_shared/rate_limiter.ts'
import { enviarEventoMeta } from '../_shared/meta_capi.ts'

/** Lo único que la landing tiene permitido reportar. */
const EVENTOS_PERMITIDOS = new Set(['PageView', 'ClicProbarGratis'])

const DOMINIO = 'imaginecloud.digital'

/** Meta rechaza eventos de más de 7 días; se deja margen y se acota el futuro
 *  a 5 minutos por si el reloj del visitante está adelantado. */
const MAX_ANTIGUEDAD_S = 6 * 24 * 60 * 60
const MAX_FUTURO_S = 5 * 60

Deno.serve(async (req) => {
    const cors = corsFor(req)

    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: cors })
    }
    if (req.method !== 'POST') {
        return respuesta(cors, 405)
    }

    try {
        const ip = getClientIp(req)

        // Generoso a propósito: una persona puede abrir la landing varias veces
        // y tocar más de un botón. Corta el abuso, no el uso.
        if (isRateLimited(`meta_evento:${ip}`, 30, 60_000)) {
            return respuesta(cors, 429)
        }

        const cuerpo = await req.json().catch(() => null)
        if (!cuerpo || typeof cuerpo !== 'object') {
            return respuesta(cors, 400)
        }

        const { nombre, eventId, urlOrigen, fbp, fbc, momento, datos } = cuerpo as Record<
            string,
            unknown
        >

        if (typeof nombre !== 'string' || !EVENTOS_PERMITIDOS.has(nombre)) {
            console.log('[meta_evento] nombre no permitido', String(nombre).slice(0, 40))
            return respuesta(cors, 400)
        }

        // Sin identificador no hay forma de unirlo con el del navegador, y
        // mandarlo igual garantizaría el conteo doble. Mejor descartarlo.
        if (typeof eventId !== 'string' || eventId.length < 8 || eventId.length > 100) {
            console.log('[meta_evento] event_id invalido')
            return respuesta(cors, 400)
        }

        // La URL viaja tal cual a Meta, así que se comprueba que sea nuestra:
        // sin esto, cualquiera podría atribuir tráfico de otro sitio a este
        // píxel.
        let url: string | null = null
        if (typeof urlOrigen === 'string') {
            try {
                const u = new URL(urlOrigen)
                if (u.protocol === 'https:' && u.hostname.endsWith(DOMINIO)) {
                    url = u.toString()
                }
            } catch {
                // URL ilegible: se manda sin ella, que es mejor que descartar
                // el evento entero.
            }
        }

        const ahora = Math.floor(Date.now() / 1000)
        let cuando = typeof momento === 'number' && Number.isFinite(momento)
            ? Math.floor(momento)
            : ahora
        if (cuando > ahora + MAX_FUTURO_S || cuando < ahora - MAX_ANTIGUEDAD_S) {
            cuando = ahora
        }

        await enviarEventoMeta({
            nombre,
            eventId,
            urlOrigen: url,
            fbp: textoCorto(fbp, 120),
            fbc: textoCorto(fbc, 200),
            // Del request, nunca del cuerpo: si el navegador pudiera declarar
            // su propia IP, el cotejo de Meta se podría falsear.
            ip: ip || null,
            userAgent: req.headers.get('user-agent'),
            momento: cuando,
            datos: saneados(datos),
        })

        return respuesta(cors, 202)
    } catch (e) {
        console.error('[meta_evento] fallo', String(e))
        // 202 igual: el visitante no tiene nada que hacer con este error, y
        // devolverle un 500 solo le ensucia la consola.
        return respuesta(cors, 202)
    }
})

function respuesta(cors: Record<string, string>, status: number): Response {
    return new Response(null, { status, headers: cors })
}

function textoCorto(v: unknown, max: number): string | null {
    return typeof v === 'string' && v.length > 0 && v.length <= max ? v : null
}

/**
 * Deja pasar solo pares texto→texto cortos.
 *
 * `datos` viene del navegador y va derecho a Meta. Sin acotarlo, alguien podría
 * mandar un objeto enorme o anidado y hacer que Meta rechace el lote entero.
 */
function saneados(v: unknown): Record<string, unknown> | null {
    if (!v || typeof v !== 'object' || Array.isArray(v)) return null
    const salida: Record<string, unknown> = {}
    let n = 0
    for (const [k, valor] of Object.entries(v as Record<string, unknown>)) {
        if (n >= 8) break
        if (typeof k !== 'string' || k.length > 40) continue
        if (typeof valor === 'string') salida[k] = valor.slice(0, 100)
        else if (typeof valor === 'number' && Number.isFinite(valor)) salida[k] = valor
        else continue
        n++
    }
    return Object.keys(salida).length > 0 ? salida : null
}
