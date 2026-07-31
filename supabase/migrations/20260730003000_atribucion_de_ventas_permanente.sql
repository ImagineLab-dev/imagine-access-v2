-- Dar de baja a un RRPP borraba la atribución de todo lo que había vendido.
--
-- `delete_member_user` hace `DELETE FROM users_profile`, y la clave foránea
-- `tickets_created_by_profile_fkey` es `ON DELETE SET NULL`. Así que al quitar a
-- un vendedor del equipo, `tickets.created_by` quedaba en NULL en TODOS sus
-- tickets.
--
-- Y `rrpp_performance` resuelve el nombre así:
--
--   SELECT COALESCE(up.display_name, u.email) AS name
--     FROM tickets t
--     LEFT JOIN auth.users u    ON t.created_by = u.id
--     LEFT JOIN users_profile up ON u.id = up.user_id
--
-- Con `created_by` en NULL las dos uniones fallan y el vendedor desaparece del
-- reporte. Sus ventas quedan sin dueño, y la liquidación de comisiones de ese
-- evento no se puede reconstruir. Silencioso e irreversible.
--
-- La solución es guardar el nombre EN EL TICKET al momento de emitirlo. Un
-- ticket es un hecho histórico: quién lo vendió no cambia porque después esa
-- persona se vaya del equipo.
--
-- El nombre vivo sigue teniendo prioridad, así que si alguien se cambia el
-- nombre en su perfil los reportes lo muestran actualizado. La copia solo entra
-- cuando ya no hay perfil que consultar.
--
-- Idempotente.

-- -----------------------------------------------------------------------------
-- 1) La columna
-- -----------------------------------------------------------------------------
ALTER TABLE public.tickets
  ADD COLUMN IF NOT EXISTS seller_name TEXT;

COMMENT ON COLUMN public.tickets.seller_name IS
  'Nombre de quien emitió el ticket, copiado al momento de emitirlo. Sobrevive '
  'a la baja de esa persona del equipo, que pone created_by en NULL. Los '
  'reportes prefieren el nombre vivo del perfil y usan esta copia como respaldo.';

-- -----------------------------------------------------------------------------
-- 2) Se llena sola al emitir
-- -----------------------------------------------------------------------------
-- En un trigger y no en `create_ticket`: los tickets entran por la Edge Function
-- pero también podrían entrar por otro camino mañana, y una regla que vive en un
-- solo lado del cliente es la que se olvida. Es el mismo razonamiento por el que
-- hoy el rol se decide en un único lugar por capa.
CREATE OR REPLACE FUNCTION public.copiar_nombre_del_vendedor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Si quien inserta ya mandó un nombre, se respeta: sirve para importaciones y
  -- para rellenar históricos sin pelearse con el trigger.
  IF NEW.seller_name IS NOT NULL AND NEW.seller_name <> '' THEN
    RETURN NEW;
  END IF;

  IF NEW.created_by IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT NULLIF(TRIM(COALESCE(p.display_name, '')), '')
    INTO NEW.seller_name
    FROM public.users_profile p
   WHERE p.user_id = NEW.created_by
   LIMIT 1;

  -- Si el perfil no tiene nombre puesto, se usa el correo de la cuenta antes de
  -- rendirse: es mejor "juan@ejemplo.com" que una fila sin dueño.
  IF NEW.seller_name IS NULL THEN
    SELECT NULLIF(TRIM(COALESCE(u.email, '')), '')
      INTO NEW.seller_name
      FROM auth.users u
     WHERE u.id = NEW.created_by
     LIMIT 1;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_ticket_copiar_vendedor ON public.tickets;
CREATE TRIGGER on_ticket_copiar_vendedor
  BEFORE INSERT ON public.tickets
  FOR EACH ROW EXECUTE FUNCTION public.copiar_nombre_del_vendedor();

-- -----------------------------------------------------------------------------
-- 3) Relleno de los que ya existen
-- -----------------------------------------------------------------------------
-- Solo donde falta y todavía se puede averiguar. Los tickets cuyo `created_by`
-- ya quedó en NULL no tienen de dónde recuperar el nombre: esa información se
-- perdió antes de esta migración y no hay forma de reconstruirla.
UPDATE public.tickets t
   SET seller_name = COALESCE(
         NULLIF(TRIM(COALESCE(p.display_name, '')), ''),
         NULLIF(TRIM(COALESCE(u.email, '')), '')
       )
  FROM auth.users u
  LEFT JOIN public.users_profile p ON p.user_id = u.id
 WHERE t.created_by = u.id
   AND (t.seller_name IS NULL OR t.seller_name = '');

-- -----------------------------------------------------------------------------
-- 4) Los reportes usan la copia como respaldo
-- -----------------------------------------------------------------------------
-- Sustitución quirúrgica sobre el cuerpo real, con verificación: si el patrón no
-- aparece, aborta. Un replace que no encuentra nada devuelve el texto igual y se
-- ejecuta sin quejarse, y eso hace pasar por arreglado algo que no se tocó.
DO $mig$
DECLARE
  v_def   TEXT;
  v_viejo TEXT := 'SELECT COALESCE(up.display_name, u.email) AS name';
  v_nuevo TEXT := 'SELECT COALESCE(up.display_name, u.email, t.seller_name) AS name';
BEGIN
  v_def := pg_get_functiondef('public.get_event_statistics(uuid)'::regprocedure);

  IF position(v_nuevo IN v_def) > 0 THEN
    RAISE NOTICE 'get_event_statistics ya usaba seller_name';
    RETURN;
  END IF;

  IF position(v_viejo IN v_def) = 0 THEN
    RAISE EXCEPTION 'ABORTA: no se encontro <%> en get_event_statistics', v_viejo;
  END IF;

  EXECUTE replace(v_def, v_viejo, v_nuevo);
  RAISE NOTICE 'get_event_statistics: rrpp_performance ahora cae en seller_name';
END $mig$;

-- -----------------------------------------------------------------------------
-- 5) Comprobación
-- -----------------------------------------------------------------------------
DO $mig$
DECLARE
  v_sin_nombre INT;
  v_total      INT;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE seller_name IS NULL AND created_by IS NOT NULL)
    INTO v_total, v_sin_nombre
    FROM public.tickets;

  IF v_sin_nombre > 0 THEN
    RAISE EXCEPTION 'Quedaron % de % tickets con creador pero sin seller_name', v_sin_nombre, v_total;
  END IF;

  RAISE NOTICE 'OK: % tickets, todos los que tienen creador tienen su nombre copiado', v_total;
END $mig$;
