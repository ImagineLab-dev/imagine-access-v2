// Baja de cuenta a pedido del titular.
//
// El orden de los tres pasos no es negociable:
//
//   1. CORTAR EL COBRO en dLocal, mientras la organización todavía existe y se
//      pueden leer sus planes. Al revés, la cuenta desaparece de nuestro lado y
//      dLocal sigue debitando una suscripción de la que ya no queda registro:
//      la persona ve el cargo, no tiene dónde reclamar dentro del producto, y
//      nosotros no tenemos con qué relacionarlo.
//
//   2. BORRAR LOS DATOS con `eliminar_mi_cuenta()`, que corre con el contexto de
//      quien llama y se encarga del orden interno —seis tablas bloquean el
//      borrado de una cuenta y cada una necesita un trato distinto—.
//
//   3. BORRAR LAS CUENTAS DE AUTENTICACIÓN con la API de administración. Esto va
//      último y por acá y no por SQL porque además revoca las sesiones abiertas:
//      borrar la fila de `auth.users` a mano dejaría tokens vivos hasta que
//      expiren.
//
// Si el paso 1 falla, NO se sigue. Es preferible una baja que no se completó y
// lo dice, a una cuenta borrada que sigue generando cargos.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { getClientIp, isRateLimited, rateLimitResponse } from '../_shared/rate_limiter.ts'
import { cortarCobro } from '../_shared/cortar_cobro.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const ip = getClientIp(req)
  // Más estricto que el resto: es una acción destructiva e irreversible, no hay
  // ningún motivo legítimo para pedirla muchas veces seguidas.
  if (isRateLimited(`eliminar_cuenta:${ip}`, 3, 60_000)) {
    return rateLimitResponse(corsHeaders)
  }

  try {
    const autorizacion = req.headers.get('Authorization')
    if (!autorizacion) {
      return json({ ok: false, mensaje: 'No autenticado' }, 401)
    }

    const { confirmacion, preview } = await req.json().catch(() => ({}))

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: { user }, error: errorUsuario } = await admin.auth.getUser(
      autorizacion.replace('Bearer ', '').trim(),
    )
    if (errorUsuario || !user) {
      return json({ ok: false, mensaje: 'No autenticado' }, 401)
    }

    // Contexto del usuario: la RPC decide con `auth.uid()`, así que tiene que
    // llamarse con SU token y no con el service role. Con el service role
    // `auth.uid()` es nulo y la función abortaría con NO_AUTENTICADO.
    const comoUsuario = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: autorizacion } } },
    )

    const { data: perfil } = await admin
      .from('users_profile')
      .select('organization_id, role')
      .eq('user_id', user.id)
      .maybeSingle()

    // ------------------------------------------------------------- Vista previa
    //
    // El diálogo de confirmación necesita saber DOS cosas que solo el servidor
    // sabe con certeza: si esta persona es dueña de la organización, y cuánto se
    // va a destruir. Calcularlo en el cliente obligaría a exponer esos datos y a
    // mantener la misma regla en dos lados; y un diálogo que dice "se borrarán
    // tus datos" sin números no le permite a nadie decidir de verdad.
    //
    // No borra nada. Es el mismo endpoint para que la respuesta venga de la
    // misma lógica que después ejecuta la baja.
    if (preview === true) {
      let esDueno = false
      let nombre: string | null = null
      let resumen: Record<string, unknown> | null = null

      if (perfil?.organization_id) {
        const { data: org } = await admin
          .from('organizations')
          .select('id, name, owner_id')
          .eq('id', perfil.organization_id)
          .maybeSingle()

        nombre = org?.name ?? null
        esDueno = org?.owner_id === user.id

        if (esDueno && org) {
          const [eventos, tickets, escaneos, miembros] = await Promise.all([
            admin.from('events').select('id', { count: 'exact', head: true })
              .eq('organization_id', org.id),
            admin.from('tickets').select('id, events!inner(organization_id)',
              { count: 'exact', head: true })
              .eq('events.organization_id', org.id),
            admin.from('checkins').select('id, events!inner(organization_id)',
              { count: 'exact', head: true })
              .eq('events.organization_id', org.id),
            admin.from('users_profile').select('user_id', { count: 'exact', head: true })
              .eq('organization_id', org.id),
          ])
          resumen = {
            eventos: eventos.count ?? 0,
            tickets: tickets.count ?? 0,
            escaneos: escaneos.count ?? 0,
            miembros: miembros.count ?? 0,
          }
        }
      }

      return json({
        ok: true,
        preview: true,
        es_dueno: esDueno,
        es_superadmin: perfil?.role === 'superadmin',
        organizacion: nombre,
        resumen,
      }, 200)
    }

    // ---------------------------------------------------------------- Paso 1

    let corte = null
    if (perfil?.organization_id) {
      const { data: org } = await admin
        .from('organizations')
        .select('id, owner_id, dlocal_plan_id, dlocal_plans')
        .eq('id', perfil.organization_id)
        .maybeSingle()

      // Solo si es el dueño: un miembro que se va no cancela la suscripción de
      // la organización, que sigue funcionando sin él.
      if (org && org.owner_id === user.id) {
        const guardados = [
          ...Object.values((org.dlocal_plans ?? {}) as Record<string, { id?: number }>)
            .map((p) => p?.id),
          org.dlocal_plan_id,
        ].filter((id): id is number => typeof id === 'number')

        corte = await cortarCobro([...new Set(guardados)], org.id)

        if (corte.fallidos.length > 0) {
          // Se aborta ANTES de borrar nada. La persona conserva su cuenta y su
          // acceso, y se le dice qué pasó: es reversible, mientras que borrar
          // con el cobro vivo no lo es.
          console.error('No se pudo cortar el cobro, se aborta la baja', corte.fallidos)
          return json({
            ok: false,
            mensaje: 'No se pudo cancelar la suscripción en la pasarela de pago. '
              + 'No se borró nada. Escribinos y lo resolvemos a mano.',
            detalle: corte.fallidos,
          }, 409)
        }
      }
    }

    // ---------------------------------------------------------------- Paso 2
    const { data: resultado, error: errorRpc } = await comoUsuario.rpc(
      'eliminar_mi_cuenta',
      { p_confirmacion: confirmacion ?? null },
    )

    if (errorRpc) {
      const codigo = String(errorRpc.message ?? '')
      const mensaje =
        codigo.includes('SUPERADMIN_NO_SE_PUEDE_BORRAR')
          ? 'Una cuenta de super-admin no puede darse de baja desde acá. Pasá el rol a otra cuenta primero.'
        : codigo.includes('CONFIRMACION_INVALIDA')
          ? 'Escribí el nombre exacto de tu organización para confirmar.'
        : 'No se pudo completar la baja.'
      return json({ ok: false, mensaje, detalle: codigo }, 400)
    }

    // ---------------------------------------------------------------- Paso 3
    const cuentas: string[] = resultado?.cuentas_a_eliminar ?? []
    const noBorradas: string[] = []

    for (const id of cuentas) {
      const { error } = await admin.auth.admin.deleteUser(id)
      if (error) {
        console.error('No se pudo borrar la cuenta de auth', id, error.message)
        noBorradas.push(id)
      }
    }

    return json({
      ok: true,
      era_dueno: resultado?.era_dueno ?? false,
      resumen: resultado?.resumen ?? null,
      cuentas_eliminadas: cuentas.length - noBorradas.length,
      // Si quedó alguna, los datos ya se fueron pero la credencial sigue viva.
      // Se informa en vez de callarlo: es lo que hay que revisar a mano.
      cuentas_pendientes: noBorradas,
      cobro: corte,
    }, 200)

  } catch (error) {
    console.error('eliminar_cuenta error', error)
    return json({ ok: false, mensaje: (error as Error).message }, 500)
  }
})

function json(cuerpo: unknown, status: number): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
