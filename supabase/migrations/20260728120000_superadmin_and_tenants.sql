-- Super-admin y administración de tenants.
--
-- Introduce un nivel POR ENCIMA de las organizaciones. Hasta ahora los tres
-- roles (admin, rrpp, door) vivían dentro de una: nadie podía ver el conjunto.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) El rol
-- -----------------------------------------------------------------------------
-- El CHECK de users_profile.role no contemplaba 'superadmin'. Se recrea en vez
-- de agregar otro: dos constraints sobre la misma columna se contradicen y el
-- error que sale no dice cuál falló.
DO $$
DECLARE
  nombre TEXT;
BEGIN
  SELECT conname INTO nombre
    FROM pg_constraint
   WHERE conrelid = 'public.users_profile'::regclass
     AND contype = 'c'
     AND pg_get_constraintdef(oid) ILIKE '%role%';

  IF nombre IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.users_profile DROP CONSTRAINT %I', nombre);
  END IF;

  ALTER TABLE public.users_profile
    ADD CONSTRAINT users_profile_role_check
    CHECK (role IN ('admin', 'rrpp', 'door', 'superadmin'));
END $$;

-- -----------------------------------------------------------------------------
-- 2) Estado y suscripción de cada organización
-- -----------------------------------------------------------------------------
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS plan TEXT NOT NULL DEFAULT 'trial',
  ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS suspended_reason TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.organizations'::regclass AND conname = 'organizations_status_check'
  ) THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT organizations_status_check
      CHECK (status IN ('active', 'suspended'));
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3) is_superadmin()
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER y search_path fijo: sin eso, un esquema del usuario podría
-- sombrear users_profile y hacer que la función devuelva true siempre.
CREATE OR REPLACE FUNCTION public.is_superadmin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users_profile
     WHERE user_id = auth.uid() AND role = 'superadmin'
  );
$$;

REVOKE ALL ON FUNCTION public.is_superadmin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_superadmin() TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) Auditoría de accesos a tenants ajenos
-- -----------------------------------------------------------------------------
-- Entrar como un cliente para dar soporte es acceso total a datos ajenos. Sin
-- registro no hay forma de responder "quién vio qué y cuándo", que es
-- exactamente lo que preguntan cuando algo sale mal.
CREATE TABLE IF NOT EXISTS public.superadmin_audit (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_email TEXT,
  action TEXT NOT NULL,
  organization_id UUID,
  organization_name TEXT,
  detail JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS superadmin_audit_created_idx
  ON public.superadmin_audit (created_at DESC);

ALTER TABLE public.superadmin_audit ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Solo lectura, y solo para superadmin. Nadie puede editar ni borrar: un
  -- registro de auditoría que el auditado puede modificar no sirve de nada.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='superadmin_audit' AND policyname='Superadmin reads audit'
  ) THEN
    CREATE POLICY "Superadmin reads audit" ON public.superadmin_audit
      FOR SELECT USING (public.is_superadmin());
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.log_superadmin_action(
  p_action TEXT,
  p_organization_id UUID DEFAULT NULL,
  p_detail JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT;
  v_org   TEXT;
BEGIN
  IF NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'Solo un superadmin puede registrar estas acciones';
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = auth.uid();
  SELECT name  INTO v_org   FROM public.organizations WHERE id = p_organization_id;

  INSERT INTO public.superadmin_audit
    (actor_id, actor_email, action, organization_id, organization_name, detail)
  VALUES
    (auth.uid(), v_email, p_action, p_organization_id, v_org, p_detail);
END $$;

REVOKE ALL ON FUNCTION public.log_superadmin_action(TEXT, UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_superadmin_action(TEXT, UUID, JSONB) TO authenticated;

-- -----------------------------------------------------------------------------
-- 5) Listado de tenants con métricas
-- -----------------------------------------------------------------------------
-- Se resuelve en una sola función y no en consultas del cliente: las policies
-- de organizations filtran por pertenencia, así que un SELECT normal nunca
-- devolvería las demás. Acá el chequeo de superadmin es explícito.
CREATE OR REPLACE FUNCTION public.superadmin_list_tenants()
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
  last_activity TIMESTAMPTZ
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
           WHERE e3.organization_id = o.id)
    FROM public.organizations o
   ORDER BY o.created_at DESC;
END $$;

REVOKE ALL ON FUNCTION public.superadmin_list_tenants() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.superadmin_list_tenants() TO authenticated;

-- -----------------------------------------------------------------------------
-- 6) Suspender, reactivar y ajustar suscripción
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.superadmin_set_status(
  p_organization_id UUID,
  p_status TEXT,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;
  IF p_status NOT IN ('active', 'suspended') THEN
    RAISE EXCEPTION 'Estado inválido: %', p_status;
  END IF;

  UPDATE public.organizations
     SET status = p_status,
         suspended_reason = CASE WHEN p_status = 'suspended' THEN p_reason ELSE NULL END
   WHERE id = p_organization_id;

  PERFORM public.log_superadmin_action(
    'set_status', p_organization_id,
    jsonb_build_object('status', p_status, 'reason', p_reason));
END $$;

CREATE OR REPLACE FUNCTION public.superadmin_set_subscription(
  p_organization_id UUID,
  p_plan TEXT,
  p_expires_at TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  UPDATE public.organizations
     SET plan = p_plan, subscription_expires_at = p_expires_at
   WHERE id = p_organization_id;

  PERFORM public.log_superadmin_action(
    'set_subscription', p_organization_id,
    jsonb_build_object('plan', p_plan, 'expires_at', p_expires_at));
END $$;

REVOKE ALL ON FUNCTION public.superadmin_set_status(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.superadmin_set_status(UUID, TEXT, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.superadmin_set_subscription(UUID, TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.superadmin_set_subscription(UUID, TEXT, TIMESTAMPTZ) TO authenticated;

-- -----------------------------------------------------------------------------
-- 7) Soporte: ver la app como un tenant
-- -----------------------------------------------------------------------------
-- No cambia la identidad ni emite otro token: solo mueve la pertenencia del
-- superadmin a esa organización, y lo deja registrado. Así el resto del sistema
-- —RLS incluido— sigue funcionando sin excepciones especiales, que es donde
-- suelen aparecer los agujeros.
CREATE OR REPLACE FUNCTION public.superadmin_impersonate(p_organization_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  UPDATE public.users_profile
     SET organization_id = p_organization_id
   WHERE user_id = auth.uid();

  PERFORM public.log_superadmin_action('impersonate', p_organization_id, NULL);
END $$;

REVOKE ALL ON FUNCTION public.superadmin_impersonate(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.superadmin_impersonate(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- 8) El superadmin ve todas las organizaciones
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='organizations' AND policyname='Superadmin sees all organizations'
  ) THEN
    CREATE POLICY "Superadmin sees all organizations" ON public.organizations
      FOR SELECT USING (public.is_superadmin());
  END IF;
END $$;
