-- "Volver a mi organización" para el super-admin.
--
-- Impersonar ("Ver como cliente") sobreescribe users_profile.organization_id sin
-- guardar cuál era la propia, así que no hay a dónde volver desde el cliente. La
-- organización propia sí se puede resolver del lado del servidor: es aquella
-- cuyo owner_id es el propio super-admin. Esta función la deja en el perfil y
-- devuelve {id, name, slug} para que el cliente sincronice su contexto (JWT y
-- caché) igual que al impersonar.
--
-- El UPDATE lo permite el guard del perfil porque is_superadmin() lo bypassa, y
-- el trigger sync_profile_to_auth ya escribe la org nueva en el JWT.

CREATE OR REPLACE FUNCTION public.superadmin_return_to_own_org()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org    uuid;
  v_result jsonb;
BEGIN
  IF NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  -- La organización propia: la que el super-admin posee. Si tuviera más de una
  -- (no debería), se toma la más antigua para que el resultado sea estable.
  SELECT id INTO v_org
    FROM public.organizations
   WHERE owner_id = auth.uid()
   ORDER BY created_at
   LIMIT 1;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'No tenés una organización propia a la que volver';
  END IF;

  UPDATE public.users_profile
     SET organization_id = v_org
   WHERE user_id = auth.uid();

  PERFORM public.log_superadmin_action('return_to_own_org', v_org, NULL);

  SELECT jsonb_build_object('id', o.id, 'name', o.name, 'slug', o.slug)
    INTO v_result
    FROM public.organizations o
   WHERE o.id = v_org;

  RETURN v_result;
END;
$$;

-- Solo un usuario autenticado la puede llamar; adentro is_superadmin() es la
-- barrera real. Se le quita a anon por prolijidad (defensa en profundidad).
REVOKE ALL ON FUNCTION public.superadmin_return_to_own_org() FROM anon;
GRANT EXECUTE ON FUNCTION public.superadmin_return_to_own_org() TO authenticated;
