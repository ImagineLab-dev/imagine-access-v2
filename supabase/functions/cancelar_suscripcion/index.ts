// Baja del cobro recurrente, a pedido de quien administra la organización.
//
// El orden importa y es el inverso al que uno escribiría por comodidad:
//
//   1. Cortar el cobro EN dLOCAL.
//   2. Recién entonces marcarlo en nuestra base.
//
// Al revés, si el corte falla, la pantalla diría "suscripción cancelada"
// mientras el débito sigue corriendo todos los meses. Esa es la peor
// combinación posible: el cliente cree que se dio de baja, deja de mirar, y se
// entera por el resumen de la tarjeta.
//
// Cancelar detiene la RENOVACIÓN, no el servicio: el acceso sigue hasta
// `subscription_expires_at`, que es hasta donde está pagado.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsFor } from '../_shared/cors.ts'
import { getClientIp, isRateLimited, rateLimitResponse } from '../_shared/rate_limiter.ts'
import { cortarCobro } from '../_shared/cortar_cobro.ts'
import { esAdmin } from '../_shared/roles.ts'

Deno.serve(async (req) => {
  const cors = corsFor(req)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors })
  }

  const ip = getClientIp(req)
  if (isRateLimited(`cancelar_suscripcion:${ip}`, 5, 60_000)) {
    return rateLimitResponse(cors)
  }

  try {
    const autorizacion = req.headers.get('Authorization')
    if (!autorizacion) return json({ ok: false, mensaje: 'No autenticado' }, 401, cors)

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: { user }, error: errorUsuario } = await admin.auth.getUser(
      autorizacion.replace('Bearer ', '').trim(),
    )
    if (errorUsuario || !user) return json({ ok: false, mensaje: 'No autenticado' }, 401, cors)

    // El rol se lee de la TABLA, no del claim: el claim sobrevive a una
    // degradación hasta que expira el token, y esto toca dinero.
    const { data: perfil } = await admin
      .from('users_profile')
      .select('role, organization_id')
      .eq('user_id', user.id)
      .maybeSingle()

    if (!perfil?.organization_id) {
      return json({ ok: false, mensaje: 'Sin organización' }, 400, cors)
    }
    if (!esAdmin(perfil.role)) {
      return json({ ok: false, mensaje: 'Solo quien administra puede dar de baja el cobro' }, 403, cors)
    }

    const { data: org } = await admin
      .from('organizations')
      .select('id, plan, subscription_expires_at, subscription_cancelled_at, dlocal_plan_id, dlocal_plans')
      .eq('id', perfil.organization_id)
      .maybeSingle()

    if (!org) return json({ ok: false, mensaje: 'Organización inexistente' }, 404, cors)

    if (!org.plan || org.plan === 'trial') {
      return json({ ok: false, mensaje: 'No hay una suscripción paga que dar de baja' }, 400, cors)
    }

    if (org.subscription_cancelled_at) {
      return json({
        ok: true,
        ya_estaba: true,
        acceso_hasta: org.subscription_expires_at,
      }, 200, cors)
    }

    // ---------------------------------------------------------------- Paso 1
    const guardados = [
      ...Object.values((org.dlocal_plans ?? {}) as Record<string, { id?: number }>)
        .map((p) => p?.id),
      org.dlocal_plan_id,
    ].filter((id): id is number => typeof id === 'number')

    const corte = await cortarCobro([...new Set(guardados)], org.id)

    if (corte.fallidos.length > 0) {
      // NO se marca. El cliente sigue viendo su suscripción activa —que es la
      // verdad— y se le dice que hubo un problema, en vez de darle por buena una
      // baja que no ocurrió.
      console.error('No se pudo cortar el cobro', corte.fallidos)
      return json({
        ok: false,
        mensaje: 'No pudimos dar de baja el cobro en la pasarela. Tu suscripción sigue activa. '
          + 'Escribinos y lo resolvemos.',
        detalle: corte.fallidos,
      }, 409, cors)
    }

    // ---------------------------------------------------------------- Paso 2
    const comoUsuario = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: autorizacion } } },
    )

    const { data: resultado, error } = await comoUsuario.rpc('marcar_suscripcion_cancelada')
    if (error) {
      // El cobro YA se cortó. Que la marca falle es molesto pero no le cuesta
      // plata a nadie, así que se informa el estado real en vez de fingir un
      // error total.
      console.error('Cobro cortado pero no se pudo marcar', error.message)
      return json({
        ok: true,
        marca_pendiente: true,
        mensaje: 'El cobro quedó dado de baja. La pantalla puede tardar en reflejarlo.',
        cobro: corte,
      }, 200, cors)
    }

    return json({
      ok: true,
      ya_estaba: resultado?.ya_estaba ?? false,
      plan: resultado?.plan,
      acceso_hasta: resultado?.acceso_hasta,
      cobro: corte,
    }, 200, cors)

  } catch (error) {
    console.error('cancelar_suscripcion error', error)
    return json({ ok: false, mensaje: (error as Error).message }, 500, cors)
  }
})

function json(cuerpo: unknown, status: number, cors: HeadersInit): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}
