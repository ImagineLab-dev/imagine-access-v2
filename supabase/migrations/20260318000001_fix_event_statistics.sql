-- Fix get_event_statistics: remove auth.users join (42P01 error)
-- Use users_profile instead, and COALESCE jsonb_agg to return [] instead of null

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
    'attendance_by_hour', COALESCE((
      SELECT jsonb_agg(h) FROM (
        SELECT to_char(date_trunc('hour', scanned_at), 'HH24:00') AS hour, count(*) AS count
        FROM public.checkins WHERE event_id = p_event_id AND result = 'allowed'
        GROUP BY 1 ORDER BY 1
      ) h
    ), '[]'::jsonb),
    'rrpp_performance', COALESCE((
      SELECT jsonb_agg(p) FROM (
        SELECT COALESCE(up.display_name, up.user_id::text) AS name, t.type, count(*) AS count
        FROM public.tickets t
        LEFT JOIN public.users_profile up ON t.created_by = up.user_id
        WHERE t.event_id = p_event_id
        GROUP BY 1, 2 ORDER BY 3 DESC
      ) p
    ), '[]'::jsonb),
    'sales_timeline', COALESCE((
      SELECT jsonb_agg(s) FROM (
        SELECT created_at::date AS day, count(*) AS count, sum(price) AS revenue
        FROM public.tickets WHERE event_id = p_event_id
        GROUP BY 1 ORDER BY 1
      ) s
    ), '[]'::jsonb)
  ) INTO v_stats;

  RETURN v_stats;
END;
$$;
