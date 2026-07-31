-- El rol `superadmin` nunca se terminó de implementar.
--
-- La migración 20260729140000 arregló `is_admin()` y `get_event_statistics()`.
-- Fueron dos de quince sitios. Los otros trece seguían comparando el rol contra
-- la cadena 'admin' a mano, así que el dueño de la plataforma, en cuanto su rol
-- pasó a ser efectivo, quedó SIN poder:
--
--   get_staff_dashboard      -> ninguna rama coincidía, devolvía
--                               {"my_sales":0,"my_revenue":0} y el panel se
--                               veía en cero, sin error, como si no hubiera datos
--   export_event_full        -> descargar el reporte
--   export_event_tickets     -> exportar los tickets
--   increment_event_quota    -> emitir invitaciones
--   get_authorized_tickets   -> ver los tickets de su organización
--   delete_member_user       -> dar de baja a un miembro
--
-- Esta migración cierra la capa de base de datos. Las Edge Functions se
-- resuelven aparte, en `_shared/roles.ts`, con la misma regla.
--
-- MÉTODO: se sustituye el texto EXACTO del control sobre el cuerpo real que
-- devuelve `pg_get_functiondef`, y se vuelve a crear la función. No se reescribe
-- el cuerpo a mano: son cientos de líneas de consultas y transcribirlas es la
-- forma más fácil de introducir un error nuevo mientras se arregla uno viejo.
--
-- Cada sustitución se VERIFICA. Si un patrón no aparece, la migración aborta en
-- vez de seguir: un `replace` que no encuentra nada devuelve el texto intacto y
-- se ejecuta igual, y ese es exactamente el modo de falla que hace pasar por
-- "arreglado" algo que no se tocó.
--
-- Idempotente: si el reemplazo ya está aplicado, informa y sigue.

-- -----------------------------------------------------------------------------
-- 1) Controles de permiso donde faltaba superadmin
-- -----------------------------------------------------------------------------
DO $mig$
DECLARE
  v            RECORD;
  v_def        TEXT;
  v_nuevo_def  TEXT;
  v_aplicados  INT := 0;
  v_ya         INT := 0;
BEGIN
  FOR v IN
    SELECT * FROM (VALUES
      -- El de los ceros en el panel.
      ('public.get_staff_dashboard(uuid)',
       'IF v_role IN (''admin'', ''door'') THEN',
       'IF v_role IN (''admin'', ''superadmin'', ''door'') THEN'),

      -- Descarga de reportes.
      ('public.export_event_full(uuid)',
       'IF v_role NOT IN (''admin'') THEN',
       'IF v_role NOT IN (''admin'', ''superadmin'') THEN'),
      ('public.export_event_tickets(uuid)',
       'IF v_role NOT IN (''admin'') THEN',
       'IF v_role NOT IN (''admin'', ''superadmin'') THEN'),

      -- Cupo de invitaciones: sin esto no se puede emitir.
      ('public.increment_event_quota(uuid,uuid)',
       'IF v_caller_role IS NULL OR v_caller_role NOT IN (''admin'', ''rrpp'') THEN',
       'IF v_caller_role IS NULL OR v_caller_role NOT IN (''admin'', ''superadmin'', ''rrpp'') THEN'),

      -- Baja de miembros. Se tocan los tres controles:
      --   quién puede borrar, a quién NO se puede borrar, y la restricción de
      --   borrar solo lo que uno creó. El super-admin queda igual que un admin
      --   en los tres, incluida la protección de no poder ser borrado.
      ('public.delete_member_user(uuid)',
       'IF v_caller_role NOT IN (''admin'') THEN',
       'IF v_caller_role NOT IN (''admin'', ''superadmin'') THEN'),
      ('public.delete_member_user(uuid)',
       'IF v_target_role = ''admin'' THEN',
       'IF v_target_role IN (''admin'', ''superadmin'') THEN'),
      ('public.delete_member_user(uuid)',
       'IF v_caller_role = ''admin'' AND v_target_created_by IS DISTINCT FROM auth.uid() THEN',
       'IF v_caller_role IN (''admin'', ''superadmin'') AND v_target_created_by IS DISTINCT FROM auth.uid() THEN')
    ) AS t(firma, viejo, nuevo)
  LOOP
    v_def := pg_get_functiondef(v.firma::regprocedure);

    IF position(v.nuevo IN v_def) > 0 THEN
      v_ya := v_ya + 1;
      RAISE NOTICE 'ya estaba: %  (%)', v.firma, left(v.nuevo, 40);
      CONTINUE;
    END IF;

    IF position(v.viejo IN v_def) = 0 THEN
      RAISE EXCEPTION 'ABORTA: en % no se encontro el patron <%>. El cuerpo cambio; revisar a mano antes de reintentar.',
        v.firma, v.viejo;
    END IF;

    v_nuevo_def := replace(v_def, v.viejo, v.nuevo);
    EXECUTE v_nuevo_def;
    v_aplicados := v_aplicados + 1;
    RAISE NOTICE 'corregida: %  (%)', v.firma, left(v.nuevo, 46);
  END LOOP;

  RAISE NOTICE '--- permisos: % corregidos, % ya estaban ---', v_aplicados, v_ya;
