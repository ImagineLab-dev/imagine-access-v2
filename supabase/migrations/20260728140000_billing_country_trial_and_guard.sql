-- Facturación: país, moneda, prueba de 14 días y el guard que efectivamente
-- bloquea a una organización suspendida o vencida.
--
-- Hasta ahora el super-admin podía marcar una organización como suspendida y
-- quedaba registrado, pero la app no le cortaba nada: seguía creando eventos y
-- emitiendo tickets igual. Una suspensión que no suspende es peor que no
-- tenerla, porque genera la creencia de que el cobro está protegido.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) País y moneda de la organización
-- -----------------------------------------------------------------------------
-- Se cobra en dólares en todas las plazas, así que `currency` hoy es siempre
-- USD. Existe igual como columna y no como constante en el código porque el día
-- que se cobre en moneda local hay que saber qué se le facturó a cada uno
-- históricamente, y eso no se puede reconstruir después.
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS country  TEXT,
  ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'USD';

-- Los 15 países donde dLocal opera y que la app ya ofrece en el selector de
-- zona horaria. NULL se admite: las organizaciones que existían antes de esta
-- migración no lo tienen cargado y no hay forma de adivinarlo.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.organizations'::regclass
      AND conname = 'organizations_country_check'
  ) THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT organizations_country_check
      CHECK (country IS NULL OR country IN (
        'PY','AR','UY','BR','CL','BO','CO','PE','EC',
        'PA','DO','CR','GT','SV','MX'
      ));
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2) Planes
-- -----------------------------------------------------------------------------
-- Un solo precio: USD 25/mes, o USD 250/año (dos meses bonificados). Armar
-- varios niveles antes de tener clientes es adivinar por qué cosa alguien
-- pagaría más — eso se descubre cuando lo piden.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.organizations'::regclass
      AND conname = 'organizations_plan_check'
  ) THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT organizations_plan_check
      CHECK (plan IN ('trial', 'monthly', 'annual'));
  END IF;
END $$;

-- Prueba de 14 días para toda organización nueva.
--
-- No hay columna `trial_ends_at` aparte: el vencimiento de la prueba y el de la
-- suscripción paga son la misma pregunta ("¿hasta cuándo tiene acceso?") y dos
-- columnas para una sola pregunta terminan contradiciéndose.
ALTER TABLE public.organizations
  ALTER COLUMN subscription_expires_at SET DEFAULT (now() + interval '14 days');

-- Las organizaciones que ya existían quedan con NULL, que significa "sin
-- vencimiento". Es deliberado: no se le corta el acceso a nadie que ya estaba
-- adentro por aplicar esta migración.

-- -----------------------------------------------------------------------------
-- 3) ¿Esta organización tiene acceso?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.organization_is_active(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organizations o
     WHERE o.id = p_organization_id
       AND o.status = 'active'
       AND (o.subscription_expires_at IS NULL
            OR o.subscription_expires_at > now())
  );
$$;

