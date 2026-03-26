-- Fix check_ticket_expiry to work with wall-clock time storage.
-- Dates are now stored as wall-clock time (no UTC conversion in the app),
-- so the function should read valid_until as-is without AT TIME ZONE conversion.
-- tolerance_minutes is added to extend the cutoff window.

-- Drop all overloads to avoid PostgREST ambiguity
DROP FUNCTION IF EXISTS public.check_ticket_expiry(UUID, TEXT);
DROP FUNCTION IF EXISTS public.check_ticket_expiry(UUID, TIMESTAMP);
DROP FUNCTION IF EXISTS public.check_ticket_expiry(UUID, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION public.check_ticket_expiry(
    p_ticket_id UUID,
    p_now_local TEXT
)
RETURNS TABLE (
    is_expired BOOLEAN,
    valid_until_raw TEXT,
    tolerance_minutes INT,
    event_timezone TEXT,
    server_now TEXT,
    cutoff_time TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_valid_until TIMESTAMPTZ;
    v_tolerance INT;
    v_event_tz TEXT;
    v_valid_until_naive TIMESTAMP;
    v_cutoff TIMESTAMP;
    v_now TIMESTAMP;
BEGIN
    -- Get ticket type's valid_until and tolerance
    SELECT tt.valid_until, tt.tolerance_minutes, e.timezone
    INTO v_valid_until, v_tolerance, v_event_tz
    FROM public.tickets t
    JOIN public.ticket_types tt ON tt.event_id = t.event_id AND tt.name = t.type
    JOIN public.events e ON e.id = t.event_id
    WHERE t.id = p_ticket_id
    LIMIT 1;

    -- If no valid_until set, ticket never expires by time
    IF v_valid_until IS NULL THEN
        RETURN QUERY SELECT
            false::BOOLEAN,
            NULL::TEXT,
            COALESCE(v_tolerance, 0),
            v_event_tz,
            p_now_local,
            NULL::TEXT;
        RETURN;
    END IF;

    -- Read valid_until as wall-clock time (strip timezone, use raw hour/minute)
    -- Since dates are stored as wall-clock time in TIMESTAMPTZ, just cast to
    -- TIMESTAMP to drop the offset and get the intended wall-clock value.
    v_valid_until_naive := v_valid_until::TIMESTAMP;

    -- Apply tolerance
    v_tolerance := COALESCE(v_tolerance, 0);
    v_cutoff := v_valid_until_naive + (v_tolerance || ' minutes')::INTERVAL;

    -- Parse the incoming local time
    v_now := p_now_local::TIMESTAMP;

    RETURN QUERY SELECT
        (v_now > v_cutoff)::BOOLEAN,
        to_char(v_valid_until_naive, 'YYYY-MM-DD"T"HH24:MI:SS')::TEXT,
        v_tolerance,
        v_event_tz,
        p_now_local,
        to_char(v_cutoff, 'YYYY-MM-DD"T"HH24:MI:SS')::TEXT;
END;
$$;
