import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { getClientIp, isRateLimited, rateLimitResponse } from "../_shared/rate_limiter.ts"

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    const ip = getClientIp(req)
    if (isRateLimited(`device_dashboard:${ip}`, 60, 60000)) {
        return rateLimitResponse(corsHeaders)
    }

    try {
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const { device_id, pin, event_id } = await req.json()

        if (!device_id || !pin || !event_id) {
            throw new Error("device_id, pin, and event_id are required")
        }

        // Authenticate device
        const { data: device, error: devErr } = await supabaseAdmin
            .from('devices')
            .select('device_id, organization_id, enabled, pin_hash, pin_salt, pin')
            .eq('device_id', device_id)
            .single()

        if (devErr || !device) throw new Error("Device not found")
        if (!device.enabled) throw new Error("Device is disabled")

        // Verify PIN
        const pinHash = device.pin_hash
        const pinSalt = device.pin_salt
        let pinValid = false
        if (pinHash && pinSalt) {
            const encoded = new TextEncoder().encode(`${pinSalt}:${pin}`)
            const digest = await crypto.subtle.digest('SHA-256', encoded)
            const hex = Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('')
            pinValid = hex === pinHash
        } else {
            pinValid = device.pin === pin
        }
        if (!pinValid) throw new Error("Invalid credentials")

        // Verify event belongs to device's org
        const { data: event, error: evErr } = await supabaseAdmin
            .from('events')
            .select('id, organization_id')
            .eq('id', event_id)
            .single()

        if (evErr || !event) throw new Error("Event not found")
        if (event.organization_id !== device.organization_id) {
            throw new Error("Event does not belong to your organization")
        }

        // Get dashboard metrics using direct queries with service_role
        const eid = event_id

        const [totalRes, scannedRes, manualRes, recentRes] = await Promise.all([
            supabaseAdmin.from('tickets').select('id', { count: 'exact', head: true }).eq('event_id', eid),
            supabaseAdmin.from('checkins').select('ticket_id', { count: 'exact', head: true }).eq('event_id', eid).eq('result', 'allowed'),
            supabaseAdmin.from('checkins').select('ticket_id', { count: 'exact', head: true }).eq('event_id', eid).eq('result', 'allowed').neq('method', 'qr'),
            supabaseAdmin.from('checkins').select('*, tickets(buyer_name, type)').eq('event_id', eid).order('scanned_at', { ascending: false }).limit(5),
        ])

        // Check for query errors
        const queryErrors = [
            totalRes.error ? `tickets count: ${totalRes.error.message}` : null,
            scannedRes.error ? `checkins scanned: ${scannedRes.error.message}` : null,
            manualRes.error ? `checkins manual: ${manualRes.error.message}` : null,
            recentRes.error ? `recent: ${recentRes.error.message}` : null,
        ].filter(Boolean)

        // Category counts: fetch tickets with type name, then ticket_types separately
        const { data: allTickets, error: ticketsErr } = await supabaseAdmin
            .from('tickets')
            .select('id, type, promo_pack_id')
            .eq('event_id', eid)

        const { data: ticketTypes, error: typesErr } = await supabaseAdmin
            .from('ticket_types')
            .select('name, category')
            .eq('event_id', eid)

        const { data: allCheckins, error: checkinsErr } = await supabaseAdmin
            .from('checkins')
            .select('ticket_id')
            .eq('event_id', eid)
            .eq('result', 'allowed')

        if (ticketsErr) queryErrors.push(`allTickets: ${ticketsErr.message}`)
        if (typesErr) queryErrors.push(`ticketTypes: ${typesErr.message}`)
        if (checkinsErr) queryErrors.push(`allCheckins: ${checkinsErr.message}`)

        const tickets = allTickets ?? []
        const types = ticketTypes ?? []
        const checkins = allCheckins ?? []

        // Build a map: type_name -> category
        const typeCategory: Record<string, string> = {}
        for (const tt of types) {
            if (tt.name) typeCategory[tt.name] = tt.category ?? ''
        }

        // Set of checked-in ticket IDs
        const checkedInIds = new Set(checkins.map((c: any) => c.ticket_id))

        // For promo packs: count distinct packs (by promo_pack_id), not individual tickets
        const countByCategory = (cat: string) => {
            const matching = tickets.filter((t: any) => typeCategory[t.type] === cat)
            if (cat === 'promo') {
                const packIds = new Set(matching.map((t: any) => t.promo_pack_id).filter(Boolean))
                // tickets without promo_pack_id count individually (shouldn't happen but safe)
                const withoutPack = matching.filter((t: any) => !t.promo_pack_id).length
                return packIds.size + withoutPack
            }
            return matching.length
        }
        const enteredByCategory = (cat: string) =>
            tickets.filter((t: any) => typeCategory[t.type] === cat && checkedInIds.has(t.id)).length

        const totalSold = totalRes.count ?? 0
        const scanned = scannedRes.count ?? 0
        const scannedManual = manualRes.count ?? 0
        const toEnter = Math.max(totalSold - scanned, 0)

        const metrics = {
            total_sold: totalSold,
            scanned: scanned,
            scanned_manual: scannedManual,
            valid: toEnter,
            standard_created: countByCategory('standard'),
            standard_entered: enteredByCategory('standard'),
            staff_created: countByCategory('staff'),
            staff_entered: enteredByCategory('staff'),
            guest_created: countByCategory('guest'),
            guest_entered: enteredByCategory('guest'),
            invitations_total: countByCategory('invitation'),
            invitations_scanned: enteredByCategory('invitation'),
            promo_created: countByCategory('promo'),
            promo_entered: enteredByCategory('promo'),
        }

        const recent = recentRes.data ?? []

        return new Response(
            JSON.stringify({ metrics, recent }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 },
        )
    }
})
