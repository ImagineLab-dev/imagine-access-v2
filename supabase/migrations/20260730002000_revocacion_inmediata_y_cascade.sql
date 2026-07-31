-- Tres arreglos de severidad media de la auditoría del 29/07/2026.
--
-- Idempotente.

-- =============================================================================
-- 1) get_my_role(): la tabla manda sobre el claim del JWT
-- =============================================================================
-- Estaba al revés:
--
--   COALESCE( auth.jwt() -> 'app_metadata' ->> 'role',     <- el claim primero
--             (SELECT role FROM users_profile ...),
--             'rrpp' )
--
-- El claim se sella cuando se emite el token y no cambia hasta que se renueva.
-- Consecuencia: degradar a alguien de admin a rrpp, o sacarlo de la
-- organización, NO tenía efecto sobre las políticas de RLS hasta que su token
-- expirara. La ventana es la vida del access token, una hora por defecto.
--
-- Eso pesa más ahora que antes: los arreglos de hoy apoyan el aislamiento entre
-- inquilinos y el guard de facturación en controles de rol. Una revocación que
-- tarda una hora en aplicarse deja una hora de acceso a alguien a quien ya le
-- sacaste el permiso.
--
-- Invertir el orden hace la revocación inmediata: el rol se lee de la tabla, que
-- es donde se escribe.
--
-- El respaldo al claim se CONSERVA como tercera opción, no por compatibilidad
-- sino por un caso concreto: el instante entre que se crea el usuario de auth y
-- que existe su fila de perfil. Se verificó que hoy no hay ningún usuario sin
-- perfil (2 de 2 lo tienen) y que las sesiones de dispositivo de puerta NO usan
-- esta función: `login_device` no emite JWT, devuelve datos del dispositivo, y
-- por eso `device_dashboard` y `device_events` reciben device_id y PIN en vez de
-- una cabecera Authorization.
--
-- Costo: una lectura a users_profile por evaluación. La función es STABLE, así
-- que dentro de una misma sentencia el resultado se reutiliza.
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(
    (SELECT role FROM public.users_profile WHERE user_id = auth.uid() LIMIT 1),
    NULLIF(auth.jwt() -> 'app_metadata' ->> 'role', ''),
    'rrpp'
  )
$function$;

-- =============================================================================
-- 2) organizations.owner_id: CASCADE -> RESTRICT
-- =============================================================================
-- Era `ON DELETE CASCADE` contra auth.users. Borrar un usuario de auth borraba
-- su organización, y de ahí en cascada: events -> tickets, ticket_types,
-- checkins, event_staff, app_settings y organization_email_usage.
--
-- O sea que un borrado desde el panel de Supabase, o un script de limpieza,
-- destruía un inquilino completo sin una sola confirmación y sin dejar rastro
-- de qué había.
--
-- En la operación normal no debería dispararse nunca: `delete_member_user` ya
-- impide borrar a un admin o super-admin, que son los dueños. Justamente por
-- eso conviene RESTRICT: si algún día se intenta, tiene que fallar de forma
-- ruidosa en vez de funcionar en silencio.
--
-- Para dar de baja un inquilino de verdad, el camino es borrar la organización
-- explícitamente, que sigue haciendo su cascada. Lo que se corta es la vía
-- indirecta y accidental.
DO $mig$
DECLARE
  v_nombre TEXT;
  v_tipo   "char";
BEGIN
  SELECT conname, confdeltype INTO v_nombre, v_tipo
    FROM pg_constraint
   WHERE conrelid = 'public.organizations'::regclass
     AND contype = 'f'
     AND conkey = ARRAY[(SELECT attnum FROM pg_attribute
                          WHERE attrelid = 'public.organizations'::regclass
                            AND attname = 'owner_id')]::smallint[];

  IF v_nombre IS NULL THEN
    RAISE NOTICE 'organizations.owner_id no tiene clave foranea, nada que cambiar';
    RETURN;
  END IF;

  IF v_tipo = 'r' THEN
    RAISE NOTICE 'ya estaba en RESTRICT: %', v_nombre;
    RETURN;
  END IF;

  EXECUTE format('ALTER TABLE public.organizations DROP CONSTRAINT %I', v_nombre);
  EXECUTE format(
    'ALTER TABLE public.organizations ADD CONSTRAINT %I
       FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE RESTRICT',
    v_nombre);
  RAISE NOTICE 'organizations.owner_id: CASCADE -> RESTRICT (%)', v_nombre;
END $mig$;

-- =============================================================================
-- 3) get_authorized_tickets: se van las dos sobrecargas muertas
-- =============================================================================
-- Había tres. El cliente llama solo la de (uuid,integer,integer)
-- —ticket_repository.dart:179 manda p_event_id, p_limit y p_offset— y las otras
-- dos venían de versiones anteriores. Antes de la migración de hoy tenían
-- listas de roles DISTINTAS entre sí: una nombraba el rol 'owner', eliminado por
-- 20260311200000_remove_owner_role, y la otra repetía 'admin' dos veces.
--
-- Hoy las tres dicen lo mismo, así que ya no hay incoherencia. Pero dos copias
-- que nadie llama son una trampa: basta que alguien cambie la cantidad de
-- argumentos en el cliente para que empiece a ejecutarse otra, en silencio, y
-- que vuelva a divergir en el próximo cambio. Se borran.
DROP FUNCTION IF EXISTS public.get_authorized_tickets();
DROP FUNCTION IF EXISTS public.get_authorized_tickets(integer, integer);

-- =============================================================================
-- Comprobación
-- =============================================================================
DO $mig$
DECLARE
  v_def     TEXT;
  v_cascade INT;
  v_sobre   INT;
BEGIN
  -- La tabla tiene que venir ANTES del claim en get_my_role.
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE proname = 'get_my_role' AND pronamespace = 'public'::regnamespace;
  IF position('users_profile' IN v_def) > position('app_metadata' IN v_def) THEN
    RAISE EXCEPTION 'get_my_role sigue leyendo el claim antes que la tabla';
  END IF;

  SELECT count(*) INTO v_cascade FROM pg_constraint
   WHERE conrelid = 'public.organizations'::regclass AND contype = 'f' AND confdeltype = 'c';
  IF v_cascade > 0 THEN
    RAISE EXCEPTION 'organizations sigue teniendo % clave(s) foranea(s) en CASCADE', v_cascade;
  END IF;

  SELECT count(*) INTO v_sobre FROM pg_proc
   WHERE proname = 'get_authorized_tickets' AND pronamespace = 'public'::regnamespace;
  IF v_sobre <> 1 THEN
    RAISE EXCEPTION 'get_authorized_tickets quedo con % versiones, deberia quedar 1', v_sobre;
  END IF;

  RAISE NOTICE 'OK: revocacion inmediata, sin CASCADE en organizations, una sola version de get_authorized_tickets';
END $mig$;
