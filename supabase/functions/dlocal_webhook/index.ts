// Aviso de pago de dLocal Go.
//
// REGLA CENTRAL: este endpoint NO confía en el cuerpo que recibe.
//
// Cualquiera puede hacer un POST acá — la URL lleva la anon key, que es
// pública, y dLocal no firma sus avisos con un secreto compartido. Si
// acreditáramos el pago leyendo el JSON entrante, regalar suscripciones sería
// tan fácil como mandar un curl.
//
// Entonces el aviso se trata como lo que es: una señal de "andá a mirar". La
// confirmación sale de consultar la API de dLocal con nuestras credenciales, y
// solo si ahí figura una suscripción activa se extiende el vencimiento.
//
// Efecto secundario deseable: no hace falta conocer el formato exacto del
// cuerpo. No está documentado en la cuenta y no se puede probar sin un pago
// real, así que depender de su forma sería construir sobre una suposición.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { listarSuscripciones, planesDeLaOrganizacion } from '../_shared/dlocal.ts'
import { enviarEventoMeta } from '../_shared/meta_capi.ts'

const ESTADOS_VIGENTES = ['ACTIVE', 'ACTIVATED', 'PAID', 'SUCCESS', 'COMPLETED']

Deno.serve(async (req) => {
  // Sin CORS: quien llama es un servidor de dLocal, no un navegador.
  try {
    const url = new URL(req.url)
    const organizationId = url.searchParams.get('org')
    const plan = url.searchParams.get('plan') ?? 'monthly'

    if (!organizationId) {
      return json({ ok: false, mensaje: 'Falta el parámetro org' }, 400)
    }

    const cuerpo = await req.json().catch(() => ({}))
    console.log('dlocal_webhook recibido', { organizationId, plan, cuerpo })

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: org } = await admin
      .from('organizations')
      // contact_email se trae para Meta: el correo hasheado es lo que le
      // permite emparejar la compra con la persona que vio el anuncio. Sin
      // ningún identificador, la conversión llega pero atribuye mucho peor.
      .select('id, dlocal_plan_id, dlocal_plans, contact_email')
      .eq('id', organizationId)
      .maybeSingle()

    if (!org) {
      // Se responde 200: un 4xx haría que dLocal reintente para siempre un
      // aviso de una organización que no existe.
      console.warn('Aviso para una organización inexistente', organizationId)
      return json({ ok: true, mensaje: 'Organización inexistente, ignorado' }, 200)
    }

    // Qué planes hay que consultar.
    //
    // Antes se consultaba SOLO `org.dlocal_plan_id`, el último usado. Y como
    // alternar entre mensual y anual sobreescribía ese campo, un enlace de pago
    // apuntaba a un plan que ya nadie miraba: quien lo completara pagaba y el
    // aviso se registraba como `payment_rejected`. Cliente cobrado, suscripción
    // sin activar, y en el registro figuraba como rechazo.
    //
    // Ahora se consulta el plan de la frecuencia que avisa la propia
    // notificación (`?plan=`), y si no está, los demás guardados y el heredado.
    // Consultar de más no tiene costo: solo se acredita si dLocal confirma una
    // suscripción vigente, y `apply_subscription_payment` corta los duplicados.
    const planes = (org?.dlocal_plans ?? {}) as Record<string, { id?: number }>
    const candidatos = [
      planes[plan]?.id,
      ...Object.values(planes).map((p) => p?.id),
      org?.dlocal_plan_id,
    ].filter((id): id is number => typeof id === 'number')
    const aConsultar = [...new Set(candidatos)]

    if (aConsultar.length === 0) {
      // Se responde 200 igual: un 4xx haría que dLocal reintente para siempre
      // un aviso que nunca va a poder procesarse.
      console.warn('Aviso para una organización sin plan de dLocal', organizationId)
      return json({ ok: true, mensaje: 'Sin plan asociado, ignorado' }, 200)
    }

    // La verificación. Todo lo anterior es contexto; esto es la prueba.
    //
    // Las consultas van EN PARALELO. En serie tardaban entre 9 y 11 segundos
    // medidos contra la cuenta real, porque con los planes duplicados hay once
    // que revisar. Un webhook que tarda diez segundos es un webhook que la
    // pasarela corta por tiempo y reintenta, y cada reintento vuelve a tardar
    // diez: se realimenta. Son consultas independientes entre sí, así que no hay
    // ninguna razón para encadenarlas.
    async function buscarVigente(ids: number[]): Promise<[any, number | null]> {
      if (ids.length === 0) return [null, null]

      const resultados = await Promise.all(
        ids.map(async (planId) => {
          const suscripciones = await listarSuscripciones(planId).catch(() => null)
          const encontrada = (suscripciones?.data ?? []).find((s: any) => {
            const estado = String(s?.status ?? s?.state ?? '').toUpperCase()
            return ESTADOS_VIGENTES.includes(estado)
          })
          return encontrada ? ([encontrada, planId] as [any, number]) : null
        }),
      )

      // Se respeta el orden de `ids`: el primero es el plan de la frecuencia que
      // avisó la notificación, que es el candidato más probable.
      return resultados.find((r) => r !== null) ?? [null, null]
    }

    let [vigente, planUsado] = await buscarVigente(aConsultar)

    // Respaldo: si los planes guardados no dieron nada, se buscan en la cuenta
    // de dLocal TODOS los planes de esta organización y se revisan también.
    //
    // Es lo que rescata un pago hecho con un enlace viejo. El bug de duplicación
    // dejó varios planes vivos para la misma organización, y cualquiera de esos
    // enlaces sigue siendo cobrable: sin este barrido, quien completara uno
    // pagaría y el aviso quedaría anotado como rechazo.
    //
    // El emparejamiento es por el UUID de la organización, que `crearPlan`
    // escribe en la descripción. Por nombre habría sido un error: hay un plan
    // llamado "Imagine Access" en la cuenta que NO es de esta organización.
    if (!vigente) {
      const historicos = await planesDeLaOrganizacion(org.id).catch(() => [])
      const faltantes = historicos.filter((id) => !aConsultar.includes(id))

      if (faltantes.length > 0) {
        const [hallada, planHallado] = await buscarVigente(faltantes)
        if (hallada) {
          vigente = hallada
          planUsado = planHallado
          console.log('Suscripción hallada en un plan histórico', planHallado)
        }
        aConsultar.push(...faltantes)
      }
    }

    if (!vigente) {
      await admin.from('subscription_events').insert({
        organization_id: org!.id,
        event: 'payment_rejected',
        dlocal_plan_id: aConsultar[0],
        // Se deja constancia de DÓNDE se buscó. Sin esto, un rechazo no permite
        // distinguir "el pago no se completó" de "buscamos en el plan que no
        // era", que fue justamente el problema anterior.
        payload: { aviso: cuerpo, planes_consultados: aConsultar },
      })
      console.warn('Aviso sin suscripción vigente en dLocal', aConsultar)
      return json({ ok: true, mensaje: 'Sin suscripción vigente' }, 200)
    }

    // Se registra el plan DONDE SE ENCONTRÓ la suscripción, no el último que la
    // organización tenga guardado. Con varios planes vivos por el bug anterior,
    // anotar el equivocado dejaría un cobro imposible de rastrear en dLocal.
    const { data: hasta, error } = await admin.rpc('apply_subscription_payment', {
      p_organization_id: org!.id,
      p_plan: plan === 'annual' ? 'annual' : 'monthly',
      p_amount: vigente.amount ?? null,
      p_currency: vigente.currency ?? 'USD',
      p_dlocal_plan_id: planUsado,
      p_payload: cuerpo,
      // Identifica ESTE cobro. Mientras dLocal no emita uno nuevo, cualquier
      // reintento del aviso cae en el corte de idempotencia y no suma otro mes.
      p_reference: String(
        vigente.id ?? vigente.subscription_id ?? vigente.token ??
        `${planUsado}:${vigente.next_payment_date ?? vigente.created_at ?? ''}`,
      ),
    })

    if (error) throw error

    // Conversión a Meta.
    //
    // Va acá y no en el navegador porque el pago ocurre en el dominio de
    // dLocal: el pixel del sitio nunca ve esa pantalla. Este webhook es el
    // único punto del sistema que sabe con certeza que el cobro se acreditó.
    //
    // Se manda DESPUÉS de acreditar y sin await bloqueante sobre el resultado:
    // la suscripción del cliente no puede depender de que Meta conteste.
    //
    // El event_id combina organización y vencimiento, así que un reintento del
    // aviso que caiga en la idempotencia no genera una segunda conversión.
    // Purchase lleva el importe: es el evento por el que se optimizan las
    // campañas y el que alimenta el retorno que reporta Meta.
    await enviarEventoMeta({
      nombre: 'Purchase',
      eventId: `purchase-${org.id}-${hasta}`,
      email: org.contact_email,
      valor: vigente.amount ?? null,
      moneda: vigente.currency ?? 'USD',
      urlOrigen: 'https://imaginecloud.digital/#/subscription',
    })

    // Subscribe va SIN importe, a propósito.
    //
    // Es el evento semánticamente correcto para un negocio de suscripción y
    // sirve para construir públicos, pero si llevara valor sumaría los mismos
    // 25 dólares dos veces y el retorno que ves en el panel saldría al doble.
    // El dinero lo reporta Purchase; este es solo la señal.
    await enviarEventoMeta({
      nombre: 'Subscribe',
      eventId: `subscribe-${org.id}-${hasta}`,
      email: org.contact_email,
      urlOrigen: 'https://imaginecloud.digital/#/subscription',
    })

    console.log('Suscripción extendida', { organizationId: org.id, hasta })
    return json({ ok: true, expires_at: hasta }, 200)
  } catch (e) {
    console.error('dlocal_webhook falló:', e)
    // 500 para que dLocal reintente: si la caída fue nuestra, el reintento
    // acredita el pago solo. La idempotencia por `reference` en
    // `apply_subscription_payment` evita que un reintento sume otro mes.
    return json({ ok: false, error_detail: String(e) }, 500)
  }
})

function json(cuerpo: unknown, status: number): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
