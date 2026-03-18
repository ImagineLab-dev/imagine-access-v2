-- =============================================================================
-- P6: Dashboard RPCs owner recognition + FK indexes + input validation in RPCs
-- =============================================================================
BEGIN;

-- 1. Fix get_authorized_tickets: recognize 'owner' role
CREATE OR REPLACE FUNCTION public.get_authorized_tickets()
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

  SELECT jsonb_agg(
    to_jsonb(t)
    || jsonb_build_object(
      'events', jsonb_build_object('name', e.name),
      'users_profile', CASE WHEN up.user_id IS NOT NULL THEN jsonb_build_object('display_name', up.display_name) ELSE NULL END,
      'checkins', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('id', c.id))
        FROM public.checkins c
        WHERE c.ticket_id = t.id
      ), '[]'::jsonb)
    )
  ) INTO v_results
  FROM public.tickets t
  LEFT JOIN public.events e ON t.event_id = e.id
  LEFT JOIN public.users_profile up ON t.created_by = up.user_id
  WHERE
    e.organization_id = v_my_org
    AND (
      EXISTS (
        SELECT 1 FROM public.users_profile p
        WHERE p.user_id = v_uid AND (p.role = 'owner' OR p.role = 'admin' OR p.role = 'door')
      )
      OR t.event_id IN (
        SELECT es.event_id FROM public.event_staff es WHERE es.user_id = v_uid
      )
      OR t.created_by = v_uid
    );

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$$;

-- 2. Fix get_staff_dashboard: recognize 'owner' role
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
  IF (SELECT organization_id FROM public.events WHERE id = p_event_id) IS DISTINCT FROM public.get_my_organization_id() THEN
    RAISE EXCEPTION 'Forbidden: You do not have access to this event dashboard';
  END IF;

  v_uid := auth.uid();
  v_role := COALESCE(
    auth.jwt() -> 'app_metadata' ->> 'role',
    'rrpp'
  );

  IF v_role IN ('owner', 'admin', 'door') THEN
    v_result := jsonb_build_object(
      'total_sold', (SELECT COUNT(*) FROM public.tickets WHERE event_id = p_event_id),
      'scanned', (SELECT COUNT(DISTINCT ticket_id) FROM public.checkins WHERE event_id = p_event_id AND result = 'allowed'),
      'scanned_manual', (SELECT COUNT(DISTINCT ticket_id) FROM public.checkins WHERE event_id = p_event_id AND result = 'allowed' AND method <> 'qr'),
      'valid', (
        SELECT COUNT(*) FROM public.tickets
        WHERE event_id = p_event_id
          AND (status IS NULL OR LOWER(status) = 'valid')
          AND id NOT IN (
            SELECT c.ticket_id FROM public.checkins c
            WHERE c.event_id = p_event_id AND c.result = 'allowed'
          )
      ),
      'revenue', (SELECT COALESCE(SUM(price), 0) FROM public.tickets WHERE event_id = p_event_id),
      'standard_created', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'standard'),
      'standard_entered', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'standard' AND c.result = 'allowed'),
      'staff_created', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'staff'),
      'staff_entered', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'staff' AND c.result = 'allowed'),
      'guest_created', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'guest'),
      'guest_entered', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'guest' AND c.result = 'allowed')
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

-- 3. Fix get_event_statistics: recognize 'owner' role
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
  IF (SELECT organization_id FROM public.events WHERE id = p_event_id) IS DISTINCT FROM public.get_my_organization_id() THEN
    RAISE EXCEPTION 'Forbidden: You do not have access to this event statistics';
  END IF;

  v_role := COALESCE(
    auth.jwt() -> 'app_metadata' ->> 'role',
    'rrpp'
  );

  IF v_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'Unauthorized: Statistics only available for Owner or Admin role';
  END IF;

  SELECT jsonb_build_object(
    'attendance_by_hour', (
      SELECT jsonb_agg(h)
      FROM (
        SELECT to_char(date_trunc('hour', scanned_at), 'HH24:00') AS hour, count(*) AS count
        FROM public.checkins
        WHERE event_id = p_event_id AND result = 'allowed'
        GROUP BY 1
        ORDER BY 1
      ) h
    ),
    'rrpp_performance', (
      SELECT jsonb_agg(p)
      FROM (
        SELECT COALESCE(up.display_name, u.email) AS name, t.type, count(*) AS count
        FROM public.tickets t
        LEFT JOIN auth.users u ON t.created_by = u.id
        LEFT JOIN public.users_profile up ON u.id = up.user_id
        WHERE t.event_id = p_event_id
        GROUP BY 1, 2
        ORDER BY 3 DESC
      ) p
    ),
    'sales_timeline', (
      SELECT jsonb_agg(s)
      FROM (
        SELECT created_at::date AS day, count(*) AS count, sum(price) AS revenue
        FROM public.tickets
        WHERE event_id = p_event_id
        GROUP BY 1
        ORDER BY 1
      ) s
    )
  ) INTO v_stats;

  RETURN v_stats;
END;
$$;

-- 4. Fix create_user_organization: set 'owner' role for org creator
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
  SET organization_id = v_org_id,
      role = 'owner'
  WHERE user_id = p_user_id;

  RETURN v_org_id;
END;
$$;

-- 5. Fix event_staff CHECK constraint to include 'owner'
ALTER TABLE public.event_staff DROP CONSTRAINT IF EXISTS event_staff_role_check;
ALTER TABLE public.event_staff
  ADD CONSTRAINT event_staff_role_check
  CHECK (role IN ('owner', 'admin', 'rrpp', 'door'));

-- 6. Performance indexes on high-join foreign keys
CREATE INDEX IF NOT EXISTS idx_tickets_event_id ON public.tickets(event_id);
CREATE INDEX IF NOT EXISTS idx_tickets_created_by ON public.tickets(created_by);
CREATE INDEX IF NOT EXISTS idx_checkins_ticket_id ON public.checkins(ticket_id);
CREATE INDEX IF NOT EXISTS idx_checkins_event_id ON public.checkins(event_id);
CREATE INDEX IF NOT EXISTS idx_ticket_types_event_id ON public.ticket_types(event_id);

-- 7. Fix Event Staff Read to include 'owner'
DROP POLICY IF EXISTS "Event Staff Read" ON public.event_staff;
CREATE POLICY "Event Staff Read" ON public.event_staff
FOR SELECT USING (
  user_id = auth.uid()
  OR (
    COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
    AND event_id IN (
      SELECT e.id FROM public.events e
      WHERE e.organization_id = public.get_my_organization_id()
    )
  )
);

COMMIT;
