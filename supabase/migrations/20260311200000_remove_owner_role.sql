-- ============================================================================
-- MIGRATION: Remove 'owner' as a role value
-- Owner concept now lives ONLY in organizations.owner_id
-- All users who had role='owner' become role='admin'
-- ============================================================================

-- 1. Migrate existing data FIRST (before constraints change)
UPDATE public.users_profile SET role = 'admin' WHERE role = 'owner';
UPDATE public.event_staff SET role = 'admin' WHERE role = 'owner';

-- 2. Sync JWT metadata for affected users
UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('role', 'admin')
WHERE raw_app_meta_data ->> 'role' = 'owner';

-- 3. Update CHECK constraints
ALTER TABLE public.users_profile DROP CONSTRAINT IF EXISTS users_profile_role_check;
ALTER TABLE public.users_profile ADD CONSTRAINT users_profile_role_check
  CHECK (role IN ('admin', 'rrpp', 'door'));

ALTER TABLE public.event_staff DROP CONSTRAINT IF EXISTS event_staff_role_check;
ALTER TABLE public.event_staff ADD CONSTRAINT event_staff_role_check
  CHECK (role IN ('admin', 'rrpp', 'door'));

-- 4. Add UNIQUE constraint on device alias per organization
CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_org_alias
  ON public.devices(organization_id, alias) WHERE alias IS NOT NULL;

-- 5. Update is_admin() to only check 'admin'
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.get_my_role() = 'admin'
$$;

-- 6. Update delete_member_user to check organizations.owner_id
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

  IF EXISTS (SELECT 1 FROM public.organizations WHERE owner_id = p_target_id AND id = v_caller_org) THEN
    RAISE EXCEPTION 'Cannot delete: Organization owner cannot be removed';
  END IF;

  v_caller_role := COALESCE(
    NULLIF(auth.jwt() -> 'app_metadata' ->> 'role', ''),
    (SELECT role FROM public.users_profile WHERE user_id = auth.uid()),
    'rrpp'
  );

  IF v_caller_role NOT IN ('admin') THEN
    RAISE EXCEPTION 'Cannot delete: Insufficient permissions';
  END IF;

  IF v_caller_role = 'admin' AND v_target_created_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Cannot delete: You can only delete users you created';
  END IF;

  DELETE FROM public.users_profile WHERE user_id = p_target_id;
  RETURN true;
END;
$$;

