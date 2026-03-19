-- ============================================================
-- Promo pack grouping: add promo_pack_id to track packs
-- so reports/dashboard count packs, not individual tickets.
-- ============================================================

-- 1. Add promo_pack_id column
ALTER TABLE public.tickets
  ADD COLUMN IF NOT EXISTS promo_pack_id UUID;

CREATE INDEX IF NOT EXISTS idx_tickets_promo_pack_id
  ON public.tickets(promo_pack_id) WHERE promo_pack_id IS NOT NULL;

-- 2. Fix old promo data: group the 3 "tests" tickets as 1 pack
--    pack UUID = first ticket's id: fc960783-ec48-47c7-ba2d-bd409344932a
UPDATE public.tickets
  SET promo_pack_id = 'fc960783-ec48-47c7-ba2d-bd409344932a'
  WHERE id IN (
    'fc960783-ec48-47c7-ba2d-bd409344932a',
    '319c2d01-e837-4a5c-9934-532a452c35e3',
    '77c8fc96-4548-4064-9526-52032b864ba0'
  );

-- Patricio's single promo ticket = its own pack
UPDATE public.tickets
  SET promo_pack_id = 'fd758e98-c9bb-4863-9d89-82de018b6dd2'
  WHERE id = 'fd758e98-c9bb-4863-9d89-82de018b6dd2';

-- Fix prices: only the first ticket in "tests" pack keeps full price
UPDATE public.tickets SET price = 0
  WHERE id IN (
    '319c2d01-e837-4a5c-9934-532a452c35e3',
    '77c8fc96-4548-4064-9526-52032b864ba0'
  );

-- 3. Update export_event_full RPC to include promo_pack_id
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

  SELECT jsonb_build_object(
    'name', e.name,
    'date', e.date,
    'venue', e.venue,
    'address', e.address,
    'city', e.city,
    'currency', e.currency
  ) INTO v_event
  FROM public.events e WHERE e.id = p_event_id;

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
      'void_reason', t.void_reason,
      'promo_pack_id', t.promo_pack_id
    ) AS row_data
    FROM public.tickets t
    LEFT JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id
    LEFT JOIN public.users_profile up ON t.created_by = up.user_id
    WHERE t.event_id = p_event_id
  ) sub;

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

-- 4. Update get_staff_dashboard: promo_created counts packs (DISTINCT promo_pack_id)
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
      'promo_created', (SELECT COUNT(DISTINCT t.promo_pack_id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id WHERE t.event_id = p_event_id AND tt.category = 'promo' AND COALESCE(t.status, 'valid') <> 'void' AND t.promo_pack_id IS NOT NULL),
      'promo_entered', (SELECT COUNT(DISTINCT t.promo_pack_id) FROM public.tickets t JOIN public.ticket_types tt ON t.type = tt.name AND t.event_id = tt.event_id JOIN public.checkins c ON t.id = c.ticket_id WHERE t.event_id = p_event_id AND tt.category = 'promo' AND c.result = 'allowed' AND t.promo_pack_id IS NOT NULL)
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
