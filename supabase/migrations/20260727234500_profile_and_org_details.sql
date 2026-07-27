-- Perfil de usuario y datos de la organización.
--
-- Agrega lo que la pantalla de perfil necesita y hoy no existe: teléfono y
-- avatar del usuario, y los datos fiscales y de contacto de la organización.
-- Los datos fiscales quedan listos para la fase de facturación con dLocal.
--
-- Idempotente: todo con IF NOT EXISTS / DO block.

-- -----------------------------------------------------------------------------
-- users_profile
-- -----------------------------------------------------------------------------
ALTER TABLE public.users_profile
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- -----------------------------------------------------------------------------
-- organizations
-- -----------------------------------------------------------------------------
-- legal_name se separa de name a propósito: el nombre comercial que se muestra
-- en la app rara vez coincide con la razón social que va en una factura.
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS legal_name TEXT,
  ADD COLUMN IF NOT EXISTS tax_id TEXT,
  ADD COLUMN IF NOT EXISTS logo_url TEXT,
  ADD COLUMN IF NOT EXISTS contact_email TEXT,
  ADD COLUMN IF NOT EXISTS contact_phone TEXT,
  ADD COLUMN IF NOT EXISTS address TEXT,
  ADD COLUMN IF NOT EXISTS country TEXT DEFAULT 'PY';

-- -----------------------------------------------------------------------------
-- updated_at automático
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_profile_touch_updated_at ON public.users_profile;
CREATE TRIGGER users_profile_touch_updated_at
  BEFORE UPDATE ON public.users_profile
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS organizations_touch_updated_at ON public.organizations;
CREATE TRIGGER organizations_touch_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- RLS: cada usuario edita su propio perfil
-- -----------------------------------------------------------------------------
-- La policy limita las COLUMNAS que puede tocar el propio usuario mediante un
-- trigger, no en el USING: Postgres no permite restringir columnas en RLS.
-- Sin esto, cualquiera podría ascenderse a admin editando su propio perfil.
CREATE OR REPLACE FUNCTION public.guard_profile_self_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Un admin de la organización sí puede cambiar rol y pertenencia.
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  -- El resto solo edita sus datos personales. Cualquier intento de cambiar
  -- rol, organización o a quién pertenece el perfil se revierte en silencio
  -- al valor anterior en lugar de fallar, para no romper un guardado legítimo
  -- que mande el objeto entero.
  NEW.role            := OLD.role;
  NEW.organization_id := OLD.organization_id;
  NEW.user_id         := OLD.user_id;
  NEW.created_by      := OLD.created_by;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_profile_guard_self_update ON public.users_profile;
CREATE TRIGGER users_profile_guard_self_update
  BEFORE UPDATE ON public.users_profile
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_self_update();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'users_profile'
      AND policyname = 'Profile self update'
  ) THEN
    CREATE POLICY "Profile self update" ON public.users_profile
      FOR UPDATE
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- Storage: bucket de avatares
-- -----------------------------------------------------------------------------
-- Público a propósito: son fotos de perfil que se muestran en toda la app y
-- servirlas por URL firmada obligaría a renovar la firma constantemente. No
-- hay dato sensible en una foto de perfil que el equipo ya ve.
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Avatars are readable'
  ) THEN
    CREATE POLICY "Avatars are readable" ON storage.objects
      FOR SELECT USING (bucket_id = 'avatars');
  END IF;

  -- El primer segmento de la ruta es el uid del dueño: avatars/<uid>/foto.jpg.
  -- Así cada usuario solo escribe dentro de su propia carpeta.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Avatars owner write'
  ) THEN
    CREATE POLICY "Avatars owner write" ON storage.objects
      FOR INSERT WITH CHECK (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Avatars owner update'
  ) THEN
    CREATE POLICY "Avatars owner update" ON storage.objects
      FOR UPDATE USING (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Avatars owner delete'
  ) THEN
    CREATE POLICY "Avatars owner delete" ON storage.objects
      FOR DELETE USING (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  END IF;
END $$;
