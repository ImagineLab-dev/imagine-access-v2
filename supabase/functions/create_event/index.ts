
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { corsHeaders } from "../_shared/cors.ts"
import { esAdmin } from "../_shared/roles.ts"
import { getSupabaseClient } from "../_shared/supabaseClient.ts"
import { getClientIp, isRateLimited, rateLimitResponse } from "../_shared/rate_limiter.ts"

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    const ip = getClientIp(req)
    if (isRateLimited(`create_event:${ip}`, 20, 60000)) {
        return rateLimitResponse(corsHeaders)
    }

    try {
        const supabase = getSupabaseClient(req)
        // Check if user is authenticated
        const {
            data: { user },
        } = await supabase.auth.getUser()

        if (!user) {
            return new Response(JSON.stringify({ error: 'Unauthorized' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 401,
            })
        }

        const { data: profile, error: profileError } = await supabase
            .from('users_profile')
            .select('organization_id, role')
            .eq('user_id', user.id)
            .single()

        if (profileError || !profile?.organization_id) {
            return new Response(JSON.stringify({ error: 'User organization not found' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        const userRole = profile.role ?? user.app_metadata?.role ?? 'rrpp'
        if (!esAdmin(userRole)) {
            return new Response(JSON.stringify({ error: 'Forbidden: admin only' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 403,
            })
        }

        const { name, date, venue, address, city, currency } = await req.json()

        if (!name || !date || !venue) {
            return new Response(JSON.stringify({ error: 'Missing required fields' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        if (typeof name !== 'string' || name.length > 200 || typeof venue !== 'string' || venue.length > 200) {
            return new Response(JSON.stringify({ error: 'name and venue must be strings of max 200 characters' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        // Simple slugify
        const slug = name
            .toString()
            .toLowerCase()
            .trim()
            .replace(/\s+/g, '-')     // Replace spaces with -
            .replace(/[^\w\-]+/g, '') // Remove all non-word chars
            .replace(/\-\-+/g, '-')   // Replace multiple - with single -

        // Check uniqueness (optimistic)
        const { data: existing } = await supabase
            .from('events')
            .select('slug')
            .eq('slug', slug)
            .maybeSingle()

        let finalSlug = slug;
        if (existing) {
            finalSlug = `${slug}-${Math.floor(Math.random() * 1000)}`
        }

        const { data, error } = await supabase
            .from('events')
            .insert([
                {
                    name,
                    slug: finalSlug,
                    date,
                    venue,
                    organization_id: profile.organization_id,
                    created_by: user.id,
                    ...(address && { address }),
                    ...(city && { city }),
                    ...(currency && { currency }),
                },
            ])
            .select()
            .single()

        if (error) throw error

        return new Response(JSON.stringify(data), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })

    } catch (error) {
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 400,
        })
    }
})
