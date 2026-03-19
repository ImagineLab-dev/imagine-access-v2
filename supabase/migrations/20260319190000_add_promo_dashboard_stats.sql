-- Add promo_created / promo_entered to get_staff_dashboard RPC
-- so dashboard correctly shows promo ticket metrics.

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
      'invitations_scanned', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'invitation' AND c.result = 'allowed'),
      'promo_created', (SELECT COUNT(t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'promo' AND COALESCE(t.status, 'valid') <> 'void'),
      'promo_entered', (SELECT COUNT(DISTINCT t.id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'promo' AND c.result = 'allowed')
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
