-- El muro del cupo gratuito no se activaba nunca. Nadie pagaba nunca.
--
-- `guard_organization_active` descuenta el cupo y verifica el límite con el
-- MISMO UPDATE: si el WHERE no encuentra la fila, es porque el cupo se agotó.
-- La secuencia era:
--
--     UPDATE public.organizations o
--        SET free_tickets_used = o.free_tickets_used + 1
--      WHERE o.id = v_org
--        AND (o.plan <> 'trial' OR o.free_tickets_limit IS NULL
--             OR o.free_tickets_used < o.free_tickets_limit)
--     RETURNING o.free_tickets_used INTO v_used;
--
--     PERFORM set_config('imagine.descontando_cupo', '', true);   -- <<<
--
--     IF NOT FOUND THEN
--       RAISE EXCEPTION 'FREE_QUOTA_EXHAUSTED';
--     END IF;
--
-- `PERFORM` REESCRIBE `FOUND`. Es una variable global de PL/pgSQL que se
-- actualiza con cada sentencia que devuelve filas, y `set_config()` devuelve
-- una. Así que entre el UPDATE y la verificación, `FOUND` pasaba a `true`
-- SIEMPRE, y el `IF NOT FOUND` no se cumplía nunca.
--
-- Efecto: con el cupo agotado (15 de 15, plan trial) el ticket se emitía igual.
-- El modelo de "15 gratis y después se cobra" no cobraba nunca. Verificado
-- antes del arreglo: caso 15/15 -> el INSERT pasaba.
--
-- La corrección es capturar el conteo de filas con GET DIAGNOSTICS
-- INMEDIATAMENTE después del UPDATE, antes de que cualquier otra sentencia
-- toque `FOUND`. Se usa una variable propia justamente para no depender de un
-- estado global que cualquier línea nueva puede pisar sin que se note.
--
-- Idempotente: reemplaza la función completa.

CREATE OR REPLACE FUNCTION public.guard_organization_active()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org        UUID;
  v_used       INT;
  v_afectadas  INT;
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

  -- El descuento del cupo y su verificación son el MISMO UPDATE: el WHERE hace
  -- de control. Si no encuentra la fila, el cupo está agotado.
  UPDATE public.organizations o
     SET free_tickets_used = o.free_tickets_used + 1
   WHERE o.id = v_org
     AND (o.plan <> 'trial'
          OR o.free_tickets_limit IS NULL
          OR o.free_tickets_used < o.free_tickets_limit)
  RETURNING o.free_tickets_used INTO v_used;

  -- ACÁ MISMO, antes de cualquier otra sentencia. `FOUND` es global de
  -- PL/pgSQL y la reescribe todo lo que devuelva filas —incluido el
  -- `PERFORM set_config` que viene abajo—, así que el conteo se guarda en una
  -- variable propia. Depender de `FOUND` a distancia fue exactamente el bug.
  GET DIAGNOSTICS v_afectadas = ROW_COUNT;

  PERFORM set_config('imagine.descontando_cupo', '', true);

  IF v_afectadas = 0 THEN
    RAISE EXCEPTION 'FREE_QUOTA_EXHAUSTED'
      USING HINT = 'Se agotaron los tickets gratuitos. Activá la suscripción.';
  END IF;

  RETURN NEW;
END $function$;
