-- Las columnas de facturación no las puede tocar el propio tenant.
--
-- La policy "Org owner update" deja al dueño modificar su fila de
-- `organizations`, que es correcto para nombre, logo o datos fiscales. Pero en
-- esa misma fila viven el plan, el vencimiento y el cupo gratuito.
--
-- Verificado con un ataque real el 28/07/2026, suplantando al dueño con rol
-- `authenticated`: los tres funcionaron.
--   UPDATE ... SET free_tickets_limit = 999999        -> cupo infinito
--   UPDATE ... SET plan='annual', expires = +10 years -> gratis para siempre
--   UPDATE ... SET free_tickets_used = 0              -> cupo reciclable
--
-- Se hace desde el navegador con una sola llamada a PostgREST: la anon key es
-- pública y el usuario ya tiene un JWT válido. Sin este guard, todo el cobro es
-- decorativo.
--
-- Idempotente.

CREATE OR REPLACE FUNCTION public.guard_billing_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol TEXT;
BEGIN
  v_rol := COALESCE(
    current_setting('request.jwt.claims', true)::json->>'role', '');

  -- Pasan sin restricción:
  --   service_role  -> las Edge Functions, que son las que cobran
  --   superadmin    -> el panel, que suspende y ajusta suscripciones
  --   auth.uid() NULL -> conexión directa a la base (migraciones, soporte).
  --     No abre un agujero: las policies de UPDATE exigen coincidir con
  --     owner_id, así que sin identidad no se llega hasta acá desde la API.
  IF v_rol = 'service_role'
     OR auth.uid() IS NULL
     OR public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  -- Para el resto se revierten los campos de facturación a su valor anterior.
  --
  -- Revertir y no abortar: el cliente manda la fila entera al guardar los datos
  -- de la organización, así que rechazar la operación rompería una pantalla
  -- legítima por incluir campos que no cambió. Se conserva lo que sí puede
  -- editar —nombre, país, datos fiscales— y se descarta lo demás.
  NEW.status                  := OLD.status;
  NEW.plan                    := OLD.plan;
  NEW.subscription_expires_at := OLD.subscription_expires_at;
  NEW.suspended_reason        := OLD.suspended_reason;
  NEW.free_tickets_used       := OLD.free_tickets_used;
  NEW.free_tickets_limit      := OLD.free_tickets_limit;
  NEW.dlocal_plan_id          := OLD.dlocal_plan_id;
  NEW.dlocal_plan_token       := OLD.dlocal_plan_token;
  NEW.currency                := OLD.currency;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS guard_billing_on_organizations ON public.organizations;

CREATE TRIGGER guard_billing_on_organizations
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.guard_billing_columns();

-- El trigger del cupo (guard_organization_active) descuenta con un UPDATE sobre
-- esta misma tabla. Corre como SECURITY DEFINER pero `request.jwt.claims` sigue
-- siendo el del usuario, así que caería en la rama que revierte y el contador
-- nunca subiría. Se le da una vía explícita en vez de dejarlo al azar.
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
  IF TG_TABLE_NAME = 'events' THEN
    v_org := NEW.organization_id;
  ELSE
    SELECT e.organization_id INTO v_org
      FROM public.events e WHERE e.id = NEW.event_id;
  END IF;

  IF v_org IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT public.organization_is_active(v_org) THEN
    RAISE EXCEPTION 'ORGANIZATION_INACTIVE'
      USING HINT = 'La suscripción está vencida o la cuenta suspendida.';
  END IF;

  IF TG_TABLE_NAME = 'events' THEN
    RETURN NEW;
  END IF;

  -- Marca que este UPDATE viene del descuento de cupo y no de un cliente.
  -- guard_billing_columns la lee para dejarlo pasar.
  PERFORM set_config('imagine.descontando_cupo', 'si', true);

  UPDATE public.organizations o
     SET free_tickets_used = o.free_tickets_used + 1
   WHERE o.id = v_org
     AND (o.plan <> 'trial'
          OR o.free_tickets_limit IS NULL
          OR o.free_tickets_used < o.free_tickets_limit)
  RETURNING o.free_tickets_used INTO v_used;

  PERFORM set_config('imagine.descontando_cupo', '', true);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FREE_QUOTA_EXHAUSTED'
      USING HINT = 'Se agotaron los tickets gratuitos. Activá la suscripción.';
  END IF;

  RETURN NEW;
END $$;

-- La excepción para el descuento de cupo, en el guard de facturación.
CREATE OR REPLACE FUNCTION public.guard_billing_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol TEXT;
BEGIN
  v_rol := COALESCE(
    current_setting('request.jwt.claims', true)::json->>'role', '');

  IF v_rol = 'service_role'
     OR auth.uid() IS NULL
     OR public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  -- Descuento de cupo: solo puede subir el contador de a uno, nada más.
  -- Acotado así, la marca no sirve para nada más aunque alguien la pusiera:
  -- cualquier otro campo se revierte igual, y el contador solo puede crecer.
  IF COALESCE(current_setting('imagine.descontando_cupo', true), '') = 'si'
     AND NEW.free_tickets_used = OLD.free_tickets_used + 1 THEN
    NEW.status                  := OLD.status;
    NEW.plan                    := OLD.plan;
    NEW.subscription_expires_at := OLD.subscription_expires_at;
    NEW.suspended_reason        := OLD.suspended_reason;
    NEW.free_tickets_limit      := OLD.free_tickets_limit;
    NEW.dlocal_plan_id          := OLD.dlocal_plan_id;
    NEW.dlocal_plan_token       := OLD.dlocal_plan_token;
    NEW.currency                := OLD.currency;
    RETURN NEW;
  END IF;

  NEW.status                  := OLD.status;
  NEW.plan                    := OLD.plan;
  NEW.subscription_expires_at := OLD.subscription_expires_at;
  NEW.suspended_reason        := OLD.suspended_reason;
  NEW.free_tickets_used       := OLD.free_tickets_used;
  NEW.free_tickets_limit      := OLD.free_tickets_limit;
  NEW.dlocal_plan_id          := OLD.dlocal_plan_id;
  NEW.dlocal_plan_token       := OLD.dlocal_plan_token;
  NEW.currency                := OLD.currency;

  RETURN NEW;
END $$;
