-- Los dos guards reventaban si `request.jwt.claims` era cadena vacía.
--
-- Los dos empiezan igual:
--
--     v_rol := COALESCE(current_setting('request.jwt.claims', true)::json->>'role', '');
--
-- `current_setting(..., true)` devuelve NULL cuando la variable NO EXISTE, y en
-- ese caso `NULL::json` es NULL y todo sigue. Pero si la variable existe con el
-- valor '' —lo que ocurre, por ejemplo, después de que una transacción anterior
-- la haya fijado con SET LOCAL y se haya revertido— entonces `''::json` lanza:
--
--     invalid input syntax for type json
--     DETAIL: The input string ended unexpectedly.
--
-- Y como los dos guards son BEFORE INSERT OR UPDATE sobre `organizations` y
-- `users_profile`, esa excepción tumba CUALQUIER escritura sobre esas tablas.
-- No es un caso de laboratorio: apareció probando la baja de cuenta, en una
-- sentencia normal ejecutada sin sesión de PostgREST.
--
-- El arreglo es descartar la cadena vacía antes de convertir. Se agrega además
-- un respaldo por si el valor existe pero no es JSON válido: un guard de
-- seguridad que se cae por el formato de una variable de entorno es un guard que
-- bloquea el producto entero.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) Función auxiliar: el rol del JWT, sin reventar nunca
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rol_del_claim()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_crudo TEXT;
BEGIN
  v_crudo := NULLIF(current_setting('request.jwt.claims', true), '');
  IF v_crudo IS NULL THEN
    RETURN '';
  END IF;
  RETURN COALESCE(v_crudo::json->>'role', '');
EXCEPTION WHEN others THEN
  -- Valor presente pero ilegible. Devolver vacío es lo seguro: significa "no
  -- es service_role", así que los guards aplican en vez de saltarse.
  RETURN '';
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2) Los dos guards la usan
-- -----------------------------------------------------------------------------
DO $mig$
DECLARE
  v RECORD;
  v_def TEXT;
  v_viejo TEXT := 'COALESCE(
    current_setting(''request.jwt.claims'', true)::json->>''role'', '''')';
  v_cambiados INT := 0;
BEGIN
  FOR v IN SELECT unnest(ARRAY['guard_profile_self_update', 'guard_billing_columns']) AS nombre
  LOOP
    v_def := pg_get_functiondef(
      (SELECT oid FROM pg_proc WHERE proname = v.nombre
        AND pronamespace = 'public'::regnamespace LIMIT 1));

    IF v_def LIKE '%public.rol_del_claim()%' THEN
      RAISE NOTICE 'ya usaba rol_del_claim: %', v.nombre;
      CONTINUE;
    END IF;

    IF position(v_viejo IN v_def) = 0 THEN
      RAISE EXCEPTION 'ABORTA: no se encontro el patron del claim en %', v.nombre;
    END IF;

    EXECUTE replace(v_def, v_viejo, 'public.rol_del_claim()');
    v_cambiados := v_cambiados + 1;
    RAISE NOTICE 'corregida: %', v.nombre;
  END LOOP;

  RAISE NOTICE '--- % guard(s) ahora toleran claims vacios ---', v_cambiados;
END $mig$;

-- -----------------------------------------------------------------------------
-- 3) Comprobación: con la variable en vacío, escribir no debe fallar
-- -----------------------------------------------------------------------------
DO $mig$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);

  IF public.rol_del_claim() <> '' THEN
    RAISE EXCEPTION 'rol_del_claim no devolvio vacio con claims vacios';
  END IF;

  -- Una escritura real sobre cada tabla guardada, revertida enseguida.
  UPDATE public.organizations SET updated_at = updated_at WHERE false;
  UPDATE public.users_profile SET updated_at = updated_at WHERE false;

  RAISE NOTICE 'OK: con request.jwt.claims vacio, los guards no revientan';
END $mig$;
