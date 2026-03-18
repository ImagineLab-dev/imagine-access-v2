
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.0.0"
import { corsHeaders } from "../_shared/cors.ts"
import { getClientIp, isRateLimited, rateLimitResponse } from "../_shared/rate_limiter.ts"

serve(async (req: Request) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    const ip = getClientIp(req)
    if (isRateLimited(`void_ticket:${ip}`, 20, 60000)) {
        return rateLimitResponse(corsHeaders)
    }

    try {
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const { ticket_id } = await req.json()

        if (!ticket_id) {
            throw new Error("Missing ticket_id")
        }

        const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
        if (typeof ticket_id !== 'string' || !uuidRegex.test(ticket_id)) {
            throw new Error("Invalid ticket_id format")
        }

        // verify user role safely
        const authHeader = req.headers.get('Authorization');
        if (!authHeader) throw new Error("Missing authorization header");

        const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
        if (userError || !user) throw new Error("Unauthorized")

        // Get user profile to check role AND tenant
        const { data: profile } = await supabaseAdmin
            .from('users_profile')
            .select('role, organization_id')
            .eq('user_id', user.id)
            .single()

        if (!profile || (profile.role !== 'admin' && profile.role !== 'rrpp')) {
            throw new Error("Forbidden: Only Admin or RRPP can void tickets")
        }

        // Validate Cross-Tenant Boundary
        const { data: ticketData } = await supabaseAdmin.from('tickets').select('event_id').eq('id', ticket_id).single()
        if (!ticketData) throw new Error("Ticket not found")

        const { data: eventData } = await supabaseAdmin.from('events').select('organization_id').eq('id', ticketData.event_id).single()
        if (eventData?.organization_id !== profile.organization_id) throw new Error("Forbidden: Target ticket does not belong to your organization")

        // Perform Update
        const { error: updateError } = await supabaseAdmin
            .from('tickets')
            .update({
                status: 'void',
                void_reason: `Voided by ${profile.role} (user:${user.id})`
            })
            .eq('id', ticket_id)

        if (updateError) throw updateError

        return new Response(
            JSON.stringify({ message: "Ticket voided successfully" }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
        )

    } catch (error: any) {
        return new Response(
            JSON.stringify({ error: error.message }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
        )
    }
})
