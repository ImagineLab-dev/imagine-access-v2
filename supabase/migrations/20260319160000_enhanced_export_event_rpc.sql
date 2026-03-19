-- Enhanced export RPC: returns event info, tickets, and checkin details
CREATE OR REPLACE FUNCTION public.export_event_full(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text;
  v_event jsonb;
  v_tickets jsonb;
  v_checkins jsonb;
BEGIN
  -- Org boundary
  IF (SELECT organization_id FROM public.events WHERE id = p_event_id)
     IS DISTINCT FROM public.get_my_organization_id() THEN
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

  -- Event info
  SELECT jsonb_build_object(
    'name', e.name,
    'date', e.date,
    'venue', e.venue,
    'address', e.address,
    'city', e.city,
    'currency', e.currency
  ) INTO v_event
  FROM public.events e WHERE e.id = p_event_id;

  -- Tickets with seller info
  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'created_at' DESC), '[]'::jsonb)
  INTO v_tickets
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
      'created_by', t.created_by,
      'created_by_name', COALESCE(up.display_name, 'Sistema'),
      'created_by_role', COALESCE(up.role, 'rrpp'),
      'scanned_at', t.scanned_at,
      'void_reason', t.void_reason
    ) AS row_data
    FROM public.tickets t
    LEFT JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id
    LEFT JOIN public.users_profile up ON t.created_by = up.user_id
    WHERE t.event_id = p_event_id
  ) sub;

  -- Checkins with operator info and timestamps
  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'scanned_at' ASC), '[]'::jsonb)
  INTO v_checkins
  FROM (
    SELECT jsonb_build_object(
      'ticket_id', c.ticket_id,
      'scanned_at', c.scanned_at,
      'result', c.result,
      'method', c.method,
      'operator_name', COALESCE(op.display_name, 'Desconocido')
    ) AS row_data
    FROM public.checkins c
    LEFT JOIN public.users_profile op ON c.operator_user = op.user_id
    WHERE c.event_id = p_event_id
  ) sub;

  RETURN jsonb_build_object(
    'event', v_event,
    'tickets', v_tickets,
    'checkins', v_checkins
  );
END;
$$;
