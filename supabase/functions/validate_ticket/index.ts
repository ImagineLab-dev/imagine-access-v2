import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { createHmac } from "https://deno.land/std@0.168.0/node/crypto.ts"
import { corsHeaders } from "../_shared/cors.ts"
import { getClientIp, isRateLimited, rateLimitResponse } from "../_shared/rate_limiter.ts"

/** Extract HH:MM from a timestamp string */
function parseWallClockTime(isoStr: string): string {
    const m = String(isoStr).match(/T?(\d{2}):(\d{2})/);
    return m ? `${m[1]}:${m[2]}` : '--:--';
}

/** Get current wall-clock time in a timezone using Deno/V8 ICU data.
 *  Returns ISO string like "2026-03-25T02:30:00" (naive, no offset). */
function getNowLocalISO(tz: string): string {
    const now = new Date();
    const f = new Intl.DateTimeFormat('en-CA', {
        timeZone: tz,
        year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit', second: '2-digit',
        hour12: false,
    });
    const p = Object.fromEntries(
        f.formatToParts(now).map(x => [x.type, x.value])
    );
    const h = p.hour === '24' ? '00' : p.hour;
    return `${p.year}-${p.month}-${p.day}T${h}:${p.minute}:${p.second}`;
}

/** Check if a ticket is expired using the valid_until already fetched from ticket_types.
 *  Uses Deno's up-to-date V8/ICU tzdata for accurate wall-clock time comparison.
 *  Mirrors the same logic as create_ticket to stay consistent. */
function checkExpiration(
    ticket: Record<string, any>,
): Response | null {
    const validUntil: string | null = ticket.ticket_types?.valid_until ?? null;
    console.log(`[expiry-debug] ticket_types=${JSON.stringify(ticket.ticket_types)} valid_until=${validUntil}`);
    if (!validUntil) return null; // No expiry set → allow

    const eventTZ = ticket.events?.timezone || 'America/Asuncion';
    const toleranceMinutes: number = ticket.ticket_types?.tolerance_minutes ?? 0;
    const nowLocalISO = getNowLocalISO(eventTZ);

    // Strip timezone offset to get wall-clock value (same as create_ticket logic)
    const vuWallClock = String(validUntil).replace(/([+-]\d{2}(:\d{2})?|Z)$/, '').replace(/\.\d+$/, '');

    // Apply tolerance by adding minutes to cutoff.
    // Append 'Z' to force UTC parsing so setUTCMinutes is unambiguous.
    let cutoffISO = vuWallClock;
    if (toleranceMinutes > 0) {
        const cutoffDate = new Date(vuWallClock + 'Z');
        cutoffDate.setUTCMinutes(cutoffDate.getUTCMinutes() + toleranceMinutes);
        cutoffISO = cutoffDate.toISOString().slice(0, 19);
    }

    console.log(`[expiry] tz=${eventTZ} now=${nowLocalISO} valid_until_wall=${vuWallClock} cutoff=${cutoffISO} tolerance=${toleranceMinutes}m`);

    if (nowLocalISO > cutoffISO) {
        const timeStr = parseWallClockTime(vuWallClock);
        return new Response(JSON.stringify({
            success: false,
            expired: true,
            error: `Entrada inválida. Solo era válida hasta las ${timeStr} hs.`,
            valid_until: validUntil,
            debug: { server_now: nowLocalISO, cutoff: cutoffISO },
            ticket: ticket
        }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 });
    }

    return null; // Not expired → allow
}

/** Constant-time comparison to prevent timing attacks on HMAC signatures */
function timingSafeEqual(a: string, b: string): boolean {
    if (a.length !== b.length) return false;
    const encoder = new TextEncoder();
    const bufA = encoder.encode(a);
    const bufB = encoder.encode(b);
    let diff = 0;
    for (let i = 0; i < bufA.length; i++) {
        diff |= bufA[i] ^ bufB[i];
    }
    return diff === 0;
}

const toHex = (bytes: Uint8Array) =>
    Array.from(bytes).map((byte) => byte.toString(16).padStart(2, '0')).join('')

