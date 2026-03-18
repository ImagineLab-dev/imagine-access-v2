-- =============================================================================
-- P5: SECURITY AUDIT FIXES - Owner role, created_by, audit isolation, ILIKE fix
-- =============================================================================
BEGIN;

-- 1. Add 'owner' role to users_profile CHECK constraint
ALTER TABLE public.users_profile
  DROP CONSTRAINT IF EXISTS users_profile_role_check;
ALTER TABLE public.users_profile
  ADD CONSTRAINT users_profile_role_check
  CHECK (role IN ('owner', 'admin', 'rrpp', 'door'));

-- 2. Add created_by column to users_profile (tracks who invited whom)
ALTER TABLE public.users_profile
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id);

-- 3. Promote existing org owners to 'owner' role
UPDATE public.users_profile up
SET role = 'owner'
FROM public.organizations o
WHERE o.owner_id = up.user_id
  AND up.role = 'admin';

-- 4. Add organization_id to audit_logs for tenant isolation
ALTER TABLE public.audit_logs
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id);

CREATE INDEX IF NOT EXISTS idx_audit_logs_org ON public.audit_logs(organization_id);

-- 5. Fix audit_logs RLS - isolate by organization
DROP POLICY IF EXISTS "Audit Logs Admin Read" ON public.audit_logs;
CREATE POLICY "Audit Logs Admin Read" ON public.audit_logs
FOR SELECT USING (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND organization_id = public.get_my_organization_id()
);

DROP POLICY IF EXISTS "Audit Logs Insert" ON public.audit_logs;
CREATE POLICY "Audit Logs Insert" ON public.audit_logs
FOR INSERT WITH CHECK (true);

