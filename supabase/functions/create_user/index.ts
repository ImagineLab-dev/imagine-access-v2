import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { esAdmin } from "../_shared/roles.ts"
import { getClientIp, isRateLimited, rateLimitResponse } from "../_shared/rate_limiter.ts"
import { sendEmail } from "../_shared/email.ts"
import { asuntoInvitacion, cuerpoInvitacion, type Idioma } from "../_shared/invitation_email.ts"

function generateTempPassword(length = 12): string {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#'
    const bytes = new Uint8Array(length)
    crypto.getRandomValues(bytes)
    return Array.from(bytes, b => chars[b % chars.length]).join('')
}

serve(async (req: Request) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    const ip = getClientIp(req)
    if (isRateLimited(`create_user:${ip}`, 15, 60000)) {
        return rateLimitResponse(corsHeaders)
    }

    try {
        // 1. Initialize Supabase Admin Client
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // 2. Authenticate caller and get their organization
        const authHeader = req.headers.get('Authorization')
        if (!authHeader) throw new Error('No authorization header')

        const { data: { user: caller }, error: callerError } = await supabaseAdmin.auth.getUser(
            authHeader.replace('Bearer ', '')
        )
        if (callerError || !caller) throw new Error('Unauthorized')

        let callerRole = caller.app_metadata?.role
        if (!callerRole) {
            const { data: callerProfileRole } = await supabaseAdmin
                .from('users_profile')
                .select('role')
                .eq('user_id', caller.id)
                .single()
            callerRole = callerProfileRole?.role
        }
        if (!esAdmin(callerRole)) {
            throw new Error('Forbidden: Admin role required')
        }

        // Get caller's organization_id
        let callerOrgId = caller.app_metadata?.organization_id
        if (!callerOrgId) {
            const { data: callerProfile } = await supabaseAdmin
                .from('users_profile')
                .select('organization_id')
                .eq('user_id', caller.id)
                .single()
            callerOrgId = callerProfile?.organization_id
        }
        if (!callerOrgId) throw new Error('Caller has no organization assigned')

        // 3. Get Input
        const { email, display_name, role, language } = await req.json()

        if (!email) throw new Error("Email is required")

        // Validate role to prevent privilege escalation
        const allowedRoles = ['admin', 'rrpp', 'door'];
        if (role && !allowedRoles.includes(role)) {
            throw new Error(`Invalid role: ${role}. Allowed: ${allowedRoles.join(', ')}`);
        }

        // 4. Create Auth User (Admin API - with temporary password)
        let userId;
        let wasJustCreated = false;
        const tempPassword = generateTempPassword();

        console.log(`Creating user (redacted)`);
        const assignedRole = role || 'rrpp';
        const { data: userData, error: userError } = await supabaseAdmin.auth.admin.createUser({
            email,
            password: tempPassword,
            email_confirm: true,
            app_metadata: {
                role: assignedRole,
                organization_id: callerOrgId,
            },
            user_metadata: {
                display_name,
                organization_id: callerOrgId,
            },
        })

        if (userError) {
            if (userError.message.includes("already been registered")) {
                console.log("User exists, fetching ID to update profile...")

                // Use org-scoped RPC instead of listing ALL users (security fix)
                const { data: foundUserId, error: lookupError } = await supabaseAdmin.rpc(
                    'get_user_id_by_email',
                    { p_email: email }
                )

                if (lookupError || !foundUserId) {
                    throw new Error("User reported as registered but could not be resolved. Contact support.")
                }

                userId = foundUserId
            } else {
                throw userError
            }
        } else {
            userId = userData.user.id
            wasJustCreated = true
        }

        // 5. Check if user profile already exists with a different organization
        //    Skip this check if user was just created — the handle_new_user trigger
        //    auto-creates a profile+org, so we need to override it, not reject it.
        if (userId && !wasJustCreated) {
            const { data: existingProfile } = await supabaseAdmin
                .from('users_profile')
                .select('organization_id')
                .eq('user_id', userId)
                .maybeSingle()

            if (existingProfile && existingProfile.organization_id && existingProfile.organization_id !== callerOrgId) {
                throw new Error("El usuario ya se encuentra registrado y pertenece a otra organización.")
            }
        }

        // 5b. If user was just created, clean up the auto-created organization
        //     (handle_new_user trigger creates profile → auto_create_org trigger creates org)
        if (wasJustCreated) {
            const { data: autoProfile } = await supabaseAdmin
                .from('users_profile')
                .select('organization_id')
                .eq('user_id', userId)
                .maybeSingle()

            if (autoProfile?.organization_id && autoProfile.organization_id !== callerOrgId) {
                console.log("Cleaning up auto-created organization for invited user")
                await supabaseAdmin
                    .from('organizations')
                    .delete()
                    .eq('id', autoProfile.organization_id)
                    .eq('owner_id', userId)
            }
        }

        // 6. Create/Update Profile linked to caller's organization
        const { error: profileError } = await supabaseAdmin
            .from('users_profile')
            .upsert({
                user_id: userId,
                role: role || 'rrpp',
                display_name: display_name || email.split('@')[0],
                organization_id: callerOrgId,  // <-- ORG SCOPED
                created_by: caller.id,          // Track who invited this user
            }, { onConflict: 'user_id' })

        if (profileError) {
            console.error("Profile upsert failed", profileError)
            throw profileError
        }

        // 7. Invitacion por correo
        //
        // Solo para usuarios recien creados: a alguien que ya existia no se le
        // puede mandar una contrasena temporal que no es la suya.
        //
        // El envio NO bloquea la respuesta ni la revierte si falla. El usuario
        // ya quedo creado y funcional; si el correo no sale, el admin todavia
        // tiene la contrasena temporal en pantalla para pasarla a mano. Hacer
        // fallar todo el alta por un problema de SMTP seria peor.
        let invitationEmailSent = false
        if (wasJustCreated) {
            try {
                const appUrl = Deno.env.get('ALLOWED_ORIGIN') ?? 'https://imaginecloud.digital'
                const idioma = (['es', 'en', 'pt'].includes(language) ? language : 'es') as Idioma

                let orgName = 'Imagine Access'
                if (callerOrgId) {
                    const { data: org } = await supabaseAdmin
                        .from('organizations').select('name').eq('id', callerOrgId).single()
                    if (org?.name) orgName = org.name
                }

                const { data: perfilCaller } = await supabaseAdmin
                    .from('users_profile').select('display_name').eq('user_id', caller.id).maybeSingle()

                const datos = {
                    email,
                    tempPassword,
                    organizacion: orgName,
                    rol: role || 'rrpp',
                    invitadoPor: perfilCaller?.display_name ?? undefined,
                    appUrl,
                    idioma,
                }

                await sendEmail(email, asuntoInvitacion(datos), cuerpoInvitacion(datos))
                invitationEmailSent = true
            } catch (mailError) {
                console.error('Invitation email failed', mailError)
            }
        }

        return new Response(
            JSON.stringify({
                user_id: userId,
                organization_id: callerOrgId,
                status: 'success',
                invitation_email_sent: invitationEmailSent,
                ...(wasJustCreated ? { temp_password: tempPassword } : {}),
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )

    } catch (error) {
        console.error("Create User Error", error)
        return new Response(
            JSON.stringify({ error: (error as Error).message }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 },
        )
    }
})
