CREATE OR REPLACE FUNCTION public.sync_profile_to_auth()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_name text;
  v_org_slug text;
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.role IS DISTINCT FROM OLD.role
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    IF NEW.organization_id IS NOT NULL THEN
      SELECT name, slug INTO v_org_name, v_org_slug
      FROM public.organizations WHERE id = NEW.organization_id;
    END IF;
    UPDATE auth.users
    SET raw_app_meta_data =
      raw_app_meta_data ||
      jsonb_build_object(
        'role', NEW.role,
        'organization_id', NEW.organization_id,
        'organization_name', COALESCE(v_org_name, ''),
        'organization_slug', COALESCE(v_org_slug, '')
      )
    WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_profile_updated_sync_auth ON public.users_profile;

CREATE TRIGGER on_profile_updated_sync_auth
AFTER INSERT OR UPDATE OF role, organization_id ON public.users_profile
FOR EACH ROW EXECUTE FUNCTION public.sync_profile_to_auth();
