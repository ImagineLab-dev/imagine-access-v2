-- Fix: Exclude voided tickets from dashboard revenue and count metrics
-- When a ticket is voided (status='void'), it should NOT count toward
-- total_sold, revenue, or any per-category counts.

-- 1. Fix get_staff_dashboard
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
    NULLIF(auth.jwt() -> 'app_metadata' ->> 'role', ''),
    (SELECT role FROM public.users_profile WHERE user_id = auth.uid()),
    'rrpp'
  );

  IF v_role IN ('admin', 'door') THEN
    v_result := jsonb_build_object(
      'total_sold', (SELECT COUNT(*) FROM public.tickets WHERE event_id = p_event_id AND COALESCE(status, 'valid') <> 'void'),
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
      'revenue', (SELECT COALESCE(SUM(price), 0) FROM public.tickets WHERE event_id = p_event_id AND COALESCE(status, 'valid') <> 'void'),
      'voided_count', (SELECT COUNT(*) FROM public.tickets WHERE event_id = p_event_id AND status = 'void'),
      'voided_revenue', (SELECT COALESCE(SUM(price), 0) FROM public.tickets WHERE event_id = p_event_id AND status = 'void'),
      'standard_created', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'standard' AND COALESCE(t.status, 'valid') <> 'void'),
      'standard_entered', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'standard' AND c.result = 'allowed'),
      'staff_created', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'staff' AND COALESCE(t.status, 'valid') <> 'void'),
      'staff_entered', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'staff' AND c.result = 'allowed'),
      'guest_created', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'guest' AND COALESCE(t.status, 'valid') <> 'void'),
      'guest_entered', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'guest' AND c.result = 'allowed'),
      'invitations_total', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'invitation' AND COALESCE(t.status, 'valid') <> 'void'),
      'invitations_scanned', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'invitation' AND c.result = 'allowed')
    );
  ELSIF v_role = 'rrpp' THEN
    v_result := (
      SELECT jsonb_build_object(
        'paid_tickets_count', (SELECT COUNT(*) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND t.created_by = v_uid AND t.price > 0 AND COALESCE(t.status, 'valid') <> 'void'),
        'paid_tickets_today', (SELECT COUNT(*) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND t.created_by = v_uid AND t.price > 0 AND t.created_at >= CURRENT_DATE AND COALESCE(t.status, 'valid') <> 'void'),
        'total_issued', (SELECT COUNT(*) FROM public.tickets WHERE event_id = p_event_id AND created_by = v_uid AND COALESCE(status, 'valid') <> 'void'),
        'invitations_count', (SELECT COUNT(*) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND t.created_by = v_uid AND t.price = 0 AND COALESCE(t.status, 'valid') <> 'void'),
        'quota_standard', es.quota_standard,
        'quota_standard_used', es.quota_standard_used,
        'remaining_standard', (es.quota_standard - es.quota_standard_used),
        'quota_guest', es.quota_guest,
        'quota_guest_used', es.quota_guest_used,
        'remaining_guest', (es.quota_guest - es.quota_guest_used),
        'total_scanned', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND t.created_by = v_uid AND c.result = 'allowed'),
        'my_revenue', (SELECT COALESCE(SUM(price), 0) FROM public.tickets WHERE event_id = p_event_id AND created_by = v_uid AND COALESCE(status, 'valid') <> 'void')
      )
      FROM public.event_staff es
      WHERE es.event_id = p_event_id AND es.user_id = v_uid
    );
  END IF;

  RETURN COALESCE(v_result, '{"my_sales":0, "my_revenue":0}'::jsonb);
END;
$$;

-- 2. Fix get_event_statistics
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
    NULLIF(auth.jwt() -> 'app_metadata' ->> 'role', ''),
    (SELECT role FROM public.users_profile WHERE user_id = auth.uid()),
    'rrpp'
  );

  IF v_role NOT IN ('admin') THEN
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
        WHERE t.event_id = p_event_id AND COALESCE(t.status, 'valid') <> 'void'
        GROUP BY 1, 2
        ORDER BY 3 DESC
      ) p
    ),
    'sales_timeline', (
      SELECT jsonb_agg(s)
      FROM (
        SELECT created_at::date AS day, count(*) AS count, sum(price) AS revenue
        FROM public.tickets
        WHERE event_id = p_event_id AND COALESCE(status, 'valid') <> 'void'
        GROUP BY 1
        ORDER BY 1
      ) s
    )
  ) INTO v_stats;

  RETURN v_stats;
END;
$$;
