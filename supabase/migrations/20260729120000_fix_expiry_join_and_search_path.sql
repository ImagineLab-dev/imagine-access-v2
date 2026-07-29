-- Auditoría 29/07/2026: dos defectos en el chequeo de vencimiento, más los
-- índices que faltaban en claves foráneas.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) check_ticket_expiry: unir por id, no por nombre
-- -----------------------------------------------------------------------------
-- Unía el ticket con su tipo comparando `tt.name = t.type`, teniendo
-- `tickets.ticket_type_id` disponible y poblado al 100%.
--
-- El día que alguien renombra un tipo de entrada —algo perfectamente normal
-- antes de un evento— los tickets ya emitidos dejan de encontrar sus reglas. La
-- consulta no devuelve fila, `v_valid_until` queda NULL, y la función responde
-- "no vence nunca". Una invitación que debía caducar a las dos de la mañana se
-- acepta a las cinco, sin error y sin rastro.
--
-- También le faltaba `SET search_path`. Las tablas están calificadas con
-- `public.`, así que no era explotable de inmediato, pero era la única función
-- SECURITY DEFINER del esquema sin esa protección.
CREATE OR REPLACE FUNCTION public.check_ticket_expiry(
    p_ticket_id UUID,
    p_now_local TEXT
)
RETURNS TABLE(
    is_expired BOOLEAN,
    valid_until_raw TEXT,
    tolerance_minutes INTEGER,
    event_timezone TEXT,
    server_now TEXT,
    cutoff_time TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_valid_until TIMESTAMPTZ;
    v_tolerance INT;
    v_event_tz TEXT;
    v_valid_until_naive TIMESTAMP;
    v_cutoff TIMESTAMP;
    v_now TIMESTAMP;
BEGIN
    -- Por ticket_type_id, con el nombre solo como respaldo para filas viejas
    -- que pudieran no tenerlo. Hoy están todas con id.
    SELECT tt.valid_until, tt.tolerance_minutes, e.timezone
      INTO v_valid_until, v_tolerance, v_event_tz
      FROM public.tickets t
      JOIN public.events e ON e.id = t.event_id
      JOIN public.ticket_types tt
        ON tt.id = t.ticket_type_id
        OR (t.ticket_type_id IS NULL
            AND tt.event_id = t.event_id
            AND tt.name = t.type)
     WHERE t.id = p_ticket_id
     LIMIT 1;

    -- Sin valid_until, el ticket no caduca por horario.
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

    -- valid_until se guarda como hora de pared dentro de un TIMESTAMPTZ, así
    -- que el cast a TIMESTAMP descarta el desplazamiento y deja la hora
    -- pretendida.
    v_valid_until_naive := v_valid_until::TIMESTAMP;

    v_tolerance := COALESCE(v_tolerance, 0);
    v_cutoff := v_valid_until_naive + (v_tolerance || ' minutes')::INTERVAL;
    v_now := p_now_local::TIMESTAMP;

    RETURN QUERY SELECT
        (v_now > v_cutoff)::BOOLEAN,
        to_char(v_valid_until_naive, 'YYYY-MM-DD"T"HH24:MI:SS')::TEXT,
        v_tolerance,
        v_event_tz,
        p_now_local,
        to_char(v_cutoff, 'YYYY-MM-DD"T"HH24:MI:SS')::TEXT;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2) Índices en claves foráneas
-- -----------------------------------------------------------------------------
-- Postgres no los crea solo. Sin ellos, cada borrado en la tabla referenciada
-- recorre la referenciante entera y toma bloqueos más amplios. Con las tablas
-- actuales no se nota; con un evento de mil tickets, sí.
CREATE INDEX IF NOT EXISTS organizations_owner_idx     ON public.organizations (owner_id);
CREATE INDEX IF NOT EXISTS users_profile_created_by_idx ON public.users_profile (created_by);
CREATE INDEX IF NOT EXISTS events_created_by_idx        ON public.events (created_by);
CREATE INDEX IF NOT EXISTS checkins_operator_idx        ON public.checkins (operator_user);
CREATE INDEX IF NOT EXISTS event_staff_user_idx         ON public.event_staff (user_id);
CREATE INDEX IF NOT EXISTS audit_logs_user_idx          ON public.audit_logs (user_id);
CREATE INDEX IF NOT EXISTS superadmin_audit_actor_idx   ON public.superadmin_audit (actor_id);
