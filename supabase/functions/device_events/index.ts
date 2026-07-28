import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { getClientIp, isRateLimited, rateLimitResponse } from "../_shared/rate_limiter.ts"

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    const ip = getClientIp(req)
    if (isRateLimited(`device_events:${ip}`, 60, 60000)) {
        return rateLimitResponse(corsHeaders)
    }

    try {
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const { device_id, organization_id, pin } = await req.json()

        // El PIN es OBLIGATORIO.
        //
        // Antes alcanzaba con device_id + organization_id, o sea que el id del
        // dispositivo funcionaba como credencial por sí solo: quien conociera
        // esos dos UUID podía listar todos los eventos con sus tipos y precios,
        // y el id de un equipo dado de baja seguía sirviendo aunque le
        // cambiaran el PIN. Es la misma verificación que ya hacía
        // device_dashboard; esta función nunca la adoptó.
        if (!device_id || !organization_id || !pin) {
            throw new Error("device_id, organization_id and pin are required")
        }

        // Validate: device exists, is enabled, and belongs to the given org
        const { data: device, error: devErr } = await supabaseAdmin
            .from('devices')
            .select('device_id, organization_id, enabled, pin_hash, pin_salt, pin')
            .eq('device_id', device_id)
            .single()

        if (devErr || !device) {
            throw new Error("Device not found")
        }

        if (!device.enabled) {
            throw new Error("Device is disabled")
        }

        if (device.organization_id !== organization_id) {
            throw new Error("Organization mismatch")
        }

        // Verify PIN — mismo esquema que device_dashboard: sha256("salt:pin"),
        // con respaldo al PIN plano de los dispositivos antiguos.
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
        if (!pinValid) {
            throw new Error("Invalid credentials")
        }

        // Fetch active events for this organization (with ticket_types)
        const { data: events, error: evErr } = await supabaseAdmin
            .from('events')
            .select('*, ticket_types(*)')
            .eq('organization_id', organization_id)
            .eq('is_archived', false)
            .order('date', { ascending: true })

        if (evErr) {
            throw new Error(`Failed to fetch events: ${evErr.message}`)
        }

        return new Response(
            JSON.stringify({ events: events ?? [] }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 },
        )
    }
})
