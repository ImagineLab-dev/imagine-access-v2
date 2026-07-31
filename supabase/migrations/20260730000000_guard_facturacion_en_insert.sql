-- El guard de facturación cubría el UPDATE y no el INSERT.
--
-- `guard_billing_on_organizations` era BEFORE UPDATE solamente, y la política de
-- RLS para insertar organizaciones solo exige `owner_id = auth.uid()`. Con eso,
-- la cadena completa era:
--
--   1. INSERT INTO organizations (..., owner_id = yo, plan = 'monthly',
--                                 free_tickets_limit = NULL,
--                                 subscription_expires_at = now() + 50 años)
--   2. UPDATE users_profile SET organization_id = <la nueva>
--
-- El paso 2 lo permite `guard_profile_self_update`, que deja a un admin cambiar
-- su organización. Resultado: cualquier persona que se registre —al registrarse
-- queda admin de su propia organización— se autoconcede el plan pago, con cupo
-- ilimitado y vencimiento a cincuenta años, sin pagar.
--
-- Verificado con una prueba real como admin común: el INSERT pasaba, el UPDATE
-- lo revertía el guard, y mudar el perfil pasaba.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) El guard ahora entiende INSERT
-- -----------------------------------------------------------------------------
-- En un INSERT no existe OLD, así que no se puede "revertir al valor anterior":
-- lo que se hace es FORZAR los valores seguros de una organización nueva. Son
-- los mismos que ya tienen las columnas como DEFAULT, así que ningún alta
-- legítima cambia de comportamiento: `ensure_profile` y
-- `auto_create_org_on_profile_insert` insertan nombre, slug, dueño y país, y
-- nunca tocan estas columnas.
--
-- Las exenciones se conservan tal cual estaban:
--   service_role      -> las Edge Functions y el webhook de dLocal
--   auth.uid() IS NULL-> migraciones y mantenimiento por consola
--   is_superadmin()   -> el dueño de la plataforma asigna y suspende planes
CREATE OR REPLACE FUNCTION public.guard_billing_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

  -- ---------------------------------------------------------------- INSERT
  IF TG_OP = 'INSERT' THEN
    -- Una organización nueva nace en prueba, con el cupo gratuito, sin
    -- vencimiento y sin plan de dLocal. Nada de eso lo elige el cliente.
    NEW.status                  := 'active';
    NEW.plan                    := 'trial';
    NEW.subscription_expires_at := NULL;
    NEW.suspended_reason        := NULL;
    NEW.free_tickets_used       := 0;
    NEW.free_tickets_limit      := 15;
    NEW.dlocal_plan_id          := NULL;
    NEW.dlocal_plan_token       := NULL;
    RETURN NEW;
  END IF;

  -- ---------------------------------------------------------------- UPDATE
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
END $function$;

-- -----------------------------------------------------------------------------
-- 2) El trigger, ahora también en INSERT
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS guard_billing_on_organizations ON public.organizations;
CREATE TRIGGER guard_billing_on_organizations
  BEFORE INSERT OR UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.guard_billing_columns();

-- -----------------------------------------------------------------------------
-- 3) Comprobación
-- -----------------------------------------------------------------------------
DO $mig$
DECLARE
  v_eventos TEXT;
BEGIN
  SELECT CASE WHEN (t.tgtype & 4) > 0 THEN 'INSERT ' ELSE '' END ||
         CASE WHEN (t.tgtype & 16) > 0 THEN 'UPDATE' ELSE '' END
    INTO v_eventos
    FROM pg_trigger t
   WHERE t.tgrelid = 'public.organizations'::regclass
     AND t.tgname = 'guard_billing_on_organizations';

  IF v_eventos IS DISTINCT FROM 'INSERT UPDATE' THEN
    RAISE EXCEPTION 'El guard no quedo en INSERT y UPDATE, quedo en: %', COALESCE(v_eventos, '(no existe)');
  END IF;

  RAISE NOTICE 'OK: guard_billing_on_organizations cubre INSERT y UPDATE';
END $mig$;
