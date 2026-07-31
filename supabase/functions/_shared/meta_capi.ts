// API de Conversiones de Meta.
//
// Existe porque el pago termina en checkout.dlocalgo.com, un dominio que no
// controlamos: el pixel del navegador jamás puede ver esa compra. La única
// forma de atribuir la conversión a la campaña que la trajo es mandarla desde
// el servidor, cuando dLocal confirma el cobro.
//
// Reparto de eventos:
//   - Servidor solo   → Purchase                  (ocurre fuera de nuestro sitio)
//   - Ambos caminos   → PageView, ClicProbarGratis (ver abajo)
//
// Los de la landing van por LOS DOS lados a propósito, con el MISMO event_id.
// El motivo está medido: la campaña del 29/07/2026 registró 70 clics al enlace
// y solo 24 vistas de landing. Los 46 que faltan no se fueron a ningún lado —
// son navegadores que bloquearon el píxel, casi todos iOS. Meta contaba el
// clic y perdía la llegada.
//
// Eso no es solo un reporte feo. Con el objetivo OUTCOME_SALES, Meta aprende a
// quién mostrar el anuncio con las señales que recibe: viendo un tercio de las
// llegadas, optimiza con un tercio de los datos y gasta peor el presupuesto.
//
// La copia del servidor no la puede bloquear ningún navegador. Meta une las dos
// por `event_name` + `event_id` y cuenta UNA sola. Por eso el identificador se
// genera una única vez en el navegador y viaja a los dos destinos: si cada lado
// generara el suyo, se contaría doble, que es peor que perder eventos.

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

    // ---------------------------------------------------------------- Cotejo
    //
    // Todo lo de acá abajo existe para que Meta pueda decir "esta persona del
    // servidor es la misma que vio el anuncio". Sin nada de esto un evento de
    // servidor llega anónimo: cuenta como conversión pero no se atribuye a
    // ninguna campaña, que para optimizar es casi lo mismo que no mandarlo.

    /** Cookie `_fbp`: identificador que el píxel le pone al navegador. */
    fbp?: string | null;
    /** Cookie `_fbc`: de qué clic de anuncio vino. Es lo que ata la conversión
     *  a la campaña, así que es el más valioso de los cuatro. */
    fbc?: string | null;
    /** IP de quien navega, NO la del servidor. La toma la Edge Function del
     *  request; si se mandara la del contenedor, todos los eventos parecerían
     *  venir de la misma persona. */
    ip?: string | null;
    userAgent?: string | null;

    /** Momento real del evento, en segundos. Viene del navegador para que la
     *  copia del servidor y la del píxel caigan en el mismo instante. Si se
     *  usara la hora del servidor, un reenvío tardío las separaría y Meta
     *  podría no reconocerlas como el mismo evento. */
    momento?: number | null;

    /** Datos propios del evento (`donde`, `texto`…). Se mandan tal cual. */
    datos?: Record<string, unknown> | null;
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
        // `fbp` y `fbc` van SIN hashear: ya son identificadores opacos que
        // genera el propio Meta, y hashearlos los volvería irreconocibles.
        if (evento.fbp) userData.fbp = evento.fbp;
        if (evento.fbc) userData.fbc = evento.fbc;
        if (evento.ip) userData.client_ip_address = evento.ip;
        if (evento.userAgent) userData.client_user_agent = evento.userAgent;

        // `custom_data` se arma una sola vez: antes se construía solo cuando
        // había importe, así que un evento con datos propios y sin valor los
        // perdía en el camino.
        const custom: Record<string, unknown> = { ...(evento.datos ?? {}) };
        if (evento.valor != null) {
            custom.value = evento.valor;
            custom.currency = evento.moneda ?? 'USD';
        }

        const cuerpo: Record<string, unknown> = {
            data: [
                {
                    event_name: evento.nombre,
                    event_time: evento.momento ?? Math.floor(Date.now() / 1000),
                    event_id: evento.eventId,
                    // 'website' y no 'other': la conversión se origina en un
                    // flujo web aunque la confirme un webhook.
                    action_source: 'website',
                    event_source_url: evento.urlOrigen ?? 'https://imaginecloud.digital/',
                    user_data: userData,
                    ...(Object.keys(custom).length > 0 ? { custom_data: custom } : {}),
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
