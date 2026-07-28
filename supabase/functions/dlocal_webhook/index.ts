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
import { listarSuscripciones } from '../_shared/dlocal.ts'

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
      .select('id, dlocal_plan_id')
      .eq('id', organizationId)
      .maybeSingle()

    if (!org?.dlocal_plan_id) {
      // Se responde 200 igual: un 4xx haría que dLocal reintente para siempre
      // un aviso que nunca va a poder procesarse.
      console.warn('Aviso para una organización sin plan de dLocal', organizationId)
      return json({ ok: true, mensaje: 'Sin plan asociado, ignorado' }, 200)
    }

    // La verificación. Todo lo anterior es contexto; esto es la prueba.
    const suscripciones = await listarSuscripciones(org.dlocal_plan_id)
    const vigente = (suscripciones?.data ?? []).find((s: any) => {
      const estado = String(s?.status ?? s?.state ?? '').toUpperCase()
      return ESTADOS_VIGENTES.includes(estado)
    })

    if (!vigente) {
      await admin.from('subscription_events').insert({
        organization_id: org.id,
        event: 'payment_rejected',
        dlocal_plan_id: org.dlocal_plan_id,
        payload: cuerpo,
      })
      console.warn('Aviso sin suscripción vigente en dLocal', org.dlocal_plan_id)
      return json({ ok: true, mensaje: 'Sin suscripción vigente' }, 200)
    }

    const { data: hasta, error } = await admin.rpc('apply_subscription_payment', {
      p_organization_id: org.id,
      p_plan: plan === 'annual' ? 'annual' : 'monthly',
      p_amount: vigente.amount ?? null,
      p_currency: vigente.currency ?? 'USD',
      p_dlocal_plan_id: org.dlocal_plan_id,
      p_payload: cuerpo,
      // Identifica ESTE cobro. Mientras dLocal no emita uno nuevo, cualquier
      // reintento del aviso cae en el corte de idempotencia y no suma otro mes.
      p_reference: String(
        vigente.id ?? vigente.subscription_id ?? vigente.token ??
        `${org.dlocal_plan_id}:${vigente.next_payment_date ?? vigente.created_at ?? ''}`,
      ),
    })

    if (error) throw error

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