END $mig$;

-- -----------------------------------------------------------------------------
-- 2) get_authorized_tickets: tres sobrecargas, tres listas distintas
-- -----------------------------------------------------------------------------
-- Además de omitir a superadmin, las tres listas de roles eran diferentes entre
-- sí y dos estaban mal:
--
--   (p.role = 'admin'  OR p.role = 'rrpp'  OR p.role = 'door')   <- la correcta
--   (p.role = 'owner'  OR p.role = 'admin' OR p.role = 'door')   <- 'owner' es
--        un rol ELIMINADO por 20260311200000_remove_owner_role: esa condición
--        no puede coincidir con nada, y de paso deja afuera a los rrpp
--   (p.role = 'admin'  OR p.role = 'admin' OR p.role = 'door')   <- 'admin'
--        repetido; el segundo debía ser otro rol y quedó duplicado al copiar
--
-- El cliente llama hoy la sobrecarga (uuid,integer,integer), que es la correcta,
-- así que las otras dos son código muerto. Pero código muerto con una lista de
-- permisos distinta es una trampa: basta que alguien cambie la cantidad de
-- argumentos para que se empiece a ejecutar la equivocada, en silencio.
--
-- Las tres quedan con la MISMA lista.
DO $mig$
DECLARE
  v_firma      TEXT;
  v_def        TEXT;
  v_antes      TEXT;
  v_variante   TEXT;
  v_canonico   TEXT := '(p.role IN (''admin'', ''superadmin'', ''rrpp'', ''door''))';
  v_tocadas    INT := 0;
BEGIN
  FOREACH v_firma IN ARRAY ARRAY[
    'public.get_authorized_tickets()',
    'public.get_authorized_tickets(integer,integer)',
    'public.get_authorized_tickets(uuid,integer,integer)'
  ] LOOP
    v_def   := pg_get_functiondef(v_firma::regprocedure);
    v_antes := v_def;

    FOREACH v_variante IN ARRAY ARRAY[
      '(p.role = ''admin'' OR p.role = ''rrpp'' OR p.role = ''door'')',
      '(p.role = ''owner'' OR p.role = ''admin'' OR p.role = ''door'')',
      '(p.role = ''admin'' OR p.role = ''admin'' OR p.role = ''door'')'
    ] LOOP
      v_def := replace(v_def, v_variante, v_canonico);
    END LOOP;

    IF v_def = v_antes THEN
      IF position(v_canonico IN v_def) > 0 THEN
        RAISE NOTICE 'ya estaba: %', v_firma;
      ELSE
        RAISE EXCEPTION 'ABORTA: en % no se reconocio ninguna lista de roles conocida.', v_firma;
      END IF;
      CONTINUE;
    END IF;

    EXECUTE v_def;
    v_tocadas := v_tocadas + 1;
    RAISE NOTICE 'unificada: %', v_firma;
  END LOOP;

  RAISE NOTICE '--- get_authorized_tickets: % sobrecargas unificadas ---', v_tocadas;
END $mig$;

-- -----------------------------------------------------------------------------
-- 3) Comprobación final
-- -----------------------------------------------------------------------------
-- No alcanza con que la migración no falle: hay que confirmar que no quedó
-- ninguna función decidiendo permisos sin contemplar al super-admin. Las que se
-- listan abajo están revisadas y NO deben cambiar, porque asignan el rol de
-- quien crea su propia organización, y eso es 'admin' a propósito.
DO $mig$
DECLARE
  v_pendientes TEXT;
BEGIN
  SELECT string_agg(firma, ', ' ORDER BY firma) INTO v_pendientes
  FROM (
    SELECT p.oid::regprocedure::text AS firma, pg_get_functiondef(p.oid) AS def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prokind = 'f'
  ) f
  WHERE def LIKE '%admin%'
    AND def NOT LIKE '%superadmin%'
    AND firma NOT IN (
      'auto_create_org_on_profile_insert()',   -- rol del creador de una org nueva
      'create_user_organization(uuid,text,text)', -- idem
      'handle_new_user()',                     -- idem, alta de usuario
      'guard_profile_self_update()'            -- ya usa is_admin(), que los incluye
    );

  IF v_pendientes IS NULL THEN
    RAISE NOTICE 'OK: no queda ninguna funcion de permisos sin superadmin';
  ELSE
    RAISE EXCEPTION 'Quedaron funciones sin superadmin: %', v_pendientes;
  END IF;
END $mig$;
