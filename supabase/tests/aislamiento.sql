-- Pruebas de regresión del aislamiento multi-tenant y las defensas de la base.
--
-- QUÉ ASEGURA
--
-- Las invariantes que la auditoría del 07/08/2026 verificó a mano. Si alguna se
-- cae —un trigger que alguien droppea, una policy que se afloja, un GRANT que
-- vuelve por la deriva de Supabase— este script FALLA con una excepción que
-- nombra la invariante rota. Es la red que convierte "lo verifiqué una vez" en
-- "se verifica cada vez que se corre".
--
-- CÓMO SE CORRE
--
--   ssh imaginelab 'docker exec -i supabase-db psql -U supabase_admin -d postgres' < supabase/tests/aislamiento.sql
--
-- Es SEGURO contra producción: cada prueba vive en su propia transacción que
-- termina en ROLLBACK. No hace falta un entorno de test; de hecho corre mejor
-- contra datos reales, porque descubre sus propios fixtures (dos admins de
-- organizaciones distintas) en vez de inventarlos.
--
-- supabase_admin es superusuario y SALTA RLS, por eso cada prueba baja a
-- `authenticated` o `anon` con SET LOCAL ROLE: así RLS se aplica como para un
-- cliente real.

\set ON_ERROR_STOP on
\pset pager off

-- ---------------------------------------------------------------------------
-- Fixtures: dos admins de organizaciones DISTINTAS, y una org víctima.
-- Se descubren de la base para que el script no dependa de IDs hardcodeados.
-- ---------------------------------------------------------------------------
SELECT user_id AS atacante_uid, organization_id AS atacante_org
FROM public.users_profile WHERE role = 'admin' ORDER BY created_at LIMIT 1
\gset
SELECT p.user_id AS victima_uid, p.organization_id AS victima_org
FROM public.users_profile p WHERE p.role = 'admin'
  AND p.organization_id <> :'atacante_org' ORDER BY p.created_at LIMIT 1
\gset
SELECT id AS victima_evento FROM public.events
WHERE organization_id = :'victima_org' LIMIT 1
\gset

-- Los `\gset` de arriba son variables del cliente psql; los bloques DO corren en
-- el servidor y no las ven. Se copian a GUCs de sesión (el `false` = alcance de
-- sesión, sobreviven al ROLLBACK de cada prueba) para poder leerlas con
-- current_setting() dentro de los DO.
SELECT set_config('test.atacante_uid',    :'atacante_uid',    false);
SELECT set_config('test.victima_org',     :'victima_org',     false);
SELECT set_config('test.victima_evento',  :'victima_evento',  false);

\echo '=== fixtures ==='
\echo '  atacante_org:' :atacante_org
\echo '  victima_org: ' :victima_org

-- ---------------------------------------------------------------------------
-- 1. Un admin NO puede leer datos de otra organización.
-- ---------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'atacante_uid', 'role', 'authenticated')::text, true);
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.events
  WHERE organization_id = current_setting('test.victima_org', true)::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'FUGA: un admin ve % eventos de otra organizacion', n; END IF;
END $$;
ROLLBACK;

-- ---------------------------------------------------------------------------
-- 2. Un admin NO puede escribir en otra organización.
-- ---------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'atacante_uid', 'role', 'authenticated')::text, true);
DO $$
DECLARE n int;
BEGIN
  UPDATE public.events SET name = 'REGRESION_HACK'
  WHERE id = current_setting('test.victima_evento', true)::uuid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FUGA: un admin edito % evento(s) ajeno(s)', n; END IF;
END $$;
ROLLBACK;

-- ---------------------------------------------------------------------------
-- 3. Un admin NO puede auto-escalar a superadmin (trigger guard_profile_self_update).
--    Esta es la prueba que la auditoria pidio: falla si el trigger se cae.
-- ---------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'atacante_uid', 'role', 'authenticated')::text, true);
DO $$
DECLARE bloqueado boolean := false; rol_final text;
BEGIN
  BEGIN
    UPDATE public.users_profile SET role = 'superadmin'
    WHERE user_id = current_setting('test.atacante_uid', true)::uuid;
    SELECT role INTO rol_final FROM public.users_profile
    WHERE user_id = current_setting('test.atacante_uid', true)::uuid;
  EXCEPTION WHEN OTHERS THEN
    bloqueado := true;  -- el trigger aborto con excepcion, perfecto
  END;
  -- Aceptable de dos formas: o el trigger aborta, o fuerza role=OLD.role y el
  -- valor final NO es superadmin. Lo que NO se acepta es que quede en superadmin.
  IF NOT bloqueado AND rol_final = 'superadmin' THEN
    RAISE EXCEPTION 'ESCALADA: un admin logro ponerse role=superadmin';
  END IF;
END $$;
ROLLBACK;

-- ---------------------------------------------------------------------------
-- 4. Un claim de JWT forjado con role=superadmin NO engaña a is_superadmin().
-- ---------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'atacante_uid', 'role', 'superadmin', 'user_role', 'superadmin')::text, true);
DO $$
BEGIN
  IF public.is_superadmin() THEN
    RAISE EXCEPTION 'ESCALADA: is_superadmin() creyo un claim forjado';
  END IF;
END $$;
ROLLBACK;

-- ---------------------------------------------------------------------------
-- 5. anon NO puede llamar las funciones de facturación (el agujero del 07/08).
-- ---------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
DO $$
DECLARE llego boolean := false;
BEGIN
  BEGIN
    PERFORM public.apply_subscription_payment(
      current_setting('test.victima_org', true)::uuid, 'annual', 0, 'USD', NULL, '{}'::jsonb, 'regresion');
    llego := true;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;  -- permission denied, correcto
  END;
  IF llego THEN RAISE EXCEPTION 'FUGA: anon pudo ejecutar apply_subscription_payment'; END IF;
END $$;
ROLLBACK;

-- ---------------------------------------------------------------------------
-- 6. Debe haber exactamente UN superadmin.
-- ---------------------------------------------------------------------------
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.users_profile WHERE role = 'superadmin';
  IF n <> 1 THEN RAISE EXCEPTION 'Hay % superadmins, deberia haber exactamente 1', n; END IF;
END $$;

\echo ''
\echo '=== TODAS LAS INVARIANTES PASARON ==='
