import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { esAdmin, esSuperAdmin } from "../_shared/roles.ts"
import { getClientIp, isRateLimited, rateLimitResponse } from "../_shared/rate_limiter.ts"

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    const ip = getClientIp(req)
    if (isRateLimited(`ensure_profile:${ip}`, 10, 60000)) {
        return rateLimitResponse(corsHeaders)
    }

    try {
        // 1. Initialize Supabase Client with SERVICE ROLE KEY (Bypasses RLS)
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const authHeader = req.headers.get('Authorization')
        if (!authHeader) throw new Error('No authorization header')

        const bearer = authHeader.replace('Bearer ', '').trim()
        const {
            data: { user: caller },
            error: callerError,
        } = await supabaseAdmin.auth.getUser(bearer)
        if (callerError || !caller) throw new Error('Unauthorized')

        // 2. Get Data Body
        const { user_id, display_name, email, organization_name, country } = await req.json()

        if (typeof display_name === 'string' && display_name.length > 200) throw new Error('display_name max 200 characters')
        if (typeof organization_name === 'string' && organization_name.length > 200) throw new Error('organization_name max 200 characters')

        // País de facturación. Se valida contra la lista de plazas de dLocal
        // acá y no solo con el CHECK de la base: un país inválido tiene que
        // fallar con un mensaje claro, no con un error de constraint que el
        // cliente no sabe interpretar. Un valor desconocido se descarta en vez
        // de abortar el alta — quedarse sin cuenta por un país mal mandado es
        // peor que quedarse sin país, que el admin puede corregir después.
        const PAISES_DLOCAL = ['PY','AR','UY','BR','CL','BO','CO','PE','EC','PA','DO','CR','GT','MX',
            'US','ES','NG','KE','IN','ID','MY','PH','VN']
        const paisFacturacion = (typeof country === 'string' && PAISES_DLOCAL.includes(country))
            ? country
            : null

        const requestedUserId = typeof user_id === 'string' && user_id.trim().length > 0
            ? user_id.trim()
            : caller.id

        // Actuar sobre el perfil de OTRO usuario.
        //
        // Antes esto solo preguntaba "¿el que llama es admin?". Nunca preguntaba
        // si el usuario objetivo era de su organización, y esta función corre con
        // el service role, que no pasa por RLS. Resultado: cualquier admin —o
        // sea, cualquiera que se registre— pasando el `user_id` del dueño de
        // otra organización obtenía la fila COMPLETA de `organizations`, que
        // incluye `tax_id`, `legal_name`, `contact_email`, `contact_phone`,
        // `address`, `plan`, `subscription_expires_at` y `dlocal_plan_token`. Y
        // si esa organización conservaba el nombre por defecto, podía
        // renombrarla y cambiarle el slug (ver más abajo).
        //
        // Explotarlo requería conocer un UUID ajeno, lo que lo hacía improbable
        // pero no imposible. La defensa correcta es comparar organizaciones: así
        // conocer el UUID deja de servir para nada.
        //
        // Hoy NADIE usa este camino: el cliente manda siempre su propio id
        // (auth_controller.dart, tres llamadas) y ninguna Edge Function invoca
        // esta función. Es superficie de ataque sin uso. Se conserva la
        // capacidad, pero acotada a la misma organización.
        if (requestedUserId !== caller.id) {
            // El rol y la organización se leen de la TABLA, no del claim del
            // JWT. Para una operación privilegiada sobre otra persona no
            // conviene fiarse de un claim que puede estar viejo: el claim se
            // sella al emitir el token y sobrevive a una degradación de rol
            // hasta que expira.
            const { data: perfilLlamador } = await supabaseAdmin
                .from('users_profile')
                .select('role, organization_id')
                .eq('user_id', caller.id)
                .single()

            if (!esAdmin(perfilLlamador?.role)) {
                throw new Error('Forbidden: cannot manage profile for another user')
            }

            const { data: perfilObjetivo } = await supabaseAdmin
                .from('users_profile')
                .select('organization_id')
                .eq('user_id', requestedUserId)
                .maybeSingle()

            // El super-admin de la plataforma sí cruza organizaciones: para eso
            // existe. Un admin común, no.
            if (!esSuperAdmin(perfilLlamador?.role)) {
                if (!perfilObjetivo?.organization_id ||
                    !perfilLlamador?.organization_id ||
                    perfilObjetivo.organization_id !== perfilLlamador.organization_id) {
                    throw new Error('Forbidden: user is not from your organization')
                }
            }
        }

        const effectiveEmail = (typeof email === 'string' && email.trim().length > 0)
            ? email.trim()
            : (caller.email ?? '')

        if (!requestedUserId) throw new Error("Missing user_id")

        // 3. Check if user already has a profile with organization
        const { data: existingProfile } = await supabaseAdmin
            .from('users_profile')
            .select('user_id, organization_id, role')
            .eq('user_id', requestedUserId)
            .single()

        if (existingProfile?.organization_id) {
            // User already has organization, fetch it
            const { data: existingOrg } = await supabaseAdmin
                .from('organizations')
                .select('*')
                .eq('id', existingProfile.organization_id)
                .single()

            // El dueño de una organización tiene que poder administrarla. Si su
            // perfil quedó con un rol MENOR que admin, se repara.
            //
            // La condición original era `profileRole !== 'admin'`, y eso incluía
            // a `superadmin`, que está POR ENCIMA de admin. Efecto real: el
            // dueño de la plataforma, que además es dueño de su organización,
            // se degradaba a `admin` en cada login. La tabla sobrevivía porque
            // `guard_profile_self_update` revierte el cambio en silencio —el
            // service role no pasa `is_admin()`— pero el claim del token se
            // escribía igual más abajo, así que el panel de super-admin
            // desaparecía del menú después de cada ingreso.
            const ROLES_MENORES_QUE_ADMIN = new Set(['rrpp', 'door'])
            const rolInvalidoParaUnDueno = existingProfile.role == null ||
                existingProfile.role === '' ||
                ROLES_MENORES_QUE_ADMIN.has(existingProfile.role)

            let profileRole = existingProfile.role
            if (existingOrg?.owner_id === requestedUserId && rolInvalidoParaUnDueno) {
                await supabaseAdmin
                    .from('users_profile')
                    .update({ role: 'admin' })
                    .eq('user_id', requestedUserId)

                // Se vuelve a LEER en vez de asumir que el UPDATE quedó.
                //
                // `guard_profile_self_update` puede revertirlo sin devolver
                // error, y en ese caso dar por hecho que quedó en 'admin'
                // escribía en el token un rol distinto al de la tabla. Esa
                // discrepancia es justamente lo que rompe la app: el cliente
                // lee el rol del token y la base lo lee de la tabla. El claim
                // se deriva de lo que REALMENTE está guardado.
                const { data: reLeido } = await supabaseAdmin
                    .from('users_profile')
                    .select('role')
                    .eq('user_id', requestedUserId)
                    .single()
                profileRole = reLeido?.role ?? existingProfile.role
            }

            // FIX: If caller is the org owner and sent a real organization_name,
            // update the org name (the DB trigger creates a generic "{name} Organization")
            let finalOrg = existingOrg
            if (
                organization_name &&
                existingOrg?.owner_id === requestedUserId &&
                existingOrg?.name !== organization_name &&
                existingOrg?.name?.endsWith(' Organization')
            ) {
                const newSlug = organization_name
                    .toLowerCase()
                    .replace(/[^a-z0-9]+/g, '-')
                    .replace(/^-|-$/g, '')
                    + '-' + (existingOrg.slug?.split('-').pop() || Math.random().toString(36).substring(2, 8))

                const { data: updatedOrg, error: updateOrgError } = await supabaseAdmin
                    .from('organizations')
                    .update({ name: organization_name, slug: newSlug })
                    .eq('id', existingProfile.organization_id)
                    .select()
                    .single()

                if (updateOrgError && updateOrgError.code === '23505') {
                    // Slug collision — retry with a fresh random suffix
                    const retrySlug = newSlug.replace(/-[^-]+$/, '-' + Math.random().toString(36).substring(2, 8))
                    const { data: retryOrg } = await supabaseAdmin
                        .from('organizations')
                        .update({ name: organization_name, slug: retrySlug })
                        .eq('id', existingProfile.organization_id)
                        .select()
                        .single()
                    if (retryOrg) finalOrg = retryOrg
                } else if (updatedOrg) {
                    finalOrg = updatedOrg
                }
            }

            // Always sync role to auth.users metadata (ensures JWT has correct role)
            await supabaseAdmin.auth.admin.updateUserById(requestedUserId, {
                app_metadata: {
                    role: profileRole,
                    organization_id: existingProfile.organization_id,
                    organization_name: finalOrg?.name ?? '',
                    organization_slug: finalOrg?.slug ?? ''
                }
            })

            return new Response(
                JSON.stringify({
                    profile: { ...existingProfile, role: profileRole },
                    organization: finalOrg,
                    organization_id: existingProfile.organization_id,
                    is_new: false
                }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
            )
        }

        // 4. Generate unique organization slug
        const baseSlug = (display_name || effectiveEmail.split('@')[0] || 'org')
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-|-$/g, '')
        const uniqueSlug = `${baseSlug}-${Math.random().toString(36).substring(2, 8)}`

        const orgName = organization_name || `${display_name || effectiveEmail.split('@')[0] || 'My'} Organization`

        // 5. Create Organization first
        const { data: org, error: orgError } = await supabaseAdmin
            .from('organizations')
            .insert({
                name: orgName,
                slug: uniqueSlug,
                owner_id: requestedUserId,
                country: paisFacturacion,
                // subscription_expires_at lo pone la base: 14 días de prueba.
            })
            .select()
            .single()

        if (orgError) {
            console.error("Error creating organization:", orgError)
            throw orgError
        }

        // 6. Create/Update Profile with organization and admin role
        const { data: profile, error: profileError } = await supabaseAdmin
            .from('users_profile')
            .upsert({
                user_id: requestedUserId,
                display_name: display_name || effectiveEmail.split('@')[0] || 'User',
                role: 'admin', // Organization creator gets 'admin' role
                organization_id: org.id,
                created_at: new Date().toISOString()
            }, { onConflict: 'user_id' })
            .select()
            .single()

        if (profileError) {
            console.error("Error creating profile:", profileError)
            throw profileError
        }

        // 7. Update auth.users metadata with organization info
        const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
            requestedUserId,
            {
                app_metadata: {
                    role: 'admin',
                    organization_id: org.id,
                    organization_name: org.name,
                    organization_slug: org.slug
                }
            }
        )

        if (updateError) {
            console.error("Error updating user metadata:", updateError)
            // Don't throw - profile is created, metadata is bonus
        }

        return new Response(
            JSON.stringify({
                profile: profile,
                organization: org,
                organization_id: org.id,
                is_new: true
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )

    } catch (error) {
        console.error("ensure_profile error:", error)
        return new Response(
            JSON.stringify({ error: error.message }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 },
        )
    }
})
