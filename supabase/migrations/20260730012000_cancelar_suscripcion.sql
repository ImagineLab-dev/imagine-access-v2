-- Cancelar la suscripción sin perder lo que ya se pagó.
--
-- No había forma de darse de baja del cobro. Un cliente que quiere irse y no
-- encuentra cómo termina llamando al banco a desconocer el cargo, que es la peor
-- versión de la misma conversación.
--
-- Regla: cancelar detiene la RENOVACIÓN, no el servicio. Se conserva el acceso
-- hasta `subscription_expires_at`, que es hasta donde está pagado. Cobrar un mes
-- y cortarlo a mitad de camino porque el cliente avisó que no sigue sería
-- quedarse con plata por un servicio no prestado.
--
-- Hace falta una marca nueva porque `plan` y `subscription_expires_at` no
-- alcanzan para distinguir "paga y sigue" de "paga pero ya avisó que no
-- renueva". Sin ella la pantalla no puede decir la verdad.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) La marca
-- -----------------------------------------------------------------------------
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS subscription_cancelled_at TIMESTAMPTZ;

COMMENT ON COLUMN public.organizations.subscription_cancelled_at IS
  'Cuándo pidió la baja del cobro. El acceso sigue hasta subscription_expires_at: '
  'esto detiene la renovación, no el servicio. Nulo = suscripción corriendo.';

-- -----------------------------------------------------------------------------
-- 2) Es columna de facturación: el guard la protege
-- -----------------------------------------------------------------------------
-- Sin esto, un cliente podría borrar su propia marca de cancelación por
-- PostgREST y aparentar una suscripción vigente.
CREATE OR REPLACE FUNCTION public.guard_billing_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rol TEXT;
BEGIN
  v_rol := public.rol_del_claim();

  IF v_rol = 'service_role'
     OR auth.uid() IS NULL
     OR public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status                    := 'active';
    NEW.plan                      := 'trial';
    NEW.subscription_expires_at   := NULL;
    NEW.subscription_cancelled_at := NULL;
    NEW.suspended_reason          := NULL;
    NEW.free_tickets_used         := 0;
    NEW.free_tickets_limit        := 15;
    NEW.dlocal_plan_id            := NULL;
    NEW.dlocal_plan_token         := NULL;
    NEW.dlocal_plans              := '{}'::jsonb;
    RETURN NEW;
  END IF;

  IF COALESCE(current_setting('imagine.descontando_cupo', true), '') = 'si'
     AND NEW.free_tickets_used = OLD.free_tickets_used + 1 THEN
    NEW.status                    := OLD.status;
    NEW.plan                      := OLD.plan;
    NEW.subscription_expires_at   := OLD.subscription_expires_at;
    NEW.subscription_cancelled_at := OLD.subscription_cancelled_at;
    NEW.suspended_reason          := OLD.suspended_reason;
    NEW.free_tickets_limit        := OLD.free_tickets_limit;
    NEW.dlocal_plan_id            := OLD.dlocal_plan_id;
    NEW.dlocal_plan_token         := OLD.dlocal_plan_token;
    NEW.dlocal_plans              := OLD.dlocal_plans;
    NEW.currency                  := OLD.currency;
    RETURN NEW;
  END IF;

  NEW.status                    := OLD.status;
  NEW.plan                      := OLD.plan;
  NEW.subscription_expires_at   := OLD.subscription_expires_at;
  NEW.subscription_cancelled_at := OLD.subscription_cancelled_at;
  NEW.suspended_reason          := OLD.suspended_reason;
  NEW.free_tickets_used         := OLD.free_tickets_used;
  NEW.free_tickets_limit        := OLD.free_tickets_limit;
  NEW.dlocal_plan_id            := OLD.dlocal_plan_id;
  NEW.dlocal_plan_token         := OLD.dlocal_plan_token;
  NEW.dlocal_plans              := OLD.dlocal_plans;
  NEW.currency                  := OLD.currency;

  RETURN NEW;
END $function$;

-- -----------------------------------------------------------------------------
-- 3) La operación
-- -----------------------------------------------------------------------------
-- Se llama DESPUÉS de que la Edge Function confirmó la baja en dLocal. Si se
-- marcara antes y el corte fallara, la pantalla diría "cancelada" mientras el
-- cobro sigue: la peor combinación posible.
CREATE OR REPLACE FUNCTION public.marcar_suscripcion_cancelada()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid   UUID := auth.uid();
  v_org   public.organizations%ROWTYPE;
  v_orgid UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NO_AUTENTICADO';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'SOLO_ADMIN'
      USING HINT = 'Solo quien administra la organización puede dar de baja el cobro.';
  END IF;

  v_orgid := public.get_my_organization_id();
  SELECT * INTO v_org FROM public.organizations WHERE id = v_orgid;

  IF v_org.id IS NULL THEN
    RAISE EXCEPTION 'SIN_ORGANIZACION';
  END IF;

  IF v_org.plan = 'trial' OR v_org.plan IS NULL THEN
    RAISE EXCEPTION 'SIN_SUSCRIPCION'
      USING HINT = 'No hay una suscripción paga que dar de baja.';
  END IF;

  IF v_org.subscription_cancelled_at IS NOT NULL THEN
    -- Idempotente a propósito: si el aviso llega dos veces, o alguien toca el
    -- botón dos veces, la respuesta es la misma y no se registra otro evento.
    RETURN jsonb_build_object(
      'ok', true, 'ya_estaba', true,
      'acceso_hasta', v_org.subscription_expires_at);
  END IF;

  UPDATE public.organizations
     SET subscription_cancelled_at = now()
   WHERE id = v_org.id;

  INSERT INTO public.subscription_events
    (organization_id, event, dlocal_plan_id, extended_to, payload)
  VALUES
    (v_org.id, 'cancelled', v_org.dlocal_plan_id, v_org.subscription_expires_at,
     jsonb_build_object('pedida_por', v_uid, 'plan', v_org.plan));

  RETURN jsonb_build_object(
    'ok', true,
    'ya_estaba', false,
    'plan', v_org.plan,
    'acceso_hasta', v_org.subscription_expires_at);
END;
$function$;

REVOKE ALL ON FUNCTION public.marcar_suscripcion_cancelada() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marcar_suscripcion_cancelada() TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) Comprobación
-- -----------------------------------------------------------------------------
DO $mig$
DECLARE v_def TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='organizations'
                    AND column_name='subscription_cancelled_at') THEN
    RAISE EXCEPTION 'falta la columna subscription_cancelled_at';
  END IF;

  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE proname='guard_billing_columns' AND pronamespace='public'::regnamespace;

  IF (length(v_def) - length(replace(v_def, 'subscription_cancelled_at', '')))
     / length('subscription_cancelled_at') < 3 THEN
    RAISE EXCEPTION 'el guard no protege subscription_cancelled_at en las tres ramas';
  END IF;

  RAISE NOTICE 'OK: cancelacion lista y la marca esta protegida en las tres ramas';
END $mig$;
