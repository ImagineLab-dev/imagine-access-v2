-- El rol de la base y el rol del JWT se habían separado.
--
-- `users_profile.role` decía `superadmin` y `auth.users.raw_app_meta_data->>'role'`
-- decía `admin` para el dueño de la plataforma. La app lee el rol del JWT
-- (auth_controller.dart), así que el router lo mandaba a /dashboard en vez de
-- /super-admin y el panel quedaba inalcanzable — sin ningún mensaje de error,
-- porque desde el punto de vista del cliente el rol era legítimamente `admin`.
--
-- El trigger `sync_profile_to_auth` ya mantiene los dos lados alineados, pero
-- solo dispara cuando `role` u `organization_id` cambian en un UPDATE. Un rol
-- escrito antes de que el trigger existiera —o por cualquier camino que no
-- pasara por ese UPDATE— queda fuera de sincronía para siempre, y el trigger
-- nunca lo va a arreglar solo: `UPDATE ... SET role = role` no lo activa,
-- porque la condición es `IS DISTINCT FROM`.
--
-- Esta migración es el backfill que faltaba. Copia el mismo jsonb que arma el
-- trigger, para que no haya dos definiciones de "qué va en el claim" que puedan
-- divergir con el tiempo.
--
-- Idempotente: solo toca las filas que discrepan, así que correrla dos veces no
-- hace nada la segunda.
--
-- IMPORTANTE: el claim viaja dentro del access token, que ya fue emitido. Quien
-- estuviera con la sesión abierta tiene que salir y volver a entrar, o esperar
-- a que el token se renueve. Actualizar la base no revoca tokens vivos.

DO $$
DECLARE
  v_fila RECORD;
  v_corregidos INT := 0;
BEGIN
  FOR v_fila IN
    SELECT p.user_id,
           p.role,
           p.organization_id,
           o.name AS org_name,
           o.slug AS org_slug,
           u.raw_app_meta_data->>'role' AS rol_viejo
      FROM public.users_profile p
      JOIN auth.users u ON u.id = p.user_id
      LEFT JOIN public.organizations o ON o.id = p.organization_id
     WHERE u.raw_app_meta_data->>'role' IS DISTINCT FROM p.role
        OR (u.raw_app_meta_data->>'organization_id') IS DISTINCT FROM p.organization_id::text
  LOOP
    UPDATE auth.users
       SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object(
             'role',              v_fila.role,
             'organization_id',   v_fila.organization_id,
             'organization_name', COALESCE(v_fila.org_name, ''),
             'organization_slug', COALESCE(v_fila.org_slug, '')
           )
     WHERE id = v_fila.user_id;

    v_corregidos := v_corregidos + 1;
    RAISE NOTICE 'rol resincronizado: % -> % (usuario %)',
      COALESCE(v_fila.rol_viejo, '(sin rol)'), v_fila.role, v_fila.user_id;
  END LOOP;

  IF v_corregidos = 0 THEN
    RAISE NOTICE 'nada que resincronizar: todos los roles ya coinciden';
  ELSE
    RAISE NOTICE '% usuario(s) corregido(s). Tienen que cerrar sesion y volver a entrar.',
      v_corregidos;
  END IF;
END $$;
