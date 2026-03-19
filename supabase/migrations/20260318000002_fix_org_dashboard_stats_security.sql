-- Fix: prevent cross-org data access in get_org_dashboard_stats
-- If p_org_id is passed, it must match the caller's organization
CREATE OR REPLACE FUNCTION public.get_org_dashboard_stats(p_org_id UUID DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_org_id UUID;
BEGIN
    v_user_id := auth.uid();

    -- Always resolve the caller's organization
    SELECT organization_id INTO v_org_id
    FROM public.users_profile
    WHERE user_id = v_user_id;

    -- If an explicit org_id was passed, it MUST match the caller's org
    IF p_org_id IS NOT NULL AND p_org_id IS DISTINCT FROM v_org_id THEN
        RAISE EXCEPTION 'Forbidden: cannot access other organization stats';
    END IF;

    RETURN jsonb_build_object(
        'total_events', (SELECT COUNT(*) FROM public.events WHERE organization_id = v_org_id),
        'active_events', (SELECT COUNT(*) FROM public.events WHERE organization_id = v_org_id AND is_active = true),
        'total_tickets', (SELECT COUNT(*) FROM public.tickets t
                          JOIN public.events e ON t.event_id = e.id
                          WHERE e.organization_id = v_org_id),
        'tickets_used', (SELECT COUNT(*) FROM public.tickets t
                         JOIN public.events e ON t.event_id = e.id
                         WHERE e.organization_id = v_org_id AND t.status = 'used'),
        'total_devices', (SELECT COUNT(*) FROM public.devices WHERE organization_id = v_org_id),
        'organization_id', v_org_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