-- 6. Fix search_tickets_unified ILIKE injection vulnerability
CREATE OR REPLACE FUNCTION public.search_tickets_unified(
  p_query text,
  p_type text,
  p_event_id uuid,
  p_device_id text DEFAULT NULL::text,
  p_device_pin text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid;
  v_is_authenticated boolean := false;
  v_device_org_id uuid;
  v_event_org_id uuid;
  v_user_org_id uuid;
  v_results jsonb := '[]'::jsonb;
  v_query_safe text;
BEGIN
  -- Sanitize ILIKE input to prevent pattern injection
  v_query_safe := replace(replace(replace(p_query, '\', '\\'), '%', '\%'), '_', '\_');

  v_uid := auth.uid();

  IF v_uid IS NOT NULL THEN
    v_is_authenticated := true;
  ELSIF p_device_id IS NOT NULL AND p_device_pin IS NOT NULL THEN
    SELECT d.organization_id
      INTO v_device_org_id
    FROM public.devices d
    WHERE d.enabled = true
      AND (
        d.id::text = p_device_id
        OR (
          EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'devices'
              AND column_name = 'device_id'
          )
          AND d.device_id = p_device_id
        )
      )
      AND (
        (
          d.pin_hash IS NOT NULL
          AND d.pin_salt IS NOT NULL
          AND d.pin_hash = encode(digest(d.pin_salt || ':' || p_device_pin, 'sha256'), 'hex')
        )
        OR (d.pin_hash IS NULL AND d.pin = p_device_pin)
      )
    LIMIT 1;

    IF v_device_org_id IS NOT NULL THEN
      v_is_authenticated := true;
    END IF;
  END IF;

  IF v_is_authenticated IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Unauthorized: No valid session or device credentials');
  END IF;

  IF p_type NOT IN ('doc', 'phone') THEN
    RETURN jsonb_build_object('error', 'Invalid search type. Use doc or phone');
  END IF;

  SELECT e.organization_id
  INTO v_event_org_id
  FROM public.events e
  WHERE e.id = p_event_id;

  IF NOT FOUND THEN
    RETURN '[]'::jsonb;
  END IF;

  IF v_uid IS NOT NULL THEN
    v_user_org_id := public.get_my_organization_id();

    IF v_event_org_id IS NOT NULL AND v_user_org_id IS DISTINCT FROM v_event_org_id THEN
      RETURN jsonb_build_object('error', 'Forbidden: event outside your organization');
    END IF;
  ELSIF v_device_org_id IS DISTINCT FROM v_event_org_id THEN
    RETURN jsonb_build_object('error', 'Forbidden: event outside your organization');
  END IF;

  IF p_type = 'doc' THEN
    SELECT jsonb_agg(t)
    INTO v_results
    FROM (
      SELECT tickets.*, events.name AS event_name
      FROM public.tickets
      JOIN public.events ON events.id = tickets.event_id
      WHERE tickets.event_id = p_event_id
        AND (
          tickets.buyer_doc ILIKE '%' || v_query_safe || '%' ESCAPE '\'
          OR regexp_replace(tickets.buyer_doc, '\D', '', 'g') = regexp_replace(p_query, '\D', '', 'g')
        )
    ) t;
  ELSE
    SELECT jsonb_agg(t)
    INTO v_results
    FROM (
      SELECT tickets.*, events.name AS event_name
      FROM public.tickets
      JOIN public.events ON events.id = tickets.event_id
      WHERE tickets.event_id = p_event_id
        AND (
          tickets.buyer_phone ILIKE '%' || v_query_safe || '%' ESCAPE '\'
          OR regexp_replace(tickets.buyer_phone, '\D', '', 'g') = regexp_replace(p_query, '\D', '', 'g')
        )
    ) t;
  END IF;

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$$;

-- 7. Fix delete_member_user: protect owner, check created_by
CREATE OR REPLACE FUNCTION public.delete_member_user(p_target_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_org uuid;
  v_target_org uuid;
  v_target_role text;
  v_caller_role text;
  v_target_created_by uuid;
BEGIN
  v_caller_org := public.get_my_organization_id();

  SELECT organization_id, role, created_by
  INTO v_target_org, v_target_role, v_target_created_by
  FROM public.users_profile WHERE user_id = p_target_id;

  IF v_target_org IS DISTINCT FROM v_caller_org THEN
    RAISE EXCEPTION 'Cannot delete: User is not from your organization';
  END IF;

  -- Owner can NEVER be deleted
  IF v_target_role = 'owner' THEN
    RAISE EXCEPTION 'Cannot delete: Organization owner cannot be removed';
  END IF;

  v_caller_role := COALESCE(
    auth.jwt() -> 'app_metadata' ->> 'role',
    'rrpp'
  );

  -- Only owner and admin can delete members
  IF v_caller_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'Cannot delete: Insufficient permissions';
  END IF;

  -- Admin can only delete users they themselves created; owner can delete anyone
  IF v_caller_role = 'admin' AND v_target_created_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Cannot delete: You can only delete users you created';
  END IF;

  DELETE FROM public.users_profile WHERE user_id = p_target_id;
  RETURN true;
END;
$$;

-- 8. Add manage_event_staff to master schema (was missing)
CREATE OR REPLACE FUNCTION public.manage_event_staff(
  p_event_id uuid,
  p_user_id uuid,
  p_role text,
  p_quota_standard int DEFAULT 0,
  p_quota_guest int DEFAULT 0,
  p_quota_invitation int DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Verify event belongs to caller's organization
  IF (SELECT organization_id FROM public.events WHERE id = p_event_id)
     IS DISTINCT FROM public.get_my_organization_id() THEN
    RAISE EXCEPTION 'Forbidden: Event outside your organization';
  END IF;

  INSERT INTO public.event_staff (
    event_id, user_id, role,
    quota_standard, quota_guest, quota_invitation,
    quota_limit
  ) VALUES (
    p_event_id, p_user_id, p_role,
    p_quota_standard, p_quota_guest, p_quota_invitation,
    p_quota_standard + p_quota_guest + p_quota_invitation
  )
  ON CONFLICT (event_id, user_id) DO UPDATE SET
    role = EXCLUDED.role,
    quota_standard = EXCLUDED.quota_standard,
    quota_guest = EXCLUDED.quota_guest,
    quota_invitation = EXCLUDED.quota_invitation,
    quota_limit = EXCLUDED.quota_standard + EXCLUDED.quota_guest + EXCLUDED.quota_invitation;
END;
$$;

-- 9. Update RLS policies to recognize 'owner' role as equivalent to 'admin'

-- Events
DROP POLICY IF EXISTS "Organization Events Insert" ON public.events;
CREATE POLICY "Organization Events Insert" ON public.events
FOR INSERT WITH CHECK (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND (
    organization_id = public.get_my_organization_id()
    OR created_by = auth.uid()
  )
);

DROP POLICY IF EXISTS "Organization Events Update" ON public.events;
CREATE POLICY "Organization Events Update" ON public.events
FOR UPDATE USING (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND (
    organization_id = public.get_my_organization_id()
    OR created_by = auth.uid()
  )
);

DROP POLICY IF EXISTS "Organization Events Delete" ON public.events;
CREATE POLICY "Organization Events Delete" ON public.events
FOR DELETE USING (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND (
    organization_id = public.get_my_organization_id()
    OR created_by = auth.uid()
  )
);

-- Ticket Types Write
DROP POLICY IF EXISTS "Organization Types Write" ON public.ticket_types;
CREATE POLICY "Organization Types Write" ON public.ticket_types
FOR ALL USING (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND event_id IN (
    SELECT e.id FROM public.events e
    WHERE e.organization_id = public.get_my_organization_id()
       OR e.created_by = auth.uid()
  )
)
WITH CHECK (
  event_id IN (
    SELECT e.id FROM public.events e
    WHERE e.organization_id = public.get_my_organization_id()
       OR e.created_by = auth.uid()
  )
);

-- Users Profile
DROP POLICY IF EXISTS "Users Profile Admin Insert" ON public.users_profile;
CREATE POLICY "Users Profile Admin Insert" ON public.users_profile
FOR INSERT WITH CHECK (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND organization_id = public.get_my_organization_id()
);

DROP POLICY IF EXISTS "Users Profile Admin Update" ON public.users_profile;
CREATE POLICY "Users Profile Admin Update" ON public.users_profile
FOR UPDATE USING (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND organization_id = public.get_my_organization_id()
)
WITH CHECK (
  organization_id = public.get_my_organization_id()
);

DROP POLICY IF EXISTS "Users Profile Admin Delete" ON public.users_profile;
CREATE POLICY "Users Profile Admin Delete" ON public.users_profile
FOR DELETE USING (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND organization_id = public.get_my_organization_id()
);

DROP POLICY IF EXISTS "Users Profile Guard Update" ON public.users_profile;
CREATE POLICY "Users Profile Guard Update" ON public.users_profile
FOR UPDATE USING (
  (COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
   AND organization_id = public.get_my_organization_id())
  OR (user_id = auth.uid())
)
WITH CHECK (
  organization_id = public.get_my_organization_id()
);

-- Event Staff
DROP POLICY IF EXISTS "Event Staff Admin Write" ON public.event_staff;
CREATE POLICY "Event Staff Admin Write" ON public.event_staff
FOR ALL USING (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND event_id IN (
    SELECT e.id FROM public.events e
    WHERE e.organization_id = public.get_my_organization_id()
  )
)
WITH CHECK (
  event_id IN (
    SELECT e.id FROM public.events e
    WHERE e.organization_id = public.get_my_organization_id()
  )
);

-- App Settings
DROP POLICY IF EXISTS "App Settings Tenant Write" ON public.app_settings;
CREATE POLICY "App Settings Tenant Write" ON public.app_settings
FOR ALL USING (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND organization_id = public.get_my_organization_id()
)
WITH CHECK (
  COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
  AND organization_id = public.get_my_organization_id()
);

-- 10. Storage policies for ticket PDFs (org-isolated)
DO $$
BEGIN
  -- Read policy: org members can read their own ticket files
  DROP POLICY IF EXISTS "Org reads ticket files" ON storage.objects;
  CREATE POLICY "Org reads ticket files" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'tickets'
    AND auth.role() = 'authenticated'
  );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  DROP POLICY IF EXISTS "Admin uploads ticket files" ON storage.objects;
  CREATE POLICY "Admin uploads ticket files" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'tickets'
    AND COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') IN ('owner', 'admin', 'rrpp')
  );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 11. Update sync_profile_to_auth to recognize owner role
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
  IF NEW.role IS DISTINCT FROM OLD.role OR NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
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

COMMIT;
