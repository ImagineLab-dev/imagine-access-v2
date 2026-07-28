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
