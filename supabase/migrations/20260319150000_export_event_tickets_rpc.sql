-- RPC to export all tickets for an event (admin only, org-scoped)
CREATE OR REPLACE FUNCTION public.export_event_tickets(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text;
  v_results jsonb;
BEGIN
  -- Org boundary
  IF (SELECT organization_id FROM public.events WHERE id = p_event_id) IS DISTINCT FROM public.get_my_organization_id() THEN
    RAISE EXCEPTION 'Forbidden: event does not belong to your organization';
  END IF;

  v_role := COALESCE(
    NULLIF(auth.jwt() -> 'app_metadata' ->> 'role', ''),
    (SELECT role FROM public.users_profile WHERE user_id = auth.uid()),
    'rrpp'
  );

  IF v_role NOT IN ('admin') THEN
    RAISE EXCEPTION 'Unauthorized: only admin can export event data';
  END IF;

  SELECT jsonb_agg(row_data ORDER BY row_data->>'created_at' DESC) INTO v_results
  FROM (
    SELECT jsonb_build_object(
      'id', t.id,
      'buyer_name', t.buyer_name,
      'buyer_email', t.buyer_email,
      'buyer_phone', t.buyer_phone,
      'buyer_doc', t.buyer_doc,
      'type', t.type,
      'category', tt.category,
      'price', t.price,
      'status', COALESCE(t.status, 'valid'),
      'created_at', t.created_at,
      'created_by_name', COALESCE(up.display_name, 'Sistema'),
      'scanned_at', t.scanned_at,
      'checkin_count', (SELECT COUNT(*) FROM public.checkins c WHERE c.ticket_id = t.id AND c.result = 'allowed'),
      'void_reason', t.void_reason
    ) AS row_data
    FROM public.tickets t
    LEFT JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id
    LEFT JOIN public.users_profile up ON t.created_by = up.user_id
    WHERE t.event_id = p_event_id
  ) sub;

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$$;
