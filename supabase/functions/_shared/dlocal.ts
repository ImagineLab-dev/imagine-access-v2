// Cliente de la API de dLocal Go.
//
// Autenticación: `Bearer <API_KEY>:<SECRET_KEY>`. Verificado el 28/07/2026
// contra la cuenta de producción (merchant 34108).
//
// La SECRET_KEY nunca sale del servidor. Si aparece en el bundle del cliente,
// cualquiera puede crear planes y consultar los cobros de todos los tenants.

const BASE = 'https://api.dlocalgo.com/v1'

function credenciales(): string {
  const key = Deno.env.get('DLOCAL_API_KEY')
  const secret = Deno.env.get('DLOCAL_SECRET_KEY')
  if (!key || !secret) {
    throw new Error('Faltan DLOCAL_API_KEY / DLOCAL_SECRET_KEY en el entorno')
  }
  return `${key}:${secret}`
}

async function llamar(ruta: string, init: RequestInit = {}): Promise<any> {
  const res = await fetch(`${BASE}${ruta}`, {
    ...init,
    headers: {
      'Authorization': `Bearer ${credenciales()}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  })

  const texto = await res.text()
  if (!res.ok) {
    // El cuerpo entra en el mensaje a propósito: dLocal devuelve el motivo real
    // ahí, y sin él un 500 no dice absolutamente nada.
    throw new Error(`dLocal ${ruta} respondió ${res.status}: ${texto.slice(0, 400)}`)
  }
  return texto ? JSON.parse(texto) : null
}

export interface PlanDLocal {
  id: number
  plan_token: string
  subscribe_url: string
  amount: number
  currency: string
  frequency_type: string
  active: boolean
}

/** Crea el plan de suscripción de una organización. */
export function crearPlan(params: {
  nombre: string
  descripcion: string
  monto: number
  moneda: string
  frecuencia: 'MONTHLY' | 'YEARLY'
  pais?: string | null
  notificationUrl: string
}): Promise<PlanDLocal> {
  return llamar('/subscription/plan', {
    method: 'POST',
    body: JSON.stringify({
      name: params.nombre,
      description: params.descripcion,
      amount: params.monto,
      currency: params.moneda,
      frequency_type: params.frecuencia,
      frequency_value: 1,
      // El país restringe los medios de pago que ofrece el checkout. Si no se
      // conoce, se omite y dLocal los muestra todos.
      ...(params.pais ? { country: params.pais } : {}),
      notification_url: params.notificationUrl,
    }),
  })
}

export function obtenerPlan(planId: number): Promise<PlanDLocal> {
  return llamar(`/subscription/plan/${planId}`)
}

/** Suscripciones de un plan. Es la fuente de verdad, no el aviso del webhook. */
export function listarSuscripciones(planId: number): Promise<{ data: any[] }> {
  return llamar(`/subscription/plan/${planId}/subscription/all`)
}

/**
 * Da de baja la suscripción de un cliente: deja de cobrarle.
 *
 * `PATCH /v1/subscription/plan/{planId}/subscription/{subId}/deactivate`,
 * tomado de la documentación de dLocal Go. El verbo importa: `POST` a esa misma
 * ruta devuelve un 500 opaco.
 *
 * DEVUELVE SI QUEDÓ DESACTIVADA, no si la llamada respondió bien. La distinción
 * no es teórica: `PATCH /subscription/plan/{id}` con `{"active":false}` responde
 * **200 con el objeto del plan y no cambia nada**. Confiar en el código HTTP
 * daría un botón de "cancelar suscripción" que dice "listo" mientras el cobro
 * sigue corriendo. Se comprueba el efecto.
 */
export async function cancelarSuscripcion(
  planId: number,
  subscriptionId: number,
): Promise<boolean> {
  const r = await llamar(
    `/subscription/plan/${planId}/subscription/${subscriptionId}/deactivate`,
    { method: 'PATCH' },
  )
  return r?.active === false
}

/**
 * Da de baja el PLAN: nadie puede suscribirse más con ese enlace.
 *
 * `PATCH /v1/subscription/plan/{planId}/deactivate`. Verificado contra la cuenta
 * real el 30/07/2026: `active` pasó de `true` a `false`.
 *
 * Es el complemento de `cancelarSuscripcion`: cancelar la suscripción corta el
 * cobro de quien ya estaba, y desactivar el plan impide que un enlace de
 * checkout viejo cree una suscripción nueva. Con los planes duplicados que dejó
 * el bug anterior, esos enlaces viejos existen.
 *
 * Devuelve si quedó desactivado, por la misma razón que arriba.
 */
export async function desactivarPlan(planId: number): Promise<boolean> {
  const r = await llamar(`/subscription/plan/${planId}/deactivate`, {
    method: 'PATCH',
  })
  return r?.active === false
}

/**
 * Todos los planes de la organización, buscándolos en la cuenta de dLocal.
 *
 * Existe para rescatar pagos de enlaces viejos. Hasta el 29/07/2026 se creaba un
 * plan nuevo cada vez que alguien alternaba entre mensual y anual, y el webhook
 * consultaba solo el último: un enlace de checkout anterior seguía vivo y
 * cobrable, pero su pago se registraba como rechazado porque mirábamos otro
 * plan. Quedaron siete planes así en la cuenta real.
 *
 * La pista es la descripción, que `crearPlan` escribe con el UUID de la
 * organización adentro: "Suscripción de SONICO (01981234-...)". Verificado
 * contra la API el 29/07/2026.
 *
 * Se usa SOLO como respaldo, cuando los planes guardados no dieron resultado:
 * recorre páginas de a diez y en el caso normal no se llama nunca.
 *
 * [maxPaginas] acota el recorrido. La cuenta es compartida con otros proyectos,
 * así que la lista crece por motivos ajenos a esta app y no conviene dejar el
 * bucle sin techo.
 */
export async function planesDeLaOrganizacion(
  organizationId: string,
  maxPaginas = 10,
): Promise<number[]> {
  const encontrados: number[] = []

  for (let page = 1; page <= maxPaginas; page++) {
    const respuesta = await llamar(
      `/subscription/plan/all?page=${page}`,
    ).catch(() => null)

    const planes = respuesta?.data ?? []
    if (planes.length === 0) break

    for (const p of planes) {
      const texto = `${p?.description ?? ''} ${p?.name ?? ''}`
      if (texto.includes(organizationId) && typeof p?.id === 'number') {
        encontrados.push(p.id)
      }
    }

    // `total_pages` viene en la respuesta; si no, se corta cuando una página
    // vuelve vacía.
    if (respuesta?.total_pages && page >= respuesta.total_pages) break
  }

  return encontrados
}
