-- =====================================================================
-- Fix 1: get_authorized_tickets — duplicated 'admin' condition
-- Was: p.role = 'admin' OR p.role = 'admin' OR p.role = 'door'
-- Fix: p.role = 'admin' OR p.role = 'rrpp' OR p.role = 'door'
-- Impact: NONE — RRPPs already saw their tickets via the fallback
--         (created_by = v_uid OR event_staff). This just adds the
--         correct broad access they should have had.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_authorized_tickets(
  p_event_id uuid DEFAULT NULL,
  p_limit int DEFAULT 200,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_my_org uuid;
  v_uid uuid;
  v_results jsonb;
BEGIN
  v_my_org := public.get_my_organization_id();
  v_uid := auth.uid();

  IF v_my_org IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT jsonb_agg(sub.ticket_json) INTO v_results
  FROM (
    SELECT
      to_jsonb(t)
      || jsonb_build_object(
        'events', jsonb_build_object('name', e.name),
        'users_profile', CASE WHEN up.user_id IS NOT NULL THEN jsonb_build_object('display_name', up.display_name) ELSE NULL END,
        'checkins', COALESCE((
          SELECT jsonb_agg(jsonb_build_object('id', c.id))
          FROM public.checkins c
          WHERE c.ticket_id = t.id
        ), '[]'::jsonb)
      ) AS ticket_json
    FROM public.tickets t
    LEFT JOIN public.events e ON t.event_id = e.id
    LEFT JOIN public.users_profile up ON t.created_by = up.user_id
    WHERE
      e.organization_id = v_my_org
      AND (p_event_id IS NULL OR t.event_id = p_event_id)
      AND (
        EXISTS (
          SELECT 1 FROM public.users_profile p
          WHERE p.user_id = v_uid AND (p.role = 'admin' OR p.role = 'rrpp' OR p.role = 'door')
        )
        OR t.event_id IN (
          SELECT es.event_id FROM public.event_staff es WHERE es.user_id = v_uid
        )
        OR t.created_by = v_uid
      )
    ORDER BY t.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) sub;

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$$;

-- =====================================================================
-- Fix 2: manage_event_staff — add admin role check
-- Was: only verified org boundary, not caller role
-- Fix: add is_admin() check so only admins can assign staff/quotas
-- Impact: NONE — only admins use the event_staff_screen UI
-- =====================================================================

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
  -- Only admin can manage event staff
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: Only admin can manage event staff';
  END IF;

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
