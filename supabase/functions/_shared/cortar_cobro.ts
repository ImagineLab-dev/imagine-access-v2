/**
 * Corta el cobro recurrente de una organización en dLocal.
 *
 * Vive acá y no dentro de una función porque lo necesitan DOS caminos distintos
 * y tienen que comportarse igual:
 *
 *   - cancelar_suscripcion  -> el cliente sigue existiendo, deja de pagar
 *   - eliminar_cuenta       -> el cliente se va; si no se corta el cobro acá,
 *                              dLocal le sigue debitando una cuenta que ya no
 *                              existe, y nadie del lado nuestro se entera
 *
 * Duplicar esta lógica era garantizar que una de las dos se olvidara de un paso.
 */

import { cancelarSuscripcion, desactivarPlan, listarSuscripciones, planesDeLaOrganizacion } from './dlocal.ts'

/** Estados que dLocal considera vigentes. Mismo criterio que el webhook. */
const ESTADOS_VIGENTES = ['ACTIVE', 'ACTIVATED', 'PAID', 'SUCCESS', 'COMPLETED']

export type ResultadoCorte = {
  /** Suscripciones que estaban vigentes y quedaron canceladas. */
  suscripcionesCanceladas: number[]
  /** Planes que quedaron desactivados, para que no se pueda suscribir nadie más. */
  planesDesactivados: number[]
  /** Lo que se intentó y NO se pudo confirmar. Si trae algo, hay que revisar a mano. */
  fallidos: string[]
}

/**
 * @param planesGuardados Los ids que la organización tiene registrados.
 * @param organizationId  Para rescatar además los planes históricos, que existen
 *                        por el bug de duplicación y siguen siendo cobrables.
 */
export async function cortarCobro(
  planesGuardados: number[],
  organizationId: string,
): Promise<ResultadoCorte> {
  const resultado: ResultadoCorte = {
    suscripcionesCanceladas: [],
    planesDesactivados: [],
    fallidos: [],
  }

  // Todos los planes de la organización: los guardados más los que quedaron
  // sueltos. Un plan viejo con un enlace de checkout vivo sigue pudiendo cobrar,
  // así que dejarlo afuera sería dejar el cobro a medio cortar.
  const historicos = await planesDeLaOrganizacion(organizationId).catch(() => [])
  const todos = [...new Set([...planesGuardados, ...historicos])]

  // En paralelo: son independientes y en serie esto se iría a decenas de
  // segundos con varios planes.
  await Promise.all(todos.map(async (planId) => {
    try {
      const suscripciones = await listarSuscripciones(planId).catch(() => null)
      const vigentes = (suscripciones?.data ?? []).filter((s: any) => {
        const estado = String(s?.status ?? s?.state ?? '').toUpperCase()
        return ESTADOS_VIGENTES.includes(estado)
      })

      for (const s of vigentes) {
        const subId = Number(s?.id ?? s?.subscription_id)
        if (!Number.isFinite(subId)) {
          resultado.fallidos.push(`plan ${planId}: suscripción sin id numérico`)
          continue
        }
        // `cancelarSuscripcion` devuelve si quedó en active:false, no si la
        // llamada respondió 200. dLocal responde 200 a cosas que no aplica.
        const ok = await cancelarSuscripcion(planId, subId).catch(() => false)
        if (ok) resultado.suscripcionesCanceladas.push(subId)
        else resultado.fallidos.push(`suscripción ${subId} del plan ${planId} no se pudo cancelar`)
      }

      const okPlan = await desactivarPlan(planId).catch(() => false)
      if (okPlan) resultado.planesDesactivados.push(planId)
      else resultado.fallidos.push(`plan ${planId} no se pudo desactivar`)
    } catch (e) {
      resultado.fallidos.push(`plan ${planId}: ${(e as Error).message}`)
    }
  }))

  return resultado
}
