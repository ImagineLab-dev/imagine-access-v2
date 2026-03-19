import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { createHmac } from "https://deno.land/std@0.168.0/node/crypto.ts"
import QRCode from "npm:qrcode@1.5.3"
import { corsHeaders } from "../_shared/cors.ts"
import { sendEmail } from "../_shared/email.ts"
import { getClientIp, isRateLimited, rateLimitResponse } from "../_shared/rate_limiter.ts"

/** Escape HTML special characters to prevent XSS in email templates */
function escapeHtml(str: string): string {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
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

        // 2. Get User Info from JWT
        const authHeader = req.headers.get('Authorization');
        if (!authHeader) throw new Error('No authorization header');

        const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''));
        if (authError || !user) throw new Error('Unauthorized');

        const userRole = user.app_metadata?.role || 'rrpp';
        const isAdmin = userRole === 'admin';

        // Block door role from creating tickets
        if (userRole === 'door') {
            throw new Error('Forbidden: door role cannot create tickets');
        }

        // 3. Get Input
        const { event_slug, type, price, buyer_name, buyer_email, buyer_phone, buyer_doc, request_id, promo_qty } = await req.json()

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
            .select('id, name, venue, address, city, date, organization_id')
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

        if (!callerOrgId) {
            throw new Error('Forbidden: caller has no organization assigned')
        }
        if (event.organization_id && event.organization_id !== callerOrgId) {
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
        if (validUntil) {
            const validUntilDate = new Date(validUntil);
            if (new Date() > validUntilDate) {
                throw new Error('Invitación expirada. Solo era válida hasta las ' + validUntilDate.toLocaleTimeString('es-ES', { hour: '2-digit', minute: '2-digit' }) + '.');
            }
        }

        // 6. Create tickets (batch for promo packs)
        const tickets: any[] = [];
        const qrBuffers: Buffer[] = [];
        const secret = Deno.env.get('QR_SECRET_KEY');
        if (!secret) throw new Error('QR_SECRET_KEY is not configured');

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
                    request_id: ticketCount > 1 ? `${request_id}_${i}` : request_id
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
        const eventDate = new Date(event.date);
        const formattedDate = eventDate.toLocaleDateString('es-ES', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
        const formattedTime = eventDate.toLocaleTimeString('es-ES', { hour: '2-digit', minute: '2-digit' });

        // Build QR sections for email
        const qrSections = tickets.map((t, idx) => `
            <div style="text-align: center; padding: 20px; background: #fff; margin: 20px 0; border: 1px dashed #ccc; border-radius: 12px;">
                ${ticketCount > 1 ? `<p style="color: #000; font-weight: bold; font-size: 14px; margin-bottom: 10px;">ENTRADA ${idx + 1} de ${ticketCount}</p>` : ''}
                <img src="cid:qrcode_${idx}" alt="QR Access ${idx + 1}" style="width: 250px; height: 250px;" />
                <p style="color: #000; font-weight: bold; font-size: 14px; margin-top: 15px; letter-spacing: 1px;">MUESTRA ESTE CÓDIGO AL INGRESAR</p>
                <p style="color: #999; font-size: 11px; margin-top: 5px;">ID: ${t.id}</p>
            </div>
        `).join('');

        const emailHtml = `
            <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #eee; border-radius: 12px; overflow: hidden; background-color: #fff;">
                <div style="background: #000; padding: 25px; text-align: center;">
                    <h1 style="color: #fff; margin: 0; font-size: 24px; letter-spacing: 2px;">IMAGINE ACCESS</h1>
                </div>
                <div style="padding: 40px 30px;">
                    <h2 style="color: #333; margin-top: 0;">¡Hola ${escapeHtml(buyer_name)}!</h2>
                    <p style="color: #555; font-size: 16px; line-height: 1.5;">Aquí tienes ${ticketCount > 1 ? `tus <strong>${ticketCount} accesos</strong>` : 'tu acceso confirmado'} para <strong>${escapeHtml(event.name)}</strong>.</p>
                    
                    <div style="margin: 30px 0; padding: 20px; background-color: #f9f9f9; border-radius: 8px; border-left: 4px solid #000;">
                        <table style="width: 100%; border-collapse: collapse;">
                            <tr>
                                <td style="padding: 5px 0; color: #777; font-size: 13px;">TIPO</td>
                                <td style="padding: 5px 0; color: #777; font-size: 13px;">FECHA Y HORA</td>
                            </tr>
                            <tr>
                                <td style="padding: 0 0 15px 0; color: #000; font-weight: bold; font-size: 16px;">${escapeHtml(type.toUpperCase())}${ticketCount > 1 ? ` x${ticketCount}` : ''}</td>
                                <td style="padding: 0 0 15px 0; color: #000; font-weight: bold; font-size: 16px;">${formattedDate}<br><span style="font-weight: normal; font-size: 14px;">A las ${formattedTime} hs</span></td>
                            </tr>
                            <tr>
                                <td colspan="2" style="padding: 5px 0; color: #777; font-size: 13px;">LUGAR</td>
                            </tr>
                            <tr>
                                <td colspan="2" style="padding:0; color: #000; font-weight: bold; font-size: 16px;">${escapeHtml(event.venue)}</td>
                            </tr>
                            <tr>
                                <td colspan="2" style="padding:0; color: #555; font-size: 14px;">${escapeHtml(event.address)}${event.city ? `, ${escapeHtml(event.city)}` : ''}</td>
                            </tr>
                            ${isInvitation && validUntil ? `<tr>
                                <td colspan="2" style="padding: 12px 0 5px 0; color: #777; font-size: 13px;">VÁLIDA HASTA</td>
                            </tr>
                            <tr>
                                <td colspan="2" style="padding:0; color: #c0392b; font-weight: bold; font-size: 16px;">⏰ ${new Date(validUntil).toLocaleTimeString('es-ES', { hour: '2-digit', minute: '2-digit' })} hs</td>
                            </tr>` : ''}
                        </table>
                    </div>

                    ${qrSections}
                </div>
                <div style="background-color: #f4f4f4; padding: 20px; text-align: center; color: #999; font-size: 12px;">
                    © ${new Date().getFullYear()} Imagine Access. Todos los derechos reservados.
                </div>
            </div>
        `;

        let email_sent = false;
        let email_error: string | null = null;

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
        console.error("Error:", error);
        return new Response(JSON.stringify({ error: error.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
    }
})

