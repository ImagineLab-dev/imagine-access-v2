/**
 * Cabeceras CORS de las Edge Functions.
 *
 * Acepta una LISTA de orígenes, no uno solo. Antes era `ALLOWED_ORIGIN` a
 * secas, así que producción y `localhost` no podían convivir: para desarrollar
 * había que cambiar el secret y volver a desplegar, y quien se olvidaba dejaba
 * producción apuntando a localhost.
 *
 * El origen se elige contra el header `Origin` de cada petición y se responde
 * con ese valor exacto, no con `*`. Es lo que exige el navegador cuando la
 * petición lleva credenciales, y evita el comodín, que anula la protección.
 */

const listaCruda = (Deno.env.get('ALLOWED_ORIGINS') ?? Deno.env.get('ALLOWED_ORIGIN') ?? '').trim()
const environment = (Deno.env.get('ENVIRONMENT') ?? '').toLowerCase()
const esLocal = environment === 'local' || environment === 'development'
const permitirCualquiera = Deno.env.get('ALLOW_ANY_ORIGIN')?.toLowerCase() === 'true'

const permitidos = listaCruda
    .split(',')
    .map((o) => o.trim().replace(/\/+$/, ''))
    .filter((o) => o.length > 0)

if (permitidos.length === 0 && !permitirCualquiera && !esLocal) {
    throw new Error(
        'CORS: hay que setear ALLOWED_ORIGINS (o ALLOWED_ORIGIN). ' +
        'Usar ENVIRONMENT=local sólo para desarrollo.',
    )
}

/** `true` si el origen está habilitado. En local se aceptan todos los localhost. */
function estaPermitido(origen: string): boolean {
    if (permitidos.includes(origen)) return true
    // El puerto de `flutter run -d chrome` cambia en cada arranque, así que
    // fijarlo en la lista no sirve.
    if (esLocal && /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origen)) return true
    return false
}

/**
 * Cabeceras para una petición concreta.
 *
 * Hay que pasarle el Request: sin él no se sabe quién llama y habría que
 * responder con un comodín.
 */
export function corsFor(req: Request): Record<string, string> {
    const origen = (req.headers.get('origin') ?? '').replace(/\/+$/, '')

    let permitido: string
    if (permitirCualquiera) {
        permitido = '*'
    } else if (origen && estaPermitido(origen)) {
        permitido = origen
    } else {
        // Origen desconocido: se responde con el primero de la lista. El
        // navegador va a bloquear igual —no coincide con quien pidió— pero la
        // respuesta queda bien formada y el error es claro en consola.
        permitido = permitidos[0] ?? '*'
    }

    return {
        'Access-Control-Allow-Origin': permitido,
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
        'Vary': 'Origin',
    }
}

/**
 * Cabeceras por defecto, sin conocer la petición.
 *
 * Se conserva para no tener que reescribir las 15 funciones de una vez. Las que
 * se vayan tocando deberían pasar a `corsFor(req)`, que es más preciso.
 */
export const corsHeaders: Record<string, string> = {
    'Access-Control-Allow-Origin': permitirCualquiera ? '*' : (permitidos[0] ?? '*'),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    'Vary': 'Origin',
}
