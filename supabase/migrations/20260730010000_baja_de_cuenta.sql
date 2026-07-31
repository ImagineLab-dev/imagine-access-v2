-- Baja de cuenta a pedido del titular.
--
-- No existía ninguna forma de que alguien se diera de baja: la única función de
-- borrado, `delete_member_user`, es para que un admin quite a un miembro de su
-- equipo, y lanza "Cannot delete your own account from here". Poder eliminar la
-- propia cuenta no es una comodidad, es el derecho de supresión.
--
-- Esta función hace el borrado del lado de la base y DEVUELVE las cuentas de
-- autenticación a eliminar. Esa última parte la hace la Edge Function con la
-- API de administración, que es el camino soportado y además revoca las sesiones
-- abiertas: borrar filas de `auth.users` a mano dejaría tokens vivos.
--
-- EL ORDEN NO ES ARBITRARIO. Seis tablas impiden borrar una cuenta de
-- autenticación, y cada una necesita un trato distinto según su columna:
--
--   audit_logs.user_id        admite nulo   -> se anula
--   checkins.operator_user    admite nulo   -> se anula
--   events.created_by         admite nulo   -> se anula
--   tickets.created_by        admite nulo   -> se anula
--   users_profile.created_by  admite nulo   -> se anula
--   event_staff.user_id       NOT NULL      -> se BORRA la fila
--
-- Y para borrar la organización primero hay que sacar `devices` y `audit_logs`,
-- que también la bloquean. Sin ese orden, la baja falla con un error de clave
-- foránea que no le dice nada a nadie.
--
-- La atribución de las ventas sobrevive: `tickets.seller_name` guarda el nombre
-- de quien las hizo, así que anular `created_by` no borra de los reportes a
-- quien vendió.
--
-- Idempotente.

CREATE OR REPLACE FUNCTION public.eliminar_mi_cuenta(p_confirmacion TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid        UUID := auth.uid();
  v_rol        TEXT;
  v_org        UUID;
  v_org_nombre TEXT;
  v_soy_dueno  BOOLEAN;
  v_cuentas    UUID[];
  v_resumen    JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NO_AUTENTICADO';
  END IF;

  SELECT p.role, p.organization_id INTO v_rol, v_org
    FROM public.users_profile p WHERE p.user_id = v_uid;

  -- El super-admin no puede borrarse a sí mismo. No es paternalismo: es el único
  -- acceso al panel de la plataforma, y una vez borrado no hay forma de volver a
  -- crearlo desde la aplicación —el guard de perfiles impide otorgar ese rol—.
  -- Habría que entrar a la base a mano.
  IF v_rol = 'superadmin' THEN
    RAISE EXCEPTION 'SUPERADMIN_NO_SE_PUEDE_BORRAR'
      USING HINT = 'Pasá el rol a otra cuenta antes de darte de baja.';
  END IF;

  SELECT o.id, o.name INTO v_org, v_org_nombre
    FROM public.organizations o WHERE o.id = v_org;

  v_soy_dueno := EXISTS (
    SELECT 1 FROM public.organizations o
     WHERE o.id = v_org AND o.owner_id = v_uid
  );

  -- ---------------------------------------------------------------- DUEÑO
  IF v_soy_dueno THEN
    -- Confirmación escrita. Esto borra el trabajo de otras personas —los tickets
    -- que compraron, las entradas que escanearon— así que no alcanza con un
    -- "¿estás seguro?" que se acepta sin leer.
    IF p_confirmacion IS NULL
       OR lower(btrim(p_confirmacion)) IS DISTINCT FROM lower(btrim(v_org_nombre)) THEN
      RAISE EXCEPTION 'CONFIRMACION_INVALIDA'
        USING HINT = 'Escribí el nombre exacto de la organización para confirmar.';
    END IF;

    -- Qué se va a destruir, contado ANTES de destruirlo. Se devuelve para poder
    -- decírselo a la persona y para que quede en el registro de la aplicación.
    SELECT jsonb_build_object(
             'organizacion', v_org_nombre,
             'eventos',   (SELECT count(*) FROM public.events WHERE organization_id = v_org),
             'tickets',   (SELECT count(*) FROM public.tickets t
                             JOIN public.events e ON e.id = t.event_id
                            WHERE e.organization_id = v_org),
             'escaneos',  (SELECT count(*) FROM public.checkins c
                             JOIN public.events e ON e.id = c.event_id
                            WHERE e.organization_id = v_org),
             'miembros',  (SELECT count(*) FROM public.users_profile WHERE organization_id = v_org),
             'dispositivos', (SELECT count(*) FROM public.devices WHERE organization_id = v_org)
           ) INTO v_resumen;

    -- Todas las cuentas de la organización, incluida la propia. Los miembros son
    -- subcuentas creadas por el admin: si se las dejara vivas, en su próximo
    -- ingreso `ensure_profile` les crearía una organización nueva y los haría
    -- admin de ella, gastando un cupo gratuito. Un RRPP se volvería dueño de un
    -- inquilino sin que nadie lo decidiera.
    SELECT array_agg(user_id) INTO v_cuentas
      FROM public.users_profile WHERE organization_id = v_org;

    -- 1) Lo que BLOQUEA borrar la organización.
    DELETE FROM public.devices    WHERE organization_id = v_org;
    DELETE FROM public.audit_logs WHERE organization_id = v_org;

    -- 2) La organización. Arrastra en cascada eventos -> tickets, tipos de
    --    entrada, escaneos y staff; más configuración y consumo de correo.
    DELETE FROM public.organizations WHERE id = v_org;

    -- 3) Los perfiles. Quedaron con organización nula por la cascada.
    DELETE FROM public.users_profile WHERE user_id = ANY(v_cuentas);

  -- ------------------------------------------------------------ NO DUEÑO
  ELSE
    v_cuentas := ARRAY[v_uid];
    v_resumen := jsonb_build_object('organizacion', v_org_nombre, 'solo_mi_cuenta', true);

    -- La organización sigue viva, así que sus datos NO se tocan: solo se sueltan
    -- las referencias a esta persona. Los tickets que vendió se quedan, y su
    -- nombre sobrevive en `seller_name`.
    DELETE FROM public.event_staff WHERE user_id = v_uid;          -- NOT NULL: se borra
    UPDATE public.audit_logs    SET user_id       = NULL WHERE user_id       = v_uid;
    UPDATE public.checkins      SET operator_user = NULL WHERE operator_user = v_uid;
    UPDATE public.events        SET created_by    = NULL WHERE created_by    = v_uid;
    UPDATE public.tickets       SET created_by    = NULL WHERE created_by    = v_uid;
    UPDATE public.users_profile SET created_by    = NULL WHERE created_by    = v_uid;

    DELETE FROM public.users_profile WHERE user_id = v_uid;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'era_dueno', v_soy_dueno,
    'cuentas_a_eliminar', to_jsonb(v_cuentas),
    'resumen', v_resumen
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.eliminar_mi_cuenta(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.eliminar_mi_cuenta(TEXT) TO authenticated;

COMMENT ON FUNCTION public.eliminar_mi_cuenta(TEXT) IS
  'Baja de cuenta a pedido del titular. Si es dueño de la organización, la borra '
  'entera junto con las subcuentas del equipo, y exige el nombre de la '
  'organización como confirmación. Devuelve las cuentas de auth a eliminar: eso '
  'lo hace la Edge Function con la API de administración, que revoca sesiones.';
