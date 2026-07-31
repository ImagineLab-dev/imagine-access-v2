-- El rol por defecto de quien no tiene sesión pasa a ser 'guest'.
--
-- `get_my_role()` caía a 'rrpp' cuando no había nada que leer: sin `auth.uid()`
-- no hay perfil, sin JWT no hay claim, y el COALESCE terminaba en ese literal.
-- O sea que una llamada con la clave anónima y sin iniciar sesión se
-- identificaba como el rol que emite entradas.
--
-- Hoy no era explotable y se verificó: ninguna política RLS usa esta función,
-- el único consumidor es `is_admin()` —que compara contra 'admin' y
-- 'superadmin', así que devolvía falso—, y la app no la llama nunca. Un
-- anónimo era rechazado en todas las escrituras probadas.
--
-- Pero el valor es una trampa esperando: 'rrpp' es un rol con permisos reales,
-- y alcanza con que alguien escriba `IF public.get_my_role() IN ('rrpp', ...)`
-- para autorizar una emisión para que los anónimos entren por esa puerta. El
-- defecto de una función de autorización tiene que ser el rol sin permisos,
-- no uno que los tenga.
--
-- 'guest' es además lo que ya devuelve `userRoleProvider` del lado de la app
-- cuando no hay sesión, así que las dos mitades pasan a hablar el mismo
-- idioma.
--
-- El cambio es inerte para el comportamiento actual: `is_admin()` devolvía
-- falso con 'rrpp' y sigue devolviendo falso con 'guest'.

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT COALESCE(
    (SELECT role FROM public.users_profile WHERE user_id = auth.uid() LIMIT 1),
    NULLIF(auth.jwt() -> 'app_metadata' ->> 'role', ''),
    'guest'
  )
$$;

COMMENT ON FUNCTION public.get_my_role() IS
  'Rol efectivo de quien llama. Sin sesión devuelve ''guest'': el defecto de '
  'una función de autorización nunca debe ser un rol con permisos.';
