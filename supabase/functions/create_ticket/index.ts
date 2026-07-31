import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { createHmac } from "https://deno.land/std@0.168.0/node/crypto.ts"
import QRCode from "npm:qrcode@1.5.3"
import { corsHeaders } from "../_shared/cors.ts"
import { esAdmin } from "../_shared/roles.ts"
import { bloqueEntrada, estilosEntrada } from "../_shared/ticket_layout.ts"
import { sendEmail } from "../_shared/email.ts"
import { getClientIp, isRateLimited, rateLimitResponse } from "../_shared/rate_limiter.ts"

/** Extract HH:MM directly from an ISO date string (wall-clock time, no TZ conversion) */
function parseWallClockTime(isoStr: string): string {
    const m = String(isoStr).match(/T(\d{2}):(\d{2})/);
    return m ? `${m[1]}:${m[2]}` : '--:--';
}

/** Format the date portion from an ISO string (weekday, day, month, year) */
function parseWallClockDate(isoStr: string): string {
    const m = String(isoStr).match(/(\d{4})-(\d{2})-(\d{2})/);
    if (!m) return 'Fecha por confirmar';
    const d = new Date(Date.UTC(parseInt(m[1]), parseInt(m[2]) - 1, parseInt(m[3])));
    return d.toLocaleDateString('es-AR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
}

/** Escape HTML special characters to prevent XSS in email templates */
function escapeHtml(str: string): string {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

/** Get current wall-clock time in a timezone using Deno/V8 ICU data.
 *  Returns naive ISO string like "2026-03-25T11:38:00" (no offset). */
function getLocalISO(tz: string, date?: Date): string {
    const d = date ?? new Date();
    const f = new Intl.DateTimeFormat('en-CA', {
        timeZone: tz,
        year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit', second: '2-digit',
        hour12: false,
    });
    const p = Object.fromEntries(
        f.formatToParts(d).map(x => [x.type, x.value])
    );
    const h = p.hour === '24' ? '00' : p.hour;
    return `${p.year}-${p.month}-${p.day}T${h}:${p.minute}:${p.second}`;
}

/** Alias for backward-compat: get current wall-clock time */
function getNowLocalISO(tz: string): string {
    return getLocalISO(tz);
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    const ip = getClientIp(req)
    if (isRateLimited(`create_ticket:${ip}`, 30, 60000)) {
        return rateLimitResponse(corsHeaders)
    }

    try {
        // 1. Initialize Supabase Admin Client (Admin Privileges for Quotas & Audit)
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // 2. Parse body first (need _auth_token before auth)
        const body = await req.json();
        const { event_slug, type, price, buyer_name, buyer_email, buyer_phone, buyer_doc, request_id, promo_qty } = body;

        // 3. Get User Info from JWT (with fallback for expired tokens)
        // Try body token first (Flutter passes it to survive session clearing), then header
        const bodyToken = body._auth_token;
        const authHeader = req.headers.get('Authorization');
        const headerToken = authHeader?.replace('Bearer ', '') || null;
        const token = bodyToken || headerToken;
        if (!token) throw new Error('Sesión no encontrada. Por favor, cierre sesión y vuelva a iniciar.');

        let user: any = null;

        // Try official verification first
        const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(token);
        if (!authError && authData?.user) {
            user = authData.user;
        } else {
            // Fallback: decode JWT payload to extract user identity
            try {
                const payloadB64 = token.split('.')[1];
                if (!payloadB64) throw new Error('Invalid token format');
                const payload = JSON.parse(atob(payloadB64));
                const userId = payload.sub;
                if (!userId) throw new Error('No sub in token');

                // Verify user exists in DB using admin client
                const { data: profile } = await supabaseAdmin
                    .from('users_profile')
                    .select('user_id, role, organization_id')
                    .eq('user_id', userId)
                    .single();

                if (!profile) throw new Error('User not found');

                user = {
                    id: userId,
                    app_metadata: {
                        role: profile.role,
                        organization_id: profile.organization_id,
                    },
                };
                console.log(`[auth] Used expired JWT fallback for user ${userId}, role=${profile.role}`);
            } catch (fallbackErr) {
                console.error('[auth] JWT fallback failed:', fallbackErr.message);
                throw new Error('Sesión expirada. Por favor, cierre sesión y vuelva a iniciar.');
            }
        }

        const userRole = user.app_metadata?.role || 'rrpp';
        const isAdmin = esAdmin(userRole);

        // Block door role from creating tickets
        if (userRole === 'door') {
            throw new Error('Forbidden: door role cannot create tickets');
        }

        // 3b. Input validation
        if (!event_slug || typeof event_slug !== 'string') {
            throw new Error('Event slug is required');
        }
        if (!type || typeof type !== 'string') {
            throw new Error('Ticket type is required');
        }
        if (!buyer_name || typeof buyer_name !== 'string' || buyer_name.trim().length === 0) {
            throw new Error('Buyer name is required');
        }
        if (buyer_name.length > 200) {
            throw new Error('Buyer name is too long (max 200 characters)');
        }
        if (buyer_email) {
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
            if (!emailRegex.test(buyer_email)) {
                throw new Error('Invalid buyer email format');
            }
        }
        // Validate promo_qty (1-20, defaults to 1)
        const ticketCount = Math.max(1, Math.min(20, Math.floor(Number(promo_qty) || 1)));

        // 4. Get Event
        const { data: event, error: eventError } = await supabaseAdmin
            .from('events')
            .select('id, name, venue, address, city, date, organization_id, timezone, image_url')
            .eq('slug', event_slug)
            .single()

        if (eventError || !event) throw new Error('Event not found')

        // 4b. ORG VERIFICATION — Ensure event belongs to caller's organization
        let callerOrgId = user.app_metadata?.organization_id
        if (!callerOrgId) {
            const { data: profile } = await supabaseAdmin
                .from('users_profile')
                .select('organization_id')
                .eq('user_id', user.id)
                .single()
            callerOrgId = profile?.organization_id
        }

        // Org check: if both caller and event have org_id, they must match.
        // Allow legacy events (no organization_id) and callers without org.
        if (callerOrgId && event.organization_id && event.organization_id !== callerOrgId) {
            throw new Error('Event does not belong to your organization')
        }

        // 4c. Resolve ticket_type from DB (moved up so isInvitation is available for quota & price logic)
        let ticketTypeId: string | null = null
        let validUntil: string | null = null
        let isInvitation = false
        const { data: ttRow } = await supabaseAdmin
            .from('ticket_types')
            .select('id, valid_until, category, tolerance_minutes')
            .eq('event_id', event.id)
            .eq('name', type)
            .maybeSingle()
        if (ttRow) {
            ticketTypeId = ttRow.id
            validUntil = ttRow.valid_until ?? null
            isInvitation = ttRow.category === 'invitation'
        }

        // 4d. Price validation (requires isInvitation to be resolved)
        if (!isInvitation) {
            if (price == null || typeof price !== 'number' || price < 0 || price > 999999999) {
                throw new Error('Price must be a non-negative number (max 999999999)');
            }
        }

        // 5. ENFORCE RBAC QUOTAS (if RRPP and Invitation)
        if (isInvitation && !isAdmin) {
            console.log(`Checking quota for user on event ${event.id}`);
            const { data: quotaResult, error: rpcError } = await supabaseAdmin.rpc('increment_event_quota', {
                p_event_id: event.id,
                p_user_id: user.id
            });

            if (rpcError || !quotaResult) {
                console.error("Quota increment failed:", rpcError);
                throw new Error('Cupo de invitaciones agotado o no asignado');
            }
        }

        // 5b. Enforce valid_until cutoff — block ticket creation after expiry
        // valid_until is stored as wall-clock time (no UTC conversion needed)
        if (validUntil) {
            const eventTZ = event.timezone || 'America/Asuncion';
            const nowLocalISO = getNowLocalISO(eventTZ);
            // Strip any trailing offset (+00:00 or Z) to get naive wall-clock ISO
            const vuWallClock = String(validUntil).replace(/([+-]\d{2}(:\d{2})?|Z)$/, '');
            console.log(`[valid_until] eventTZ=${eventTZ} now=${nowLocalISO} valid_until_wall=${vuWallClock}`);
            if (nowLocalISO > vuWallClock) {
                throw new Error('Invitación expirada. Solo era válida hasta las ' + parseWallClockTime(vuWallClock) + ' hs.');
            }
        }

        // 6. Create tickets (batch for promo packs)
        const tickets: any[] = [];
        const qrBuffers: Buffer[] = [];
        const secret = Deno.env.get('QR_SECRET_KEY');
        if (!secret) throw new Error('QR_SECRET_KEY is not configured');

        // For promo packs: generate a shared pack ID so reports count packs, not individual tickets
        const isPromo = ttRow?.category === 'promo';
        const promoPackId = (isPromo && ticketCount >= 1) ? crypto.randomUUID() : null;

        for (let i = 0; i < ticketCount; i++) {
            // Generate Secure QR Token
            const qr_payload = {
                event_id: event.id,
                type: type,
                email: buyer_email,
                timestamp: Date.now(),
                issuer: user.id,
                batch_index: i
            }
            const payloadStr = JSON.stringify(qr_payload)
            const signature = createHmac('sha256', secret).update(payloadStr).digest('hex')
            const qr_token = `${btoa(payloadStr)}.${signature}`

            // Create Ticket Record
            // For promo packs: only the first ticket carries the pack price, rest are 0
            const ticketPrice = isInvitation ? 0 : (i === 0 ? price : 0);
            // Each ticket in a batch gets its own unique request_id (request_id is UUID)
            const ticketRequestId = ticketCount > 1 ? crypto.randomUUID() : request_id;
            const { data: ticket, error: ticketError } = await supabaseAdmin
                .from('tickets')
                .insert({
                    event_id: event.id,
                    ticket_type_id: ticketTypeId,
                    type,
                    price: ticketPrice,
                    buyer_name,
                    buyer_email,
                    buyer_phone,
                    buyer_doc,
                    qr_token,
                    status: 'valid',
                    created_by: user.id,
                    request_id: ticketRequestId,
                    promo_pack_id: promoPackId
                })
                .select()
                .single()

            if (ticketError) throw ticketError
            tickets.push(ticket)

            // Audit log
            await supabaseAdmin.from('audit_logs').insert({
                user_id: user.id,
                action: 'create_ticket',
                resource: `ticket:${ticket.id}`,
                details: { type, event_slug, buyer_email, batch_index: i, batch_total: ticketCount },
                ip_address: req.headers.get('x-real-ip') || req.headers.get('x-forwarded-for')
            });

            // Generate QR Image
            const qrBuffer = await QRCode.toBuffer(qr_token, { margin: 2, scale: 8 });
            qrBuffers.push(qrBuffer);
        }

        // 7. Send Email (single email with all QR codes)
        // event.date is stored as wall-clock time — read it directly
        const formattedDate = parseWallClockDate(event.date);
        const formattedTime = parseWallClockTime(event.date);

        // Entrada horizontal: QR a la izquierda, datos al medio, arte a la
        // derecha. La maqueta vive en _shared/ticket_layout.ts porque se arma
        // con tablas y atributos viejos por compatibilidad con Outlook, y eso
        // ensucia mucho si se mezcla con la logica de negocio.
        let organizador: string | undefined
        if (event.organization_id) {
            const { data: org } = await supabaseAdmin
                .from('organizations').select('name').eq('id', event.organization_id).single()
            organizador = org?.name ?? undefined
        }

        const qrSections = tickets.map((t, idx) => bloqueEntrada({
            qrCid: `qrcode_${idx}`,
            numero: idx + 1,
            total: ticketCount,
            ticketId: t.id,
            eventoNombre: event.name,
            fecha: formattedDate,
            hora: formattedTime,
            lugar: event.venue,
            direccion: event.address,
            ciudad: event.city,
            tipo: type,
            organizador,
            imagenUrl: event.image_url,
        })).join('')

        const emailHtml = `
            ${estilosEntrada}
            <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #eee; border-radius: 12px; overflow: hidden; background-color: #fff;">
                <div style="background: #000; padding: 25px; text-align: center;">
                    <h1 style="color: #fff; margin: 0; font-size: 24px; letter-spacing: 2px;">IMAGINE ACCESS</h1>
                </div>
                <div style="padding: 40px 30px;">
                    <h2 style="color: #333; margin-top: 0;">¡Hola ${escapeHtml(buyer_name)}!</h2>
                    <p style="color: #555; font-size: 16px; line-height: 1.5;">Aquí tienes ${ticketCount > 1 ? `tus <strong>${ticketCount} accesos</strong>` : 'tu acceso confirmado'} para <strong>${escapeHtml(event.name)}</strong>.</p>
                    
                    <!-- El recuadro de datos se eliminó: repetía tipo, fecha y
                         lugar, que ya vienen dentro de la entrada. -->
                    ${qrSections}
                </div>
                <div style="background-color: #f4f4f4; padding: 20px; text-align: center; color: #999; font-size: 12px;">
                    © ${new Date().getFullYear()} Imagine Access. Todos los derechos reservados.
                </div>
            </div>
        `;

        let email_sent = false;
        let email_error: string | null = null;

        if (buyer_email) {
            try {
                const attachments = qrBuffers.map((buf, idx) => ({
                    filename: `ticket-qr-${idx + 1}.png`,
                    content: buf,
                    cid: `qrcode_${idx}`,
                    contentType: 'image/png'
                }));
                const subject = ticketCount > 1
                    ? `Tus ${ticketCount} entradas para ${event.name}`
                    : `Tu entrada para ${event.name}`;
                await sendEmail(buyer_email, subject, emailHtml, attachments);
                // Mark all tickets as email sent
                const ticketIds = tickets.map((t: any) => t.id);
                await supabaseAdmin.from('tickets').update({ email_sent_at: new Date() }).in('id', ticketIds);
                email_sent = true;
            } catch (e) {
                console.error("Email error:", e);
                email_error = e instanceof Error ? e.message : String(e);
            }
        }

        // Return first ticket for backward compat, plus batch info
        return new Response(
            JSON.stringify({
                ...tickets[0],
                email_sent,
                email_error,
                tickets_created: tickets.length,
                ticket_ids: tickets.map((t: any) => t.id),
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error("Error:", error?.message);
        return new Response(JSON.stringify({ error: error.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
    }
})

