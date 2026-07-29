// API de Conversiones de Meta.
//
// Existe porque el pago termina en checkout.dlocalgo.com, un dominio que no
// controlamos: el pixel del navegador jamás puede ver esa compra. La única
// forma de atribuir la conversión a la campaña que la trajo es mandarla desde
// el servidor, cuando dLocal confirma el cobro.
//
// Reparto de eventos, pensado para que NO haya duplicados:
//   - Navegador  → PageView, InitiateCheckout   (el usuario está ahí)
//   - Servidor   → Purchase                     (ocurre fuera de nuestro sitio)
//
// Ningún evento se manda por los dos caminos, así que no hace falta deduplicar.
// Si algún día se manda el mismo evento desde ambos lados, hay que darles el
// MISMO event_id o Meta lo va a contar dos veces.

const GRAPH = 'https://graph.facebook.com';

/** SHA-256 en hexadecimal, como exige Meta para los datos personales. */
async function hash(valor: string): Promise<string> {
    const limpio = valor.trim().toLowerCase();
    const bytes = new TextEncoder().encode(limpio);
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    return Array.from(new Uint8Array(digest))
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('');
}

export interface EventoMeta {
    nombre: string;
    /** Identificador único del evento. Si el mismo evento se manda dos veces
     *  con este valor, Meta lo cuenta una sola vez. */
    eventId: string;
    /** Correo del comprador. Se envía hasheado, nunca en claro. */
    email?: string | null;
    valor?: number | null;
    moneda?: string | null;
    urlOrigen?: string | null;
}

/**
 * Manda un evento a Meta.
 *
 * Nunca lanza: un fallo de analítica no puede tumbar un cobro. Si no hay
 * credenciales configuradas, no hace nada y lo dice en el log — así queda
 * explícito que la medición está apagada, en vez de fallar en silencio.
 */
export async function enviarEventoMeta(evento: EventoMeta): Promise<void> {
    const pixelId = Deno.env.get('META_PIXEL_ID');
    const token = Deno.env.get('META_CAPI_TOKEN');

    if (!pixelId || !token) {
        console.log('[meta] sin META_PIXEL_ID o META_CAPI_TOKEN: evento no enviado',
            evento.nombre);
        return;
    }

    try {
        const userData: Record<string, unknown> = {};
        if (evento.email) {
            userData.em = [await hash(evento.email)];
        }

        const cuerpo: Record<string, unknown> = {
            data: [
                {
                    event_name: evento.nombre,
                    event_time: Math.floor(Date.now() / 1000),
                    event_id: evento.eventId,
                    // 'website' y no 'other': la conversión se origina en un
                    // flujo web aunque la confirme un webhook.
                    action_source: 'website',
                    event_source_url: evento.urlOrigen ?? 'https://imaginecloud.digital/',
                    user_data: userData,
                    ...(evento.valor != null
                        ? {
                            custom_data: {
                                value: evento.valor,
                                currency: evento.moneda ?? 'USD',
                            },
                        }
                        : {}),
                },
            ],
        };

        // Solo mientras se prueba desde el administrador de eventos. En cuanto
        // se saca la variable, los eventos pasan a contar de verdad.
        const testCode = Deno.env.get('META_TEST_EVENT_CODE');
        if (testCode) cuerpo.test_event_code = testCode;

        const res = await fetch(
            `${GRAPH}/${pixelId}/events?access_token=${encodeURIComponent(token)}`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(cuerpo),
            },
        );

        const texto = await res.text();
        if (!res.ok) {
            console.error('[meta] rechazado', res.status, texto.slice(0, 300));
            return;
        }
        console.log('[meta] evento enviado', evento.nombre, texto.slice(0, 200));
    } catch (e) {
        // Se traga a propósito. Que Meta esté caído no puede impedir que se
        // acredite una suscripción que el cliente ya pagó.
        console.error('[meta] fallo al enviar', evento.nombre, String(e));
    }
}
