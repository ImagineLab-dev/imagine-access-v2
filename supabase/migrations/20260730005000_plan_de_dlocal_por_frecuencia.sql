-- Un plan de dLocal por frecuencia, no uno solo para las dos.
--
-- `organizations` guardaba UN `dlocal_plan_id`, pero el producto tiene DOS
-- planes: mensual (USD 25) y anual (USD 250). En `dlocal_subscribe`:
--
--     if (org.dlocal_plan_id) {
--       planDLocal = await obtenerPlan(org.dlocal_plan_id)
--       if (planDLocal.frequency_type !== precio.frecuencia) planDLocal = null
--     }
--     if (!planDLocal) { planDLocal = await crearPlan(...) }   // <<<
--
-- Alternar entre mensual y anual descarta el plan guardado por no coincidir la
-- frecuencia, y crea otro. Cada clic en el otro plan = un plan nuevo en dLocal.
--
-- Comprobado en la cuenta real: 20 planes, y siete llamados "Imagine Access -
-- SONICO" alternando importes de forma perfecta —25, 250, 25, 250, 25, 250,
-- 25—, que es la huella exacta de este bug.
--
-- Lo grave no es el desorden sino esto: el webhook consulta ÚNICAMENTE el plan
-- guardado. Si alguien abre el enlace mensual, después mira el anual (lo que
-- sobreescribe `dlocal_plan_id`) y luego completa el pago del PRIMERO, la
-- consulta a dLocal se hace contra el plan equivocado, no encuentra la
-- suscripción y el cobro se registra como `payment_rejected`. El cliente paga y
-- no recibe nada.
--
-- Se verificó que eso no pasó todavía: los 20 planes de la cuenta tienen CERO
-- suscripciones, así que nadie completó un pago nunca y no hay plata perdida.
--
-- La solución es guardar un plan POR frecuencia. Se usa jsonb en vez de cuatro
-- columnas nuevas para que agregar un plan mañana —trimestral, por ejemplo— no
-- vuelva a requerir una migración de esquema:
--
--     {"monthly": {"id": 22867, "token": "..."},
--      "annual":  {"id": 22862, "token": "..."}}
--
-- `dlocal_plan_id` y `dlocal_plan_token` se conservan apuntando al último plan
-- usado. No son redundantes: el panel de super-admin los lee, y dejarlos evita
-- tocar más superficie de la necesaria en el mismo cambio.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) La columna
-- -----------------------------------------------------------------------------
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS dlocal_plans JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.organizations.dlocal_plans IS
  'Plan de dLocal por frecuencia: {"monthly":{"id":N,"token":"..."},"annual":{...}}. '
  'Antes se guardaba uno solo y alternar de plan creaba uno nuevo en dLocal cada '
  'vez, dejando enlaces de pago vivos apuntando a planes que el webhook ya no '
  'consultaba.';

-- -----------------------------------------------------------------------------
-- 2) Es una columna de facturación: el guard tiene que protegerla
-- -----------------------------------------------------------------------------
-- Sin esto, un cliente podría escribir ahí el plan de OTRA organización y
-- hacer que su webhook mire una suscripción ajena. Se agrega a las dos ramas
-- —forzar en INSERT, revertir en UPDATE— igual que el resto.
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

  IF TG_OP = 'INSERT' THEN
    NEW.status                  := 'active';
    NEW.plan                    := 'trial';
    NEW.subscription_expires_at := NULL;
    NEW.suspended_reason        := NULL;
    NEW.free_tickets_used       := 0;
    NEW.free_tickets_limit      := 15;
    NEW.dlocal_plan_id          := NULL;
    NEW.dlocal_plan_token       := NULL;
    NEW.dlocal_plans            := '{}'::jsonb;
    RETURN NEW;
  END IF;

  IF COALESCE(current_setting('imagine.descontando_cupo', true), '') = 'si'
     AND NEW.free_tickets_used = OLD.free_tickets_used + 1 THEN
    NEW.status                  := OLD.status;
    NEW.plan                    := OLD.plan;
    NEW.subscription_expires_at := OLD.subscription_expires_at;
    NEW.suspended_reason        := OLD.suspended_reason;
    NEW.free_tickets_limit      := OLD.free_tickets_limit;
    NEW.dlocal_plan_id          := OLD.dlocal_plan_id;
    NEW.dlocal_plan_token       := OLD.dlocal_plan_token;
    NEW.dlocal_plans            := OLD.dlocal_plans;
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
  NEW.dlocal_plans            := OLD.dlocal_plans;
  NEW.currency                := OLD.currency;

  RETURN NEW;
END $function$;

-- -----------------------------------------------------------------------------
-- 3) Comprobación
-- -----------------------------------------------------------------------------
DO $mig$
DECLARE
  v_def TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='organizations'
       AND column_name='dlocal_plans'
  ) THEN
    RAISE EXCEPTION 'falta la columna dlocal_plans';
  END IF;

  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE proname='guard_billing_columns' AND pronamespace='public'::regnamespace;

  -- Tres veces: una por cada rama del guard (INSERT, descuento de cupo, resto).
  IF (length(v_def) - length(replace(v_def, 'dlocal_plans', ''))) / length('dlocal_plans') < 3 THEN
    RAISE EXCEPTION 'el guard no protege dlocal_plans en las tres ramas';
  END IF;

  RAISE NOTICE 'OK: dlocal_plans creada y protegida por el guard en las tres ramas';
END $mig$;
