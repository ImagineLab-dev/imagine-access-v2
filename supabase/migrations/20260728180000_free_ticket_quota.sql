-- La prueba pasa de ser por TIEMPO a ser por USO: 15 tickets gratis.
--
-- Los 14 días castigaban justo al cliente típico: un productor se registra tres
-- semanas antes de su fiesta, arma el evento, y para cuando emite el primer
-- ticket la prueba ya venció sin haber recibido nada. Un cupo de tickets se
-- consume solo cuando el sistema hizo algo de valor.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) El cupo
-- -----------------------------------------------------------------------------
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS free_tickets_used  INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS free_tickets_limit INT;

-- La columna se agrega SIN default y el default se pone después, a propósito:
-- así las organizaciones que ya existían quedan en NULL —sin cupo— y solo las
-- nuevas arrancan con 15. Agregarla con DEFAULT 15 se lo habría aplicado
-- también a las de antes, cortándoles el servicio de un día para el otro.
ALTER TABLE public.organizations
  ALTER COLUMN free_tickets_limit SET DEFAULT 15;

-- Ya no hay vencimiento por tiempo durante la prueba: el límite es el cupo.
ALTER TABLE public.organizations
  ALTER COLUMN subscription_expires_at DROP DEFAULT;

COMMENT ON COLUMN public.organizations.free_tickets_used IS
  'Tickets emitidos contra el cupo gratuito. Solo sube: no baja al anular ni '
  'borrar un ticket, para que el cupo no se pueda reciclar emitiendo y anulando.';
COMMENT ON COLUMN public.organizations.free_tickets_limit IS
  'Cupo gratuito de por vida. NULL = sin cupo (organizaciones anteriores al cobro).';

-- -----------------------------------------------------------------------------
-- 2) El guard, ahora con cupo
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_organization_active()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org  UUID;
  v_used INT;
BEGIN
  -- events lleva organization_id directo; tickets llega por su evento.
  IF TG_TABLE_NAME = 'events' THEN
    v_org := NEW.organization_id;
  ELSE
    SELECT e.organization_id INTO v_org
      FROM public.events e WHERE e.id = NEW.event_id;
  END IF;

  IF v_org IS NULL THEN
    RETURN NEW;
  END IF;

  -- Suspendida o vencida: no se crea nada, ni evento ni ticket.
  IF NOT public.organization_is_active(v_org) THEN
    RAISE EXCEPTION 'ORGANIZATION_INACTIVE'
      USING HINT = 'La suscripción está vencida o la cuenta suspendida.';
  END IF;

  -- Crear EVENTOS no consume cupo. Alguien en prueba tiene que poder armar su
  -- evento entero y recién toparse con el límite al emitir tickets; frenarlo
  -- antes de eso no le deja ver lo que estaría comprando.
  IF TG_TABLE_NAME = 'events' THEN
    RETURN NEW;
  END IF;

  -- El descuento del cupo y su verificación son el MISMO UPDATE: el WHERE hace
  -- de condición y el bloqueo de fila serializa a dos emisiones simultáneas.
  -- Leer el contador y después decidir dejaría pasar el ticket 16 cuando dos
  -- llegan juntos.
  UPDATE public.organizations o
     SET free_tickets_used = o.free_tickets_used + 1
   WHERE o.id = v_org
     AND (o.plan <> 'trial'
          OR o.free_tickets_limit IS NULL
          OR o.free_tickets_used < o.free_tickets_limit)
  RETURNING o.free_tickets_used INTO v_used;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FREE_QUOTA_EXHAUSTED'
      USING HINT = 'Se agotaron los tickets gratuitos. Activá la suscripción.';
  END IF;

  RETURN NEW;
END $$;

-- -----------------------------------------------------------------------------
-- 3) El estado que ve el cliente
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.my_subscription();

CREATE FUNCTION public.my_subscription()
RETURNS TABLE (
  organization_id UUID,
  status TEXT,
  plan TEXT,
  currency TEXT,
  country TEXT,
  expires_at TIMESTAMPTZ,
  days_left INT,
  is_active BOOLEAN,
  suspended_reason TEXT,
  free_tickets_used INT,
  free_tickets_limit INT,
  free_tickets_left INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT o.id,
         o.status,
         o.plan,
         o.currency,
         o.country,
         o.subscription_expires_at,
         CASE
           WHEN o.subscription_expires_at IS NULL THEN NULL
           ELSE EXTRACT(DAY FROM (o.subscription_expires_at - now()))::INT
         END,
         (o.status = 'active'
          AND (o.subscription_expires_at IS NULL
               OR o.subscription_expires_at > now())),
         o.suspended_reason,
         o.free_tickets_used,
         o.free_tickets_limit,
         CASE
           WHEN o.plan <> 'trial' OR o.free_tickets_limit IS NULL THEN NULL
           ELSE GREATEST(o.free_tickets_limit - o.free_tickets_used, 0)
         END
    FROM public.organizations o
    JOIN public.users_profile p ON p.organization_id = o.id
   WHERE p.user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.my_subscription() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_subscription() TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) El panel de super-admin ve el cupo
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.superadmin_list_tenants();

CREATE FUNCTION public.superadmin_list_tenants()
RETURNS TABLE (
  id UUID,
  name TEXT,
  slug TEXT,
  status TEXT,
  plan TEXT,
  subscription_expires_at TIMESTAMPTZ,
  tax_id TEXT,
  contact_email TEXT,
  created_at TIMESTAMPTZ,
  users_count BIGINT,
  events_count BIGINT,
  tickets_count BIGINT,
  last_activity TIMESTAMPTZ,
  country TEXT,
  currency TEXT,
  emails_this_month INT,
  free_tickets_used INT,
  free_tickets_limit INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  RETURN QUERY
  SELECT o.id, o.name, o.slug, o.status, o.plan, o.subscription_expires_at,
         o.tax_id, o.contact_email, o.created_at,
         (SELECT count(*) FROM public.users_profile p WHERE p.organization_id = o.id),
         (SELECT count(*) FROM public.events e WHERE e.organization_id = o.id),
         (SELECT count(*) FROM public.tickets t
            JOIN public.events e2 ON e2.id = t.event_id
           WHERE e2.organization_id = o.id),
         (SELECT max(t2.created_at) FROM public.tickets t2
            JOIN public.events e3 ON e3.id = t2.event_id
           WHERE e3.organization_id = o.id),
         o.country, o.currency,
         COALESCE((SELECT u.sent_count FROM public.organization_email_usage u
                    WHERE u.organization_id = o.id
                      AND u.period = date_trunc('month', now())::DATE), 0),
         o.free_tickets_used, o.free_tickets_limit
    FROM public.organizations o
   ORDER BY o.created_at DESC;
END $$;

REVOKE ALL ON FUNCTION public.superadmin_list_tenants() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.superadmin_list_tenants() TO authenticated;

-- -----------------------------------------------------------------------------
-- 5) Al pagar, el cupo deja de aplicar
-- -----------------------------------------------------------------------------
-- No hace falta tocar apply_subscription_payment: pone plan = 'monthly' o
-- 'annual', y el guard solo mira el cupo cuando plan = 'trial'.
