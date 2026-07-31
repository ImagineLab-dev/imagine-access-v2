-- `my_subscription` no devolvía la marca de cancelación.
--
-- Sin ella la pantalla no puede distinguir "suscripción corriendo" de
-- "cancelada, con acceso hasta el fin del período pagado". Las dos tienen el
-- mismo `plan` y el mismo `subscription_expires_at`, así que la app mostraría
-- "Se renueva el 17/08" a alguien que ya pidió la baja — y volvería a ofrecerle
-- el botón de pagar como si nada.
--
-- Se agrega la columna al final del RETURNS TABLE: los clientes leen por nombre
-- de columna, así que sumar una al final no rompe a nadie.
--
-- Idempotente: reemplaza la función entera.

-- Hace falta DROP: `CREATE OR REPLACE` no puede cambiar el tipo de retorno de
-- una funcion que devuelve TABLE, porque eso redefine sus parametros OUT.
-- Va todo en una transaccion, asi que no existe un instante en que la funcion
-- falte: o se aplica entero o no se aplica nada.
--
-- Los permisos se reponen abajo. Al borrar la funcion se van con ella, y sin
-- `authenticated` la pantalla de suscripcion dejaria de cargar para todos.
DROP FUNCTION IF EXISTS public.my_subscription();

CREATE FUNCTION public.my_subscription()
RETURNS TABLE(
  organization_id uuid,
  status text,
  plan text,
  currency text,
  country text,
  expires_at timestamp with time zone,
  days_left integer,
  is_active boolean,
  suspended_reason text,
  free_tickets_used integer,
  free_tickets_limit integer,
  free_tickets_left integer,
  cancelled_at timestamp with time zone
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT o.id,
         o.status,
         o.plan,
         o.currency,
         o.country,
         o.subscription_expires_at,
         CASE
           WHEN o.subscription_expires_at IS NULL THEN NULL
           ELSE EXTRACT(DAY FROM (o.subscription_expires_at - now()))::INT
         END,
         (o.status = 'active'
          AND (o.subscription_expires_at IS NULL
               OR o.subscription_expires_at > now())),
         o.suspended_reason,
         o.free_tickets_used,
         o.free_tickets_limit,
         CASE
           WHEN o.plan <> 'trial' OR o.free_tickets_limit IS NULL THEN NULL
           ELSE GREATEST(o.free_tickets_limit - o.free_tickets_used, 0)
         END,
         o.subscription_cancelled_at
    FROM public.organizations o
    JOIN public.users_profile p ON p.organization_id = o.id
   WHERE p.user_id = auth.uid();
$function$;

-- Permisos, tal como estaban antes del DROP.
GRANT EXECUTE ON FUNCTION public.my_subscription() TO anon, authenticated, service_role;

DO $mig$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
     WHERE p.proname = 'my_subscription'
       AND p.pronamespace = 'public'::regnamespace
       AND pg_get_function_result(p.oid) LIKE '%cancelled_at%'
  ) THEN
    RAISE EXCEPTION 'my_subscription no devuelve cancelled_at';
  END IF;
  RAISE NOTICE 'OK: my_subscription ahora informa la cancelacion';
END $mig$;