const sha256Hex = async (value: string) => {
    const encoded = new TextEncoder().encode(value)
    const digest = await crypto.subtle.digest('SHA-256', encoded)
    return toHex(new Uint8Array(digest))
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const SAFE_ID_REGEX = /^[a-zA-Z0-9_-]{1,128}$/

const verifyDevicePin = async (device: Record<string, unknown>, pin: string) => {
    const pinHash = typeof device.pin_hash === 'string' ? device.pin_hash : null
    const pinSalt = typeof device.pin_salt === 'string' ? device.pin_salt : null
    if (pinHash && pinSalt) {
        const calculated = await sha256Hex(`${pinSalt}:${pin}`)
        return calculated === pinHash
    }
    const legacyPin = typeof device.pin === 'string' ? device.pin : null
    return !!legacyPin && legacyPin === pin
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    const ip = getClientIp(req)
    if (isRateLimited(`validate_ticket:${ip}`, 60, 60000)) {
        return rateLimitResponse(corsHeaders)
    }

    try {
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const { method, qr_token, buyer_doc, event_id, notes, device_id, pin, request_id, ticket_id, _auth_token } = await req.json()

        // 1. AUTENTICACIÓN — OBLIGATORIA.
        //
        // Era "best-effort, for audit only": si no llegaba credencial, la
        // verificación de organización de más abajo se salteaba entera y
        // cualquiera podía marcar un ticket como usado sabiendo solo su id.
        // Verificado con un POST sin ninguna credencial: devolvió allowed:true,
        // dejó el ticket en 'used' y entregó nombre, correo, teléfono y
        // documento del comprador a quien lo pidió.
        //
        // Se puede quemar la entrada de alguien de forma remota para que le
        // rechacen el acceso en la puerta. Y había ids de tickets reales
        // commiteados en una migración del repositorio.
        let callerRole: string | null = null;
        let callerOrgId: string | null = null;
        let callerUserId: string | null = null;
        let callerDeviceId: string | null = null;

        // El token del usuario viaja en el CUERPO, no en la cabecera: el
        // cliente pone la anon key en Authorization y con eso `getUser` nunca
        // identificaba a nadie. Es el mismo mecanismo que ya usaba
        // create_ticket, que por eso sí sabía quién llamaba.
        const authHeader = req.headers.get('Authorization');
        const headerToken = authHeader?.startsWith('Bearer ')
            ? authHeader.replace('Bearer ', '')
            : null;
        const userToken = _auth_token || headerToken;

        if (userToken) {
            try {
                const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(userToken);
                if (!authError && user) {
                    callerUserId = user.id;
                    callerRole = user.app_metadata?.role;
                    callerOrgId = user.app_metadata?.organization_id;
                    if (!callerRole || !callerOrgId) {
                        const { data: profile } = await supabaseAdmin
                            .from('users_profile')
                            .select('role, organization_id')
                            .eq('user_id', user.id)
                            .single();
                        callerRole = callerRole || profile?.role;
                        callerOrgId = callerOrgId || profile?.organization_id;
                    }
                }
            } catch (_e) { /* JWT failed — continue without user context */ }
        }

        // Try device auth (best-effort — for audit / org check)
        if (device_id && pin) {
            try {
                if (UUID_REGEX.test(device_id) || SAFE_ID_REGEX.test(device_id)) {
                    const { data: device, error: deviceError } = await supabaseAdmin
                        .from('devices')
                        .select('*')
                        .eq('device_id', device_id)
                        .single();
                    if (!deviceError && device) {
                        const pinValid = await verifyDevicePin(device as Record<string, unknown>, String(pin));
                        if (pinValid && device.enabled) {
                            callerRole = callerRole || 'door';
                            callerOrgId = callerOrgId || device.organization_id;
                            callerDeviceId = device.device_id;
                        }
                    }
                }
            } catch (_e) { /* device auth failed — continue */ }
        }

        // Sin organización identificada no se valida nada. Es la línea que
        // convierte el chequeo de organización de más abajo en obligatorio:
        // antes, un llamante anónimo simplemente lo esquivaba.
        if (!callerOrgId) {
            return new Response(JSON.stringify({
                success: false,
                allowed: false,
                result: 'unauthorized',
                error: 'Authentication required to validate tickets'
            }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 });
        }

        let ticket;

        // 2. VALIDATE BY QR
        if (method === 'qr') {
            if (!qr_token) throw new Error("QR Token missing");

            // Verify Signature
            //
            // Se recorta el token: un lector puede devolver el texto con un
            // salto de línea o un espacio al final, y eso desplaza la firma lo
            // suficiente como para que la comparación falle por longitud. El
            // QR sería correcto y aun así rechazaría a la persona.
            const tokenLimpio = String(qr_token).trim();
            const partes = tokenLimpio.split('.');
            const payloadB64 = (partes[0] ?? '').trim();
            const signature = (partes[1] ?? '').trim();

            let payloadStr: string;
            try {
                payloadStr = atob(payloadB64);
            } catch (_e) {
                console.warn('[qr] base64 ilegible', {
                    largo: tokenLimpio.length,
                    partes: partes.length,
                    inicio: tokenLimpio.slice(0, 24),
                });
                throw new Error("Invalid QR Signature");
            }
            const secret = Deno.env.get('QR_SECRET_KEY')
            if (!secret) {
                throw new Error('QR_SECRET_KEY is not configured');
            }
            const expectedSig = createHmac('sha256', secret).update(payloadStr).digest('hex');

            if (!timingSafeEqual(signature, expectedSig)) {
                // Diagnóstico. Un fallo de firma sin contexto es imposible de
                // investigar: no se sabe si el lector leyó mal, si el token vino
                // de otro entorno o si el QR es de otro sistema. No se registra
                // la firma esperada, que revelaría información sobre el secreto.
                console.warn('[qr] firma no coincide', {
                    largo_token: tokenLimpio.length,
                    partes: partes.length,
                    largo_firma_recibida: signature.length,
                    largo_firma_esperada: expectedSig.length,
                    payload: payloadStr.slice(0, 120),
                });
                throw new Error("Invalid QR Signature");
            }


            // Fetch Ticket
            const { data, error } = await supabaseAdmin
                .from('tickets')
                .select('*, events(name, timezone, date), ticket_types(valid_until, tolerance_minutes)')
                .eq('qr_token', qr_token)
                .single()

            if (error || !data) throw new Error("Ticket not found");
            ticket = data;

            // Check Expiration (tolerance_minutes extends the cutoff internally)
            const qrExpired = checkExpiration(ticket);
            if (qrExpired) return qrExpired;

        }
        // 3. VALIDATE BY DOCUMENT
        else if (method === 'doc') {
            if (!buyer_doc || !event_id) throw new Error("Document or Event ID missing");
            if (!notes) throw new Error("Notes (Motivo) required for manual entry");

            const { data, error } = await supabaseAdmin
                .from('tickets')
                .select('*, events(name, timezone, date), ticket_types(valid_until, tolerance_minutes)')
                .eq('buyer_doc', buyer_doc)
                .eq('event_id', event_id)
                .eq('status', 'valid')
                .maybeSingle()

            if (error) throw error;
            if (!data) throw new Error("Ticket not found or already used");
            ticket = data;

            // Check Expiration
            const docExpired = checkExpiration(ticket);
            if (docExpired) return docExpired;
        }
        // 4. VALIDATE BY TICKET_ID (Generic for any staff manual selection)
        else if (method === 'id') {
            // ticket_id is now destructured at the top
            if (!ticket_id) throw new Error("Ticket ID missing");
            if (!notes) throw new Error("Notes required for manual entry");

            const { data, error } = await supabaseAdmin
                .from('tickets')
                .select('*, events(name, timezone, date), ticket_types(valid_until, tolerance_minutes)')
                .eq('id', ticket_id)
                .single();

            if (error || !data) throw new Error("Ticket not found");
            ticket = data;

            // Check Expiration
            const idExpired = checkExpiration(ticket);
            if (idExpired) return idExpired;
        }
        else {
            throw new Error("Invalid validation method");
        }

        // 3.5 EVENT VERIFICATION — el ticket tiene que ser DEL evento que la
        // puerta tiene seleccionado.
        //
        // La verificación de organización de más abajo impide usar el ticket de
        // otro cliente, pero no el de OTRO EVENTO DEL MISMO cliente. Sin esto,
        // en una productora que hace fiestas todas las semanas alguien compra
        // la entrada barata de dentro de un mes y entra con ella esta noche —
        // firma válida, ticket existente, organización correcta.
        //
        // Solo aplica cuando la puerta manda el evento. Hoy lo manda siempre,
        // incluso en la cola sin conexión, que reenvía el mismo cuerpo; la
        // condición está por si alguna integración futura no lo hace, para que
        // no falle de forma silenciosa.
        if (event_id && ticket.event_id && ticket.event_id !== event_id) {
            return new Response(JSON.stringify({
                success: false,
                allowed: false,
                result: 'wrong_event',
                // El nombre del evento va en el mensaje porque es lo que le
                // permite al operador explicárselo a la persona en la puerta.
                event_name: ticket.events?.name ?? null,
                error: `Ticket belongs to another event: ${ticket.events?.name ?? ticket.event_id}`,
                ticket: ticket
            }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 });
        }

        // 4. ORG VERIFICATION — Ensure ticket belongs to caller's organization
        if (callerOrgId) {
            const { data: eventData } = await supabaseAdmin
                .from('events')
                .select('organization_id')
                .eq('id', ticket.event_id)
                .single()

            if (eventData?.organization_id && eventData.organization_id !== callerOrgId) {
                throw new Error('Ticket does not belong to your organization')
            }
        }

        // 5. ATOMIC CHECKIN
        // Check if already used
        if (ticket.status !== 'valid') {
            return new Response(JSON.stringify({
                success: false,
                allowed: false,
                result: 'already_used',
                error: `Ticket already used at ${ticket.scanned_at || 'unknown time'}`,
                ticket: ticket
            }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 });
        }

        // Handle Device ID (FK Constraint)
        let final_device_id = device_id;
        if (final_device_id) {
            const { data: deviceExists } = await supabaseAdmin
                .from('devices')
                .select('device_id')
                .eq('device_id', final_device_id)
                .maybeSingle();

            if (!deviceExists) {
                console.log(`Device ${final_device_id} not registered. Defaulting to NULL.`);
                final_device_id = null;
            }
        }

        // Atomically update ticket status (prevents TOCTOU race)
        const { data: updatedTicket, error: atomicUpdateError } = await supabaseAdmin
            .from('tickets')
            .update({
                status: 'used',
                scanned_at: new Date().toISOString()
            })
            .eq('id', ticket.id)
            .eq('status', 'valid')
            .select('id')
            .maybeSingle();

        if (atomicUpdateError) {
            throw new Error(`Failed to update ticket: ${atomicUpdateError.message}`);
        }

        if (!updatedTicket) {
            throw new Error('Ticket already scanned (concurrent validation detected)');
        }

        // Insert record in checkins
        const { error: checkinError } = await supabaseAdmin
            .from('checkins')
            .insert({
                ticket_id: ticket.id,
                event_id: ticket.event_id,
                operator_user: callerUserId,
                device_id: callerDeviceId || final_device_id,
                method: method,
                result: 'allowed',
                notes: notes,
                request_id: request_id
            });

        if (checkinError) {
            if (checkinError.message.includes('unique constraint')) {
                // Si el error es por contienda en request_id, significa que el celular ya había mandado el checkin
                // y es seguro resolver el caso offline devolviendo 200/201
                if (checkinError.message.includes('checkins_request_id_unique') || checkinError.message.includes('request_id')) {
                    console.log(`Idempotent offline scan detected for request: ${request_id}`);
                    return new Response(JSON.stringify({
                        success: true,
                        warning: 'Already synced from offline queue',
                        ticket: ticket
                    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })
                }
                throw new Error("Ticket already scanned");
            }
            throw checkinError;
        }

        // 5. AUDIT LOG
        await supabaseAdmin.from('audit_logs').insert({
            user_id: callerUserId,
            action: 'validate_ticket',
            resource: `ticket:${ticket.id}`,
            details: { method, event_id: ticket.event_id, device_id: callerDeviceId },
            ip_address: req.headers.get('x-real-ip') || req.headers.get('x-forwarded-for'),
            organization_id: callerOrgId
        });

        return new Response(
            JSON.stringify({ success: true, allowed: true, result: 'allowed', ticket }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('validate_ticket error:', error.message, error.stack);
        return new Response(
            JSON.stringify({ error: error.message }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
        )
    }
})
