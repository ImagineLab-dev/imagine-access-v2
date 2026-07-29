-- El superadmin no podía hacer lo que puede un admin.
--
-- El rol `superadmin` se agregó después que el resto del sistema de permisos, y
-- los controles que ya existían nunca lo contemplaron:
--
--   is_admin()             -> SELECT get_my_role() = 'admin'   (falso para superadmin)
--   get_event_statistics() -> IF v_role NOT IN ('admin') THEN RAISE
--
-- Efecto real: el dueño de la plataforma, entrando a su propia organización,
-- tenía MENOS permisos que un admin común. No veía las estadísticas de sus
-- eventos, y como el cliente atrapa el error y devuelve un mapa vacío, la
-- pantalla mostraba ceros sin decir que había fallado.
--
-- El mensaje de esa excepción además decía "Owner or Admin" mientras la
-- condición solo aceptaba 'admin': el dueño de una organización cuyo perfil no
-- fuera exactamente 'admin' quedaba afuera igual, contradiciendo el texto.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) is_admin() incluye a superadmin
-- -----------------------------------------------------------------------------
-- Se usa en varias policies de RLS, así que este cambio ensancha el acceso del
-- superadmin de forma consistente en todas ellas a la vez — que es lo correcto:
-- quien administra la plataforma debe poder al menos lo mismo que un admin.
--
-- No abre nada a otros roles: 'rrpp' y 'door' siguen dando falso.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT public.get_my_role() IN ('admin', 'superadmin')
$function$;

-- -----------------------------------------------------------------------------
-- 2) Estadísticas del evento
-- -----------------------------------------------------------------------------
-- Se recrea solo la comprobación de rol; el resto del cuerpo se conserva tal
-- como estaba, incluido el guard multi-tenant que ya funcionaba bien.
DO $$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'get_event_statistics';

  IF v_def IS NULL THEN
    RAISE NOTICE 'get_event_statistics no existe, nada que ajustar';
    RETURN;
  END IF;

  -- Sustitución quirúrgica: solo la lista de roles aceptados.
  v_def := replace(
    v_def,
    'IF v_role NOT IN (''admin'') THEN',
    'IF v_role NOT IN (''admin'', ''superadmin'') THEN'
  );

  EXECUTE v_def;
  RAISE NOTICE 'get_event_statistics: superadmin habilitado';
END $$;
