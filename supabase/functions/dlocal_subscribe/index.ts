// Devuelve el enlace de pago de la organización del usuario autenticado.
//
// Crea el plan en dLocal la primera vez y lo reutiliza después: cada
// organización tiene el suyo porque dLocal Go no ofrece ningún campo de
// referencia libre, y el ÚNICO dato que identifica al pagador cuando llega el
// aviso es a qué plan se suscribió.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsFor } from '../_shared/cors.ts'
import { crearPlan, obtenerPlan } from '../_shared/dlocal.ts'

const PRECIOS = {
  monthly: { monto: 25, frecuencia: 'MONTHLY' as const },
  annual: { monto: 250, frecuencia: 'YEARLY' as const },
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsFor(req) })
  }

  try {
    const autorizacion = req.headers.get('Authorization')
    if (!autorizacion) {
      return json({ ok: false, mensaje: 'No autenticado' }, 401, req)
    }

    const { plan = 'monthly' } = await req.json().catch(() => ({}))
    if (plan !== 'monthly' && plan !== 'annual') {
      return json({ ok: false, mensaje: `Plan inválido: ${plan}` }, 400, req)
    }

    // Con el token del usuario: así RLS decide qué organización es la suya, en
    // vez de confiar en un id que mande el cliente.
    const comoUsuario = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: autorizacion } } },
    )

    const { data: usuario } = await comoUsuario.auth.getUser()
    if (!usuario?.user) {
      return json({ ok: false, mensaje: 'Sesión inválida' }, 401, req)
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: perfil } = await admin
      .from('users_profile')
      .select('organization_id, role')
      .eq('user_id', usuario.user.id)
      .maybeSingle()

    if (!perfil?.organization_id) {
      return json({ ok: false, mensaje: 'El usuario no tiene organización' }, 400, req)
    }
    // Solo un admin contrata: un RRPP no debería poder generar cobros a nombre
    // de la organización.
    if (perfil.role !== 'admin' && perfil.role !== 'superadmin') {
      return json({ ok: false, mensaje: 'Solo un administrador puede contratar' }, 403, req)
    }

    const { data: org } = await admin
      .from('organizations')
      .select('id, name, country, dlocal_plan_id, dlocal_plan_token')
      .eq('id', perfil.organization_id)
      .single()

    if (!org) return json({ ok: false, mensaje: 'Organización inexistente' }, 404, req)

    // SUPABASE_PUBLIC_URL, no SUPABASE_URL: dentro del contenedor esta última
    // vale `http://kong:8000`, que dLocal no puede alcanzar desde afuera.
    const urlPublica = Deno.env.get('SUPABASE_PUBLIC_URL')
    if (!urlPublica) {
      throw new Error('Falta SUPABASE_PUBLIC_URL: sin ella el aviso de pago nunca llega')
    }

    // El aviso de pago vuelve con el id de la organización en la URL.
    //
    // SIN apikey. Llevarla hacía 291 caracteres y dLocal rechaza las
    // notification_url largas con un 500 opaco (code 7000), sin decir cuál es
    // el campo. Tampoco hace falta: las Edge Functions de esta instalación no
    // exigen JWT (FUNCTIONS_VERIFY_JWT=false), verificado con un POST sin
    // credencial que responde 200.
    //
    // Que el webhook quede accesible sin credencial es aceptable acá y no un
    // descuido: no acredita nada por lo que le manden. Lee el aviso como una
    // señal, consulta la API de dLocal con nuestras claves, y solo extiende el
    // vencimiento si allá figura una suscripción vigente.
    const notificationUrl =
      `${urlPublica}/functions/v1/dlocal_webhook?org=${org.id}&plan=${plan}`

    const precio = PRECIOS[plan as keyof typeof PRECIOS]

    let planDLocal
    if (org.dlocal_plan_id) {
      // Reutilizar. Si el plan se borró del panel, se crea otro en vez de
      // devolver un enlace muerto.
      planDLocal = await obtenerPlan(org.dlocal_plan_id).catch(() => null)

      // Y si el plan guardado no es del tipo que se está pidiendo, tampoco
      // sirve. Sin esta comprobación, alguien que primero mira el mensual y
      // después elige el anual recibía el enlace del MENSUAL: el checkout le
      // cobraba USD 25 al mes habiendo elegido USD 250 al año.
      if (planDLocal && planDLocal.frequency_type !== precio.frecuencia) {
        planDLocal = null
      }
    }

    if (!planDLocal) {
      planDLocal = await crearPlan({
        // Guion simple y no raya larga, por precaución: el nombre viaja a un
        // tercero y después vuelve en sus correos y su checkout. No está
        // probado que dLocal la rechace —el error de UTF-8 que vi al probarlo
        // lo generó la consola de Windows, no su API— pero no hay nada que
        // ganar mandando un carácter decorativo por ese camino.
        nombre: `Imagine Access - ${org.name}`,
        descripcion: `Suscripción de ${org.name} (${org.id})`,
        monto: precio.monto,
        moneda: 'USD',
        frecuencia: precio.frecuencia,
        pais: org.country,
        notificationUrl,
      })

      await admin.from('organizations').update({
        dlocal_plan_id: planDLocal.id,
        dlocal_plan_token: planDLocal.plan_token,
      }).eq('id', org.id)
    }

    await admin.from('subscription_events').insert({
      organization_id: org.id,
      event: 'checkout_created',
      dlocal_plan_id: planDLocal.id,
      amount: planDLocal.amount,
      currency: planDLocal.currency,
    })

    return json({ ok: true, url: planDLocal.subscribe_url }, 200, req)
  } catch (e) {
    console.error('dlocal_subscribe falló:', e)
    return json({ ok: false, mensaje: 'No se pudo generar el enlace de pago',
                  error_detail: String(e) }, 500, req)
  }
})

function json(cuerpo: unknown, status: number, req: Request): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...corsFor(req), 'Content-Type': 'application/json' },
  })
}
