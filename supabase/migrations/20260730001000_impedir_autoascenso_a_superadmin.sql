-- Un admin común podía convertirse en super-admin de la plataforma.
--
-- `guard_profile_self_update` empezaba con:
--
--     IF public.is_admin() THEN RETURN NEW; END IF;
--
-- Eso deja al admin exento de TODO el guard, incluidas las líneas que revierten
-- `role` y `organization_id`. La intención era permitirle administrar a su
-- equipo, pero también le permitía escribir su propio rol.
--
-- Verificado con pruebas reales como admin común, las tres exitosas:
--
--   A  UPDATE users_profile SET role='superadmin' WHERE user_id = yo
--      -> LOGRADO. Toma de la plataforma: acceso al panel de todos los
--         inquilinos, y además exención del guard de facturación, que exime a
--         is_superadmin() a propósito. O sea que reabría el bypass de cobro que
--         se cerró en la migración anterior.
--
--   B  INSERT organizations (15 tickets gratis) + UPDATE users_profile
--         SET organization_id = <la nueva>
--      -> LOGRADO. El cupo gratuito se recicla de a 15, sin límite. La política
--         `Profile self update` lo permite porque su WITH CHECK solo exige
--         `user_id = auth.uid()`, sin restringir columnas, y las políticas de
--         RLS se combinan con OR.
--
--   C  UPDATE users_profile SET role='superadmin' WHERE user_id = <otro de mi org>
--      -> LOGRADO. Podía ascender a cualquiera de su organización.
--
-- Y una cuarta puerta que el guard no cubría: era BEFORE UPDATE solamente, así
-- que un admin podía INSERTAR una fila con role='superadmin' directamente. La
-- política de INSERT lo permite si la organización es la suya, y
-- `auto_create_org_on_profile_insert` solo pisa el rol cuando la organización
-- viene nula.
--
-- Reglas que quedan:
--
--   1. Solo un super-admin crea un super-admin. Cualquier otro intento aborta.
--   2. Nadie cambia su PROPIO rol ni su PROPIA organización. Cierra el
--      autoascenso y el reciclaje de cupo de una sola vez.
--   3. Un admin sigue administrando el rol y la pertenencia de los DEMÁS
--      miembros de su organización, que es la capacidad legítima. El límite de
--      organización lo pone el WITH CHECK de RLS, que ya estaba bien.
--
-- Exenciones, las mismas de siempre: service_role (Edge Functions),
-- auth.uid() IS NULL (migraciones y consola) y is_superadmin().
--
-- Se verificó que ninguna ruta legítima cambia el rol propio:
-- `create_user_organization` lo hacía, pero es SECURITY DEFINER y NADIE la
-- llama —ni el cliente ni ninguna Edge Function—, y `ensure_profile` entra con
-- service_role, que está exento.
--
-- Idempotente.

CREATE OR REPLACE FUNCTION public.guard_profile_self_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rol_jwt TEXT;
BEGIN
  v_rol_jwt := COALESCE(
    current_setting('request.jwt.claims', true)::json->>'role', '');

  IF v_rol_jwt = 'service_role'
     OR auth.uid() IS NULL
     OR public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  -- --------------------------------------------------------------- Regla 1
  -- Nadie que no sea super-admin puede producir un super-admin, ni creando la
  -- fila ni modificándola. Acá se ABORTA en vez de revertir en silencio: no
  -- existe ningún guardado legítimo que intente esto, así que callarlo sería
  -- esconder un ataque. Un cliente que reenvía el objeto entero de alguien que
  -- YA es super-admin no dispara nada, porque el rol no cambia.
  IF NEW.role = 'superadmin'
     AND (TG_OP = 'INSERT' OR OLD.role IS DISTINCT FROM 'superadmin') THEN
    RAISE EXCEPTION 'FORBIDDEN_SUPERADMIN_GRANT'
      USING HINT = 'Solo un super-admin puede otorgar el rol de super-admin.';
  END IF;

  IF TG_OP = 'INSERT' THEN
    RETURN NEW;
  END IF;

  -- --------------------------------------------------------------- Regla 2
  -- El propio perfil: los datos personales se editan, el rol y la organización
  -- no. Vale también para los admin, que es lo que faltaba.
  IF NEW.user_id = OLD.user_id AND OLD.user_id = auth.uid() THEN
    NEW.role       := OLD.role;
    NEW.created_by := OLD.created_by;

    -- La organización se restaura SALVO que la anterior ya no exista.
    --
    -- `users_profile.organization_id` es ON DELETE SET NULL: al borrar una
    -- organización, la base pone el campo en nulo, y eso llega acá como un
    -- UPDATE. Restaurarlo sin más devolvía el id de la organización recién
    -- borrada y la baja de cuenta fallaba con una violación de clave foránea.
    --
    -- No alcanza con dejar pasar cualquier nulo: soltarse la organización a
    -- voluntad reabre el reciclaje de cupo, porque en el ingreso siguiente
    -- `ensure_profile` crea una organización nueva con sus quince tickets. La
    -- condición distingue las dos cosas: solo se acepta el nulo cuando la
    -- organización anterior REALMENTE desapareció.
    IF NOT (NEW.organization_id IS NULL
            AND OLD.organization_id IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM public.organizations o
                             WHERE o.id = OLD.organization_id)) THEN
      NEW.organization_id := OLD.organization_id;
    END IF;

    RETURN NEW;
  END IF;

  -- --------------------------------------------------------------- Regla 3
  -- Un admin administra a los demás miembros. El WITH CHECK de RLS ya obliga a
  -- que la fila resultante siga siendo de su organización.
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  -- El resto solo edita datos personales. Cualquier intento de cambiar rol,
  -- organización o a quién pertenece el perfil se revierte en silencio al valor
  -- anterior en lugar de fallar, para no romper un guardado legítimo que mande
  -- el objeto entero.
  NEW.role            := OLD.role;
  NEW.organization_id := OLD.organization_id;
  NEW.user_id         := OLD.user_id;
  NEW.created_by      := OLD.created_by;
  RETURN NEW;
END;
$function$;

-- El guard tiene que correr también en INSERT.
DROP TRIGGER IF EXISTS users_profile_guard_self_update ON public.users_profile;
CREATE TRIGGER users_profile_guard_self_update
  BEFORE INSERT OR UPDATE ON public.users_profile
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_self_update();

-- -----------------------------------------------------------------------------
-- Comprobación
-- -----------------------------------------------------------------------------
DO $mig$
DECLARE
  v_eventos TEXT;
BEGIN
  SELECT CASE WHEN (t.tgtype & 4) > 0 THEN 'INSERT ' ELSE '' END ||
         CASE WHEN (t.tgtype & 16) > 0 THEN 'UPDATE' ELSE '' END
    INTO v_eventos
    FROM pg_trigger t
   WHERE t.tgrelid = 'public.users_profile'::regclass
     AND t.tgname = 'users_profile_guard_self_update';

  IF v_eventos IS DISTINCT FROM 'INSERT UPDATE' THEN
    RAISE EXCEPTION 'El guard de perfiles quedo en: %', COALESCE(v_eventos, '(no existe)');
  END IF;

  RAISE NOTICE 'OK: guard de perfiles cubre INSERT y UPDATE';
END $mig$;
