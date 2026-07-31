-- Dos huecos de aislamiento entre inquilinos, encontrados en la auditoría del
-- 29/07/2026.
--
-- Idempotente.

-- =============================================================================
-- 1) events: se podían crear eventos DENTRO de otra organización
-- =============================================================================
-- Las cuatro políticas de `events` decían:
--
--   is_admin() AND ( organization_id = get_my_organization_id()
--                    OR created_by = auth.uid() )
--
-- La segunda rama vuelve inútil a la primera en el INSERT: alcanza con poner
-- `created_by` propio para que el `organization_id` pueda ser el de cualquier
-- otra organización. Y el cliente inserta en `events` DIRECTO por PostgREST
-- (event_repository.dart:219), no a través de una Edge Function, así que esta
-- política es la única puerta que hay.
--
-- Consecuencia: cualquier admin —o sea, cualquiera que se registre— podía
-- plantar un evento en la organización de otro cliente. El evento aparecía en la
-- lista de la víctima, porque para ella `organization_id = get_my_organization_id()`
-- coincide. Y el atacante conservaba UPDATE y DELETE sobre él, porque esas dos
-- políticas también aceptan la rama de `created_by`.
--
-- El `OR created_by = auth.uid()` no hace falta para el uso legítimo: quien crea
-- un evento en su propia organización ya pasa por la primera rama.
-- `get_my_organization_id()` lee la TABLA, no el claim del JWT, así que apretar
-- esto no depende de que el token esté fresco.
--
-- El SELECT se deja como está a propósito. Leer un evento que uno creó no filtra
-- nada de otro inquilino, y una vez cerrado el INSERT ya no puede existir un
-- evento cuyo creador sea de otra organización.

DROP POLICY IF EXISTS "Organization Events Insert" ON public.events;
CREATE POLICY "Organization Events Insert" ON public.events
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

DROP POLICY IF EXISTS "Organization Events Update" ON public.events;
CREATE POLICY "Organization Events Update" ON public.events
  FOR UPDATE TO authenticated
  USING (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  )
  -- El WITH CHECK impide además MOVER un evento a otra organización con un
  -- UPDATE, que sería la misma jugada por otra puerta.
  WITH CHECK (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

DROP POLICY IF EXISTS "Organization Events Delete" ON public.events;
CREATE POLICY "Organization Events Delete" ON public.events
  FOR DELETE TO authenticated
  USING (
    public.is_admin()
    AND organization_id = public.get_my_organization_id()
  );

-- =============================================================================
-- 2) audit_logs: cualquiera podía escribir auditoría falsa
-- =============================================================================
-- Había DOS políticas de INSERT, idénticas, y las dos decían solamente:
--
--   auth.role() = 'authenticated'
--
-- Las políticas de RLS se combinan con OR, así que una sobraba. Y ninguna de las
-- dos miraba el CONTENIDO de la fila: cualquier usuario con sesión podía
-- insertar entradas con `user_id`, `organization_id`, `action`, `details` e
-- `ip_address` arbitrarios. Es decir, atribuir acciones a otra persona —incluido
-- el super-admin— o ensuciar la auditoría de otra organización.
--
-- Un registro de auditoría que cualquiera puede escribir no sirve como
-- evidencia de nada, que es su único propósito.
--
-- Quién escribe de verdad: cuatro Edge Functions (create_ticket, delete_user,
-- validate_ticket, void_ticket) y todas usan el service role, que NO pasa por
-- RLS. Se verificó además que ninguna función ni trigger de la base inserta
-- acá. Así que apretar esto no rompe ningún camino legítimo: la fila ahora
-- tiene que ser del propio usuario y de su propia organización.

DROP POLICY IF EXISTS "Audit Logs Insert" ON public.audit_logs;
DROP POLICY IF EXISTS "Authenticated users insert logs" ON public.audit_logs;

CREATE POLICY "Audit Logs Insert Propia" ON public.audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND organization_id = public.get_my_organization_id()
  );

-- =============================================================================
-- 3) Comprobación
-- =============================================================================
DO $mig$
DECLARE
  v_malas TEXT;
BEGIN
  -- Ninguna política de escritura puede seguir aceptando la rama de `created_by`
  -- sin exigir la organización, ni conformarse con estar autenticado.
  SELECT string_agg(tablename || '.' || policyname || ' (' || cmd || ')', ', ')
    INTO v_malas
    FROM pg_policies
   WHERE schemaname = 'public'
     AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
     AND (
       coalesce(with_check, '') LIKE '%created_by = auth.uid()%'
       OR coalesce(qual, '')    LIKE '%created_by = auth.uid()%'
       OR coalesce(with_check, '') = '(auth.role() = ''authenticated''::text)'
     );

  IF v_malas IS NULL THEN
    RAISE NOTICE 'OK: ninguna politica de escritura acepta created_by solo, ni basta con estar autenticado';
  ELSE
    RAISE EXCEPTION 'Quedaron politicas permisivas: %', v_malas;
  END IF;
END $mig$;
