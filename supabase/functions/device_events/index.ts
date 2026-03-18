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

        const { device_id, organization_id } = await req.json()

        if (!device_id || !organization_id) {
            throw new Error("device_id and organization_id are required")
        }

        // Validate: device exists, is enabled, and belongs to the given org
        const { data: device, error: devErr } = await supabaseAdmin
            .from('devices')
            .select('device_id, organization_id, enabled')
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
