// Devuelve el enlace de pago de la organización del usuario autenticado.
//
// Crea el plan en dLocal la primera vez y lo reutiliza después: cada
// organización tiene el suyo porque dLocal Go no ofrece ningún campo de
// referencia libre, y el ÚNICO dato que identifica al pagador cuando llega el
// aviso es a qué plan se suscribió.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsFor } from '../_shared/cors.ts'
import { crearPlan, obtenerPlan } from '../_shared/dlocal.ts'
import { esAdmin } from '../_shared/roles.ts'

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
    // Era la única función que contemplaba al super-admin, con la condición
    // escrita a mano. Pasa por el predicado compartido igual que las otras
    // ocho: una sola definición de "quién administra".
    if (!esAdmin(perfil.role)) {
      return json({ ok: false, mensaje: 'Solo un administrador puede contratar' }, 403, req)
    }

    const { data: org } = await admin
      .from('organizations')
      .select('id, name, country, dlocal_plan_id, dlocal_plan_token, dlocal_plans')
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

    // Un plan guardado POR frecuencia.
    //
    // Antes se guardaba uno solo en `dlocal_plan_id`, y como hay dos planes
    // —mensual y anual— alternar entre ellos descartaba el guardado por no
    // coincidir la frecuencia y creaba otro. Cada clic en el otro plan era un
    // plan nuevo en dLocal: en la cuenta real quedaron siete "Imagine Access -
    // SONICO" alternando 25 y 250, que es la huella exacta del bug.
    //
    // Lo caro no era el desorden: el webhook consulta el plan guardado, así que
    // un enlace de pago viejo apuntaba a un plan que ya nadie miraba. Quien lo
    // completara pagaba sin que se le activara nada.
    const planes = (org.dlocal_plans ?? {}) as Record<string, { id?: number; token?: string }>
    const guardado = planes[plan]

    let planDLocal
    if (guardado?.id) {
      // Se confirma contra dLocal: si el plan se borró del panel, hay que crear
      // otro en vez de devolver un enlace muerto.
      planDLocal = await obtenerPlan(guardado.id).catch(() => null)

      // Y se vuelve a comprobar la frecuencia. Es defensa en profundidad: la
      // clave del jsonb ya dice cuál es, pero si alguna vez se guardara mal, el
      // síntoma sería cobrarle USD 25 al mes a quien eligió USD 250 al año.
      if (planDLocal && planDLocal.frequency_type !== precio.frecuencia) {
        planDLocal = null
      }

      // Un plan DESACTIVADO no sirve, aunque exista y sea de la frecuencia
      // correcta. Cancelar la suscripción desactiva los planes a propósito —para
      // que un enlace viejo no pueda volver a cobrar—, así que sin esta
      // comprobación quien se da de baja y después quiere volver recibe el
      // enlace de un plan muerto: el checkout abre y no deja pagar. Se crea uno
      // nuevo, que es lo correcto para una suscripción nueva.
      if (planDLocal && planDLocal.active === false) {
        planDLocal = null
      }
    } else if (org.dlocal_plan_id) {
      // Organizaciones anteriores a `dlocal_plans`: se intenta reutilizar el
      // plan viejo si resulta ser de esta frecuencia, y así no se crea uno más
      // al pie del cambio.
      planDLocal = await obtenerPlan(org.dlocal_plan_id).catch(() => null)
      if (planDLocal &&
          (planDLocal.frequency_type !== precio.frecuencia || planDLocal.active === false)) {
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

      // Se guarda BAJO SU FRECUENCIA, sin pisar el plan de la otra. Eso es lo
      // que impide que alternar de plan siga creando uno nuevo cada vez, y lo
      // que le permite al webhook encontrar la suscripción de un enlace viejo.
      //
      // `dlocal_plan_id` y `dlocal_plan_token` se siguen actualizando al último
      // usado porque el panel de super-admin los muestra.
      await admin.from('organizations').update({
        dlocal_plan_id: planDLocal.id,
        dlocal_plan_token: planDLocal.plan_token,
        dlocal_plans: {
          ...planes,
          [plan]: { id: planDLocal.id, token: planDLocal.plan_token },
        },
      }).eq('id', org.id)
    } else if (!guardado?.id) {
      // Se reutilizó el plan heredado de antes de `dlocal_plans`: se registra
      // bajo su frecuencia para que la próxima vez ya salga por el camino nuevo.
      await admin.from('organizations').update({
        dlocal_plans: {
          ...planes,
          [plan]: { id: planDLocal.id, token: planDLocal.plan_token },
        },
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
