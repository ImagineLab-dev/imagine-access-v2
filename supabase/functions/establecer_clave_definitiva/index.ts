import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { getClientIp, isRateLimited, rateLimitResponse } from "../_shared/rate_limiter.ts"

/**
 * Cierra el ciclo de la contraseña temporal.
 *
 * A un RRPP o door recién invitado se le crea la cuenta con una contraseña
 * temporal (`create_user`) y se le marca `app_metadata.must_change_password`.
 * El router no lo deja ir a ningún lado hasta que elija una propia; esta función
 * es lo que llama esa pantalla.
 *
 * Hace las dos cosas en UN solo llamado del admin —cambiar la clave y bajar la
 * bandera— porque el cliente no puede tocar `app_metadata` por su cuenta. Como
 * GoTrue FUSIONA `app_metadata`, `role` y `organization_id` quedan intactos.
 *
 * Solo actúa sobre el usuario del propio token: nadie puede cambiarle la clave a
 * otro. No pide la contraseña vieja a propósito —el usuario entró con la
 * temporal, ya está autenticado, y pedirle la que justamente está por descartar
 * no agrega seguridad—.
 */
serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders })
    }

    const ip = getClientIp(req)
    if (isRateLimited(`establecer_clave_definitiva:${ip}`, 10, 60000)) {
        return rateLimitResponse(corsHeaders)
    }

    try {
        const supabaseAdmin = createClient(
            Deno.env.get("SUPABASE_URL") ?? "",
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
        )

        const authHeader = req.headers.get("Authorization")
        if (!authHeader) throw new Error("No autorizado")
        const token = authHeader.replace("Bearer ", "").trim()

        const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
        if (authError || !user) {
            throw new Error("Sesión inválida. Cerrá sesión y volvé a entrar.")
        }

        const { password } = await req.json().catch(() => ({}))
        if (typeof password !== "string" || password.length < 8) {
            throw new Error("La contraseña debe tener al menos 8 caracteres.")
        }
        // bcrypt trunca a 72 bytes: una clave más larga guardaría algo distinto a
        // lo que la persona cree haber puesto. Se rechaza en vez de truncar.
        if (new TextEncoder().encode(password).length > 72) {
            throw new Error("La contraseña es demasiado larga.")
        }

        const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
            user.id,
            {
                password,
                app_metadata: { must_change_password: false },
            },
        )
        if (updateError) throw updateError

        return new Response(
            JSON.stringify({ ok: true }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
        )
    } catch (error) {
        const message = error instanceof Error ? error.message : "Error inesperado"
        return new Response(
            JSON.stringify({ ok: false, error: message }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 },
        )
    }
})
