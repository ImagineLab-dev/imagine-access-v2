-- Cobro de suscripción con dLocal Go.
--
-- dLocal Go no tiene ningún campo de referencia libre en el plan ni en el
-- checkout: cuando llega el aviso de pago, lo único que identifica al que pagó
-- es a QUÉ plan se suscribió. Por eso se crea un plan de dLocal por
-- organización, en vez de uno compartido. Es el mismo patrón que ya usa
-- Chillberry en esta cuenta de comercio.
--
-- Verificado el 28/07/2026 contra la API: GET /v1/subscription/plan/{id}
-- devuelve name, amount, currency, frequency y plan_token, y ninguno de esos
-- campos sirve para distinguir suscriptores dentro de un mismo plan.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) El plan de dLocal de cada organización
-- -----------------------------------------------------------------------------
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS dlocal_plan_id    BIGINT,
  ADD COLUMN IF NOT EXISTS dlocal_plan_token TEXT;

-- -----------------------------------------------------------------------------
-- 2) Historial de cobros
-- -----------------------------------------------------------------------------
-- Toda extensión de vencimiento deja rastro. Cuando alguien reclame que pagó y
-- el sistema diga que no, esta tabla es la única respuesta posible; sin ella
-- la discusión se resuelve mirando el panel de dLocal a mano.
CREATE TABLE IF NOT EXISTS public.subscription_events (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
  event           TEXT NOT NULL,      -- 'checkout_created' | 'payment_confirmed' | 'payment_rejected'
  dlocal_plan_id  BIGINT,
  amount          NUMERIC(12,2),
  currency        TEXT,
  extended_to     TIMESTAMPTZ,
  reference       TEXT,               -- id del cobro en dLocal, para no acreditarlo dos veces
  payload         JSONB,              -- el aviso crudo, tal como llegó
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sin índice único sobre `reference`: el id de suscripción de dLocal se repite
-- en cada renovación, y un único rechazaría el cobro del mes siguiente. La
-- protección contra reintentos vive en apply_subscription_payment, por ventana
-- de tiempo. `reference` queda como dato de auditoría.

CREATE INDEX IF NOT EXISTS subscription_events_org_idx
  ON public.subscription_events (organization_id, created_at DESC);

ALTER TABLE public.subscription_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='subscription_events' AND policyname='Own org reads subscription events'
  ) THEN
    -- Solo lectura. El historial de cobros lo escribe únicamente el webhook,
    -- con service_role: un registro que el interesado puede editar no sirve
    -- para dirimir nada.
    CREATE POLICY "Own org reads subscription events" ON public.subscription_events
      FOR SELECT USING (
        public.is_superadmin()
        OR organization_id IN (
          SELECT p.organization_id FROM public.users_profile p
           WHERE p.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3) Acreditar un pago
-- -----------------------------------------------------------------------------
-- El vencimiento se extiende desde la fecha que sea MAYOR entre hoy y el
-- vencimiento actual. Si alguien paga tres días antes de vencer, esos tres días
-- no se pierden; si paga un mes después de vencido, no se le regalan los que
-- estuvo sin pagar.
CREATE OR REPLACE FUNCTION public.apply_subscription_payment(
  p_organization_id UUID,
  p_plan            TEXT,
  p_amount          NUMERIC DEFAULT NULL,
  p_currency        TEXT DEFAULT 'USD',
  p_dlocal_plan_id  BIGINT DEFAULT NULL,
  p_payload         JSONB DEFAULT NULL,
  p_reference       TEXT DEFAULT NULL
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_desde  TIMESTAMPTZ;
  v_hasta  TIMESTAMPTZ;
  v_lapso  INTERVAL;
  v_previo TIMESTAMPTZ;
BEGIN
  -- Idempotencia por VENTANA DE TIEMPO, no por referencia del cobro.
  --
  -- La referencia natural sería el id de la suscripción en dLocal, pero ese id
  -- NO cambia entre renovaciones: el segundo mes llegaría con el mismo y se
  -- descartaría como duplicado, dejando vencer a alguien que sigue pagando.
  --
  -- Los reintentos de dLocal ocurren en minutos u horas; una renovación real
  -- llega recién al mes. Una ventana de 24 horas separa los dos casos sin
  -- depender de campos del aviso cuyo nombre no está documentado.
  SELECT e.extended_to INTO v_previo
    FROM public.subscription_events e
   WHERE e.organization_id = p_organization_id
     AND e.event = 'payment_confirmed'
     AND e.created_at > now() - interval '24 hours'
   ORDER BY e.created_at DESC
   LIMIT 1;

  IF v_previo IS NOT NULL THEN
    RETURN v_previo;
  END IF;

  IF p_plan NOT IN ('monthly', 'annual') THEN
    RAISE EXCEPTION 'Plan inválido: %', p_plan;
  END IF;

  v_lapso := CASE p_plan WHEN 'annual' THEN interval '1 year'
                         ELSE interval '1 month' END;

  SELECT GREATEST(COALESCE(o.subscription_expires_at, now()), now())
    INTO v_desde
    FROM public.organizations o
   WHERE o.id = p_organization_id;

  IF v_desde IS NULL THEN
    RAISE EXCEPTION 'Organización inexistente: %', p_organization_id;
  END IF;

  v_hasta := v_desde + v_lapso;

  UPDATE public.organizations
     SET plan = p_plan,
         subscription_expires_at = v_hasta,
         -- Un pago acreditado reactiva a quien estaba vencido, pero NO levanta
         -- una suspensión puesta a mano desde el panel: esa la sacó una
         -- persona por un motivo, y no le corresponde revertirla a un webhook.
         status = CASE WHEN status = 'suspended' THEN status ELSE 'active' END
   WHERE id = p_organization_id;

  INSERT INTO public.subscription_events
    (organization_id, event, dlocal_plan_id, amount, currency, extended_to,
     reference, payload)
  VALUES
    (p_organization_id, 'payment_confirmed', p_dlocal_plan_id, p_amount,
     p_currency, v_hasta, p_reference, p_payload);

  RETURN v_hasta;
END $$;

REVOKE ALL ON FUNCTION public.apply_subscription_payment(UUID, TEXT, NUMERIC, TEXT, BIGINT, JSONB, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_subscription_payment(UUID, TEXT, NUMERIC, TEXT, BIGINT, JSONB, TEXT) TO service_role;