-- 7. Update create_user_organization to assign 'admin' instead of 'owner'
CREATE OR REPLACE FUNCTION public.create_user_organization(
  p_user_id UUID,
  p_display_name TEXT,
  p_email TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_id UUID;
  v_org_slug TEXT;
BEGIN
  v_org_slug := lower(regexp_replace(
    COALESCE(p_display_name, split_part(p_email, '@', 1)),
    '[^a-zA-Z0-9]+', '-', 'g'
  )) || '-' || substr(md5(random()::text), 1, 6);

  INSERT INTO public.organizations (name, slug, owner_id)
  VALUES (
    COALESCE(p_display_name, split_part(p_email, '@', 1)) || ' Organization',
    v_org_slug,
    p_user_id
  )
  RETURNING id INTO v_org_id;

  UPDATE public.users_profile
  SET organization_id = v_org_id, role = 'admin'
  WHERE user_id = p_user_id;

  RETURN v_org_id;
END;
$$;

-- 8. Update auto_create_org trigger to assign 'admin'
CREATE OR REPLACE FUNCTION public.auto_create_org_on_profile_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_id UUID;
  v_display TEXT;
  v_slug TEXT;
BEGIN
  IF TG_OP = 'INSERT' AND NEW.organization_id IS NULL THEN
    v_display := COALESCE(NEW.display_name, 'User');
    v_slug := lower(regexp_replace(v_display, '[^a-zA-Z0-9]+', '-', 'g'))
              || '-' || substr(md5(random()::text), 1, 6);

    INSERT INTO public.organizations (name, slug, owner_id)
    VALUES (v_display || ' Organization', v_slug, NEW.user_id)
    RETURNING id INTO v_org_id;

    NEW.organization_id := v_org_id;
    NEW.role := 'admin';
  END IF;

  RETURN NEW;
END;
$$;

-- 9. Update handle_new_user trigger to assign 'admin'
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_display TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users_profile WHERE user_id = NEW.id) THEN
    v_display := COALESCE(
      NEW.raw_user_meta_data ->> 'display_name',
      split_part(NEW.email, '@', 1),
      'User'
    );

    INSERT INTO public.users_profile (user_id, display_name, role)
    VALUES (NEW.id, v_display, 'admin')
    ON CONFLICT (user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- 10. Update RLS policies to use is_admin()
DROP POLICY IF EXISTS "Organization Events Insert" ON public.events;
CREATE POLICY "Organization Events Insert" ON public.events
FOR INSERT WITH CHECK (
  public.is_admin()
  AND (organization_id = public.get_my_organization_id() OR created_by = auth.uid())
);

DROP POLICY IF EXISTS "Organization Events Update" ON public.events;
CREATE POLICY "Organization Events Update" ON public.events
FOR UPDATE USING (
  public.is_admin()
  AND (organization_id = public.get_my_organization_id() OR created_by = auth.uid())
);

DROP POLICY IF EXISTS "Organization Events Delete" ON public.events;
CREATE POLICY "Organization Events Delete" ON public.events
FOR DELETE USING (
  public.is_admin()
  AND (organization_id = public.get_my_organization_id() OR created_by = auth.uid())
);

DROP POLICY IF EXISTS "Organization Types Write" ON public.ticket_types;
CREATE POLICY "Organization Types Write" ON public.ticket_types
FOR ALL USING (
  public.is_admin()
  AND event_id IN (
    SELECT e.id FROM public.events e
    WHERE e.organization_id = public.get_my_organization_id() OR e.created_by = auth.uid()
  )
)
WITH CHECK (
  event_id IN (
    SELECT e.id FROM public.events e
    WHERE e.organization_id = public.get_my_organization_id() OR e.created_by = auth.uid()
  )
);

DROP POLICY IF EXISTS "Users Profile Admin Insert" ON public.users_profile;
CREATE POLICY "Users Profile Admin Insert" ON public.users_profile
FOR INSERT WITH CHECK (
  public.is_admin()
  AND organization_id = public.get_my_organization_id()
);

DROP POLICY IF EXISTS "Users Profile Admin Update" ON public.users_profile;
CREATE POLICY "Users Profile Admin Update" ON public.users_profile
FOR UPDATE USING (
  public.is_admin()
  AND organization_id = public.get_my_organization_id()
)
WITH CHECK (organization_id = public.get_my_organization_id());

DROP POLICY IF EXISTS "Users Profile Admin Delete" ON public.users_profile;
CREATE POLICY "Users Profile Admin Delete" ON public.users_profile
FOR DELETE USING (
  public.is_admin()
  AND organization_id = public.get_my_organization_id()
);

DROP POLICY IF EXISTS "Users Profile Guard Update" ON public.users_profile;
CREATE POLICY "Users Profile Guard Update" ON public.users_profile
FOR UPDATE USING (
  (public.is_admin() AND organization_id = public.get_my_organization_id())
  OR (user_id = auth.uid())
)
WITH CHECK (organization_id = public.get_my_organization_id());

DROP POLICY IF EXISTS "Event Staff Read" ON public.event_staff;
CREATE POLICY "Event Staff Read" ON public.event_staff
FOR SELECT USING (
  user_id = auth.uid()
  OR (
    public.is_admin()
    AND event_id IN (
      SELECT e.id FROM public.events e WHERE e.organization_id = public.get_my_organization_id()
    )
  )
);

DROP POLICY IF EXISTS "Event Staff Admin Write" ON public.event_staff;
CREATE POLICY "Event Staff Admin Write" ON public.event_staff
FOR ALL USING (
  public.is_admin()
  AND event_id IN (
    SELECT e.id FROM public.events e WHERE e.organization_id = public.get_my_organization_id()
  )
)
WITH CHECK (
  event_id IN (
    SELECT e.id FROM public.events e WHERE e.organization_id = public.get_my_organization_id()
  )
);

DROP POLICY IF EXISTS "App Settings Tenant Write" ON public.app_settings;
CREATE POLICY "App Settings Tenant Write" ON public.app_settings
FOR ALL USING (
  public.is_admin()
  AND organization_id = public.get_my_organization_id()
)
WITH CHECK (
  public.is_admin()
  AND organization_id = public.get_my_organization_id()
);

DROP POLICY IF EXISTS "Audit Logs Admin Read" ON public.audit_logs;
CREATE POLICY "Audit Logs Admin Read" ON public.audit_logs
FOR SELECT USING (
  public.is_admin()
  AND organization_id = public.get_my_organization_id()
);

-- 11. Update RPCs that referenced 'owner'
CREATE OR REPLACE FUNCTION public.increment_event_quota(p_event_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit int;
  v_used int;
  v_caller_role text;
  v_event_org_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no authenticated session';
  END IF;

  v_caller_role := COALESCE(
    NULLIF(auth.jwt() -> 'app_metadata' ->> 'role', ''),
    (SELECT role FROM public.users_profile WHERE user_id = auth.uid())
  );

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'rrpp') THEN
    RAISE EXCEPTION 'Forbidden: insufficient permissions to increment quotas';
  END IF;

  SELECT organization_id INTO v_event_org_id FROM public.events WHERE id = p_event_id;
  IF v_event_org_id IS DISTINCT FROM public.get_my_organization_id() THEN
    RAISE EXCEPTION 'Forbidden: event does not belong to your organization';
  END IF;

  SELECT quota_limit, quota_used INTO v_limit, v_used
  FROM public.event_staff
  WHERE event_id = p_event_id AND user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN RETURN false; END IF;
  IF COALESCE(v_used, 0) >= COALESCE(v_limit, 0) THEN RETURN false; END IF;

  UPDATE public.event_staff
  SET quota_used = COALESCE(quota_used, 0) + 1
  WHERE event_id = p_event_id AND user_id = p_user_id;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_authorized_tickets(
  p_limit int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid;
  v_results jsonb;
  v_my_org uuid;
BEGIN
  v_uid := auth.uid();
  v_my_org := public.get_my_organization_id();

  SELECT jsonb_agg(sub.ticket_json) INTO v_results
  FROM (
    SELECT
      to_jsonb(t)
      || jsonb_build_object(
        'events', jsonb_build_object('name', e.name),
        'users_profile', CASE WHEN up.user_id IS NOT NULL THEN jsonb_build_object('display_name', up.display_name) ELSE NULL END,
        'checkins', COALESCE((
          SELECT jsonb_agg(jsonb_build_object('id', c.id))
          FROM public.checkins c WHERE c.ticket_id = t.id
        ), '[]'::jsonb)
      ) AS ticket_json
    FROM public.tickets t
    LEFT JOIN public.events e ON t.event_id = e.id
    LEFT JOIN public.users_profile up ON t.created_by = up.user_id
    WHERE
      e.organization_id = v_my_org
      AND (
        EXISTS (
          SELECT 1 FROM public.users_profile p
          WHERE p.user_id = v_uid AND p.role IN ('admin', 'door')
        )
        OR t.event_id IN (SELECT es.event_id FROM public.event_staff es WHERE es.user_id = v_uid)
        OR t.created_by = v_uid
      )
    ORDER BY t.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) sub;

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_staff_dashboard(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text;
  v_uid uuid;
  v_result jsonb;
BEGIN
  IF (SELECT organization_id FROM public.events WHERE id = p_event_id)
     IS DISTINCT FROM public.get_my_organization_id() THEN
    RAISE EXCEPTION 'Forbidden: You do not have access to this event dashboard';
  END IF;

  v_uid := auth.uid();
  v_role := COALESCE(
    NULLIF(auth.jwt() -> 'app_metadata' ->> 'role', ''),
    (SELECT role FROM public.users_profile WHERE user_id = auth.uid()),
    'rrpp'
  );

  IF v_role IN ('admin', 'door') THEN
    v_result := jsonb_build_object(
      'total_sold', (SELECT COUNT(*) FROM public.tickets WHERE event_id = p_event_id),
      'scanned', (SELECT COUNT(DISTINCT ticket_id) FROM public.checkins WHERE event_id = p_event_id AND result = 'allowed'),
      'scanned_manual', (SELECT COUNT(DISTINCT ticket_id) FROM public.checkins WHERE event_id = p_event_id AND result = 'allowed' AND method <> 'qr'),
      'valid', (
        SELECT COUNT(*) FROM public.tickets
        WHERE event_id = p_event_id
          AND (status IS NULL OR LOWER(status) = 'valid')
          AND id NOT IN (SELECT c.ticket_id FROM public.checkins c WHERE c.event_id = p_event_id AND c.result = 'allowed')
      ),
      'revenue', (SELECT COALESCE(SUM(price), 0) FROM public.tickets WHERE event_id = p_event_id),
      'standard_created', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'standard'),
      'standard_entered', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'standard' AND c.result = 'allowed'),
      'staff_created', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'staff'),
      'staff_entered', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'staff' AND c.result = 'allowed'),
      'guest_created', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'guest'),
      'guest_entered', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'guest' AND c.result = 'allowed'),
      'invitations_total', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'invitation'),
      'invitations_scanned', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'invitation' AND c.result = 'allowed')
    );
  ELSIF v_role = 'rrpp' THEN
    v_result := (
      SELECT jsonb_build_object(
        'paid_tickets_count', (SELECT COUNT(*) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND t.created_by = v_uid AND t.price > 0),
        'paid_tickets_today', (SELECT COUNT(*) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND t.created_by = v_uid AND t.price > 0 AND t.created_at >= CURRENT_DATE),
        'total_issued', (SELECT COUNT(*) FROM public.tickets WHERE event_id = p_event_id AND created_by = v_uid),
        'invitations_count', (SELECT COUNT(*) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND t.created_by = v_uid AND t.price = 0),
        'quota_standard', es.quota_standard,
        'quota_standard_used', es.quota_standard_used,
        'remaining_standard', (es.quota_standard - es.quota_standard_used),
        'quota_guest', es.quota_guest,
        'quota_guest_used', es.quota_guest_used,
        'remaining_guest', (es.quota_guest - es.quota_guest_used),
        'total_scanned', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND t.created_by = v_uid AND c.result = 'allowed'),
        'my_revenue', (SELECT COALESCE(SUM(price), 0) FROM public.tickets WHERE event_id = p_event_id AND created_by = v_uid)
      )
      FROM public.event_staff es
      WHERE es.event_id = p_event_id AND es.user_id = v_uid
    );
  END IF;

  RETURN COALESCE(v_result, '{"my_sales":0, "my_revenue":0}'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_event_statistics(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text;
  v_stats jsonb;
BEGIN
  IF (SELECT organization_id FROM public.events WHERE id = p_event_id)
     IS DISTINCT FROM public.get_my_organization_id() THEN
    RAISE EXCEPTION 'Forbidden: You do not have access to this event statistics';
  END IF;

  v_role := COALESCE(
    NULLIF(auth.jwt() -> 'app_metadata' ->> 'role', ''),
    (SELECT role FROM public.users_profile WHERE user_id = auth.uid()),
    'rrpp'
  );

  IF v_role NOT IN ('admin') THEN
    RAISE EXCEPTION 'Unauthorized: Statistics only available for Admin role';
  END IF;

  SELECT jsonb_build_object(
    'attendance_by_hour', (
      SELECT jsonb_agg(h) FROM (
        SELECT to_char(date_trunc('hour', scanned_at), 'HH24:00') AS hour, count(*) AS count
        FROM public.checkins WHERE event_id = p_event_id AND result = 'allowed'
        GROUP BY 1 ORDER BY 1
      ) h
    ),
    'rrpp_performance', (
      SELECT jsonb_agg(p) FROM (
        SELECT COALESCE(up.display_name, u.email) AS name, t.type, count(*) AS count
        FROM public.tickets t
        LEFT JOIN auth.users u ON t.created_by = u.id
        LEFT JOIN public.users_profile up ON u.id = up.user_id
        WHERE t.event_id = p_event_id
        GROUP BY 1, 2 ORDER BY 3 DESC
      ) p
    ),
    'sales_timeline', (
      SELECT jsonb_agg(s) FROM (
        SELECT created_at::date AS day, count(*) AS count, sum(price) AS revenue
        FROM public.tickets WHERE event_id = p_event_id
        GROUP BY 1 ORDER BY 1
      ) s
    )
  ) INTO v_stats;

  RETURN v_stats;
END;
$$;

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
  IF public.get_my_role() NOT IN ('admin') THEN
    RAISE EXCEPTION 'Forbidden: Admin role required';
  END IF;

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
