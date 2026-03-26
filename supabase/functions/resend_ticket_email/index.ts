import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import QRCode from "npm:qrcode@1.5.3"
import { corsHeaders } from "../_shared/cors.ts"
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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  const ip = getClientIp(req)
  if (isRateLimited(`resend_ticket_email:${ip}`, 5, 60000)) {
      return rateLimitResponse(corsHeaders)
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    )

    // --- Parse body first (need _auth_token before auth) ---
    const body = await req.json().catch(() => ({}))
    const ticketId = body?.ticket_id as string | undefined
    const ping = body?.ping === true

    if (ping) {
      return new Response(
        JSON.stringify({ message: "pong", status: "ok" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      )
    }

    // --- JWT Authentication (with expired token fallback) ---
    const bodyToken = body?._auth_token
    const authHeader = req.headers.get("Authorization")
    const headerToken = authHeader?.replace("Bearer ", "") || null
    const token = bodyToken || headerToken
    if (!token) throw new Error("Sesión no encontrada. Por favor, cierre sesión y vuelva a iniciar.")

    let user: any = null

    const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(token)
    if (!authError && authData?.user) {
      user = authData.user
    } else {
      try {
        const payloadB64 = token.split('.')[1]
        if (!payloadB64) throw new Error('Invalid token')
        const payload = JSON.parse(atob(payloadB64))
        const userId = payload.sub
        if (!userId) throw new Error('No sub')
        const { data: profile } = await supabaseAdmin
          .from('users_profile').select('user_id, role, organization_id')
          .eq('user_id', userId).single()
        if (!profile) throw new Error('User not found')
        user = { id: userId, app_metadata: { role: profile.role, organization_id: profile.organization_id } }
        console.log(`[auth] Expired JWT fallback for ${userId}`)
      } catch (_e) {
        throw new Error("Sesión expirada. Por favor, cierre sesión y vuelva a iniciar.")
      }
    }

    // Verify caller role (admin or rrpp can resend)
    let callerRole = user.app_metadata?.role
    if (!callerRole) {
      const { data: roleProfile } = await supabaseAdmin
        .from("users_profile")
        .select("role")
        .eq("user_id", user.id)
        .single()
      callerRole = roleProfile?.role
    }
    if (!['admin', 'rrpp'].includes(callerRole ?? '')) {
      throw new Error("Forbidden: only Admin or RRPP can resend emails")
    }

    if (!ticketId) {
      throw new Error("Missing ticket_id")
    }

    const { data: ticket, error: ticketError } = await supabaseAdmin
      .from("tickets")
      .select("id, buyer_name, buyer_email, type, qr_token, event_id, events(name, date, venue, address, city, organization_id, timezone)")
      .eq("id", ticketId)
      .single()

    if (ticketError || !ticket) {
      throw new Error("Ticket not found")
    }

    // --- Organization verification ---
    let callerOrgId = user.app_metadata?.organization_id
    if (!callerOrgId) {
      const { data: profile } = await supabaseAdmin
        .from("users_profile")
        .select("organization_id")
        .eq("user_id", user.id)
        .single()
      callerOrgId = profile?.organization_id
    }
    if (callerOrgId && ticket.events?.organization_id && ticket.events.organization_id !== callerOrgId) {
      throw new Error("Ticket does not belong to your organization")
    }

    const eventName = ticket.events?.name ?? "tu evento"
    const eventDateStr = ticket.events?.date ?? null
    const dateLabel = eventDateStr
      ? parseWallClockDate(eventDateStr)
      : "Fecha por confirmar"
    const timeLabel = eventDateStr
      ? parseWallClockTime(eventDateStr)
      : "Horario por confirmar"
    const venueLabel = ticket.events?.venue ?? "Lugar por confirmar"
    const addressLabel = ticket.events?.address ?? ""
    const cityLabel = ticket.events?.city ?? ""

    let qrBuffer: Uint8Array | null = null
    if (ticket.qr_token) {
      try {
        qrBuffer = await QRCode.toBuffer(ticket.qr_token, {
          margin: 2,
          scale: 8,
          type: "png",
          color: { dark: "#000000", light: "#ffffff" },
        })
      } catch (_error) {
        qrBuffer = null
      }
    }

    const html = `
      <div style="font-family:Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:12px;">
        <h2 style="margin:0 0 12px 0;">Tu ticket fue reenviado</h2>
        <p>Hola ${escapeHtml(ticket.buyer_name ?? "invitado")},</p>
        <p>Reenviamos tu entrada para <strong>${escapeHtml(eventName)}</strong>.</p>
        <p><strong>Tipo de entrada:</strong> ${escapeHtml((ticket.type ?? "").toString().toUpperCase())}</p>
        <p><strong>Fecha:</strong> ${escapeHtml(dateLabel)}</p>
        <p><strong>Hora:</strong> ${escapeHtml(timeLabel)}</p>
        <p><strong>Lugar:</strong> ${escapeHtml(venueLabel)}</p>
        <p><strong>Dirección:</strong> ${escapeHtml(addressLabel)}${cityLabel ? `, ${escapeHtml(cityLabel)}` : ""}</p>
        <div style="margin-top:16px;padding:16px;border:1px dashed #d1d5db;border-radius:10px;text-align:center;">
          ${qrBuffer
            ? '<img src="cid:ticket-qr.png" alt="QR Ticket" style="width:220px;height:220px;" />'
            : '<p style="margin:0;color:#6b7280;">No se pudo adjuntar el QR en este envío.</p>'}
          <p style="margin:10px 0 0 0;font-size:12px;color:#374151;">Presenta este QR al ingresar.</p>
        </div>
        <p style="margin-top:18px;color:#6b7280;font-size:12px;">ID Ticket: ${ticket.id}</p>
      </div>
    `

    const attachments = qrBuffer
      ? [{
        filename: "ticket-qr.png",
        content: qrBuffer,
        cid: "ticket-qr.png",
        contentType: "image/png",
      }]
      : []

    await sendEmail(ticket.buyer_email, `Reenvío de entrada - ${eventName}`, html, attachments)

    await supabaseAdmin
      .from("tickets")
      .update({ email_sent_at: new Date().toISOString() })
      .eq("id", ticketId)

    return new Response(
      JSON.stringify({ message: "Email resent successfully" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    )
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error"
    return new Response(
      JSON.stringify({ error: message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
    )
  }
})