REVOKE ALL ON FUNCTION public.organization_is_active(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.organization_is_active(UUID) TO authenticated;

-- Lo que el cliente necesita para dibujar el estado de la cuenta. Devuelve solo
-- la organización de quien pregunta: no hace falta pasar un id, y así nadie
-- puede sondear el estado de suscripción de un tercero.
CREATE OR REPLACE FUNCTION public.my_subscription()
RETURNS TABLE (
  organization_id UUID,
  status TEXT,
  plan TEXT,
  currency TEXT,
  country TEXT,
  expires_at TIMESTAMPTZ,
  days_left INT,
  is_active BOOLEAN,
  suspended_reason TEXT
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
         o.suspended_reason
    FROM public.organizations o
    JOIN public.users_profile p ON p.organization_id = o.id
   WHERE p.user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.my_subscription() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_subscription() TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) El guard, del lado del servidor
-- -----------------------------------------------------------------------------
-- Un redirect en el router es cosmética: quien tenga el token puede seguir
-- llamando a la API igual. El corte tiene que estar en la base.
--
-- Se bloquea CREAR (eventos y tickets nuevos), no LEER ni VALIDAR. Dos razones:
--   - Leer: no se le secuestran los datos a nadie por no pagar. Puede entrar,
--     ver lo suyo y exportarlo.
--   - Validar: si una organización vence un sábado a la noche con 400 personas
--     en la puerta, cortarle el escáner deja gente afuera de un evento que ya
--     se vendió. El daño no lo paga el que no pagó: lo pagan sus clientes.
CREATE OR REPLACE FUNCTION public.guard_organization_active()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org UUID;
BEGIN
  -- events lleva organization_id directo; tickets llega por su evento.
  IF TG_TABLE_NAME = 'events' THEN
    v_org := NEW.organization_id;
  ELSE
    SELECT e.organization_id INTO v_org
      FROM public.events e WHERE e.id = NEW.event_id;
  END IF;

  IF v_org IS NOT NULL AND NOT public.organization_is_active(v_org) THEN
    RAISE EXCEPTION 'ORGANIZATION_INACTIVE'
      USING HINT = 'La suscripción está vencida o la cuenta suspendida.';
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS guard_active_on_events  ON public.events;
DROP TRIGGER IF EXISTS guard_active_on_tickets ON public.tickets;

CREATE TRIGGER guard_active_on_events
  BEFORE INSERT ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.guard_organization_active();

CREATE TRIGGER guard_active_on_tickets
  BEFORE INSERT ON public.tickets
  FOR EACH ROW EXECUTE FUNCTION public.guard_organization_active();

-- -----------------------------------------------------------------------------
-- 5) Volumen de correo por organización
-- -----------------------------------------------------------------------------
-- El único costo variable real del servicio. El plano de USD 25 no lo cobra,
-- pero hay que MEDIRLO desde el primer día: el riesgo no es perder plata, es
-- que el buzón de Hostinger corte los envíos en medio de un evento y el cliente
-- crea que la app se rompió. Un dato que no se guarda desde el principio no se
-- reconstruye después.
CREATE TABLE IF NOT EXISTS public.organization_email_usage (
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  period          DATE NOT NULL,   -- primer día del mes
  sent_count      INT  NOT NULL DEFAULT 0,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, period)
);

ALTER TABLE public.organization_email_usage ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='organization_email_usage' AND policyname='Own org reads email usage'
  ) THEN
    CREATE POLICY "Own org reads email usage" ON public.organization_email_usage
      FOR SELECT USING (
        public.is_superadmin()
        OR organization_id IN (
          SELECT p.organization_id FROM public.users_profile p
           WHERE p.user_id = auth.uid()
        )
      );
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.record_email_sent(
  p_organization_id UUID,
  p_count INT DEFAULT 1
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.organization_email_usage (organization_id, period, sent_count)
  VALUES (p_organization_id, date_trunc('month', now())::DATE, p_count)
  ON CONFLICT (organization_id, period) DO UPDATE
    SET sent_count = public.organization_email_usage.sent_count + EXCLUDED.sent_count,
        updated_at = now();
END $$;

REVOKE ALL ON FUNCTION public.record_email_sent(UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_email_sent(UUID, INT) TO service_role;

-- -----------------------------------------------------------------------------
-- 6) El listado de super-admin suma país, moneda y correos del mes
-- -----------------------------------------------------------------------------
-- DROP y no CREATE OR REPLACE: cambia el tipo de retorno, y Postgres rechaza
-- reemplazar una función cuando cambian las columnas devueltas.
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
  emails_this_month INT
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
                      AND u.period = date_trunc('month', now())::DATE), 0)
    FROM public.organizations o
   ORDER BY o.created_at DESC;
END $$;

REVOKE ALL ON FUNCTION public.superadmin_list_tenants() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.superadmin_list_tenants() TO authenticated;
