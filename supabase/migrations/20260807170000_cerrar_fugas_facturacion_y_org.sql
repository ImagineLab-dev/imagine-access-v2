-- Cierra dos agujeros de facturacion y uno intra-organizacion que encontro la
-- auditoria adversarial de aislamiento del 07/08/2026.
--
-- IMPORTANTE — POR QUE ESTO ES UNA MIGRACION Y NO SOLO UN FIX A MANO
--
-- Los dos primeros problemas NO estaban en el codigo: las migraciones ya
-- otorgaban esas funciones SOLO a service_role. El agujero era DERIVA de
-- produccion: alguien le dio EXECUTE a `anon` y `authenticated` a mano, despues
-- de correr las migraciones. Esta migracion vuelve a declarar el estado correcto
-- para que un `db reset` o un despliegue limpio no reintroduzca la deriva, y para
-- que quede en git por que se hizo.

-- ---------------------------------------------------------------------------
-- 1. CRITICO — apply_subscription_payment invocable por anon
--
-- La funcion es SECURITY DEFINER (owner postgres, superusuario), asi que salta
-- RLS. Con EXECUTE para `anon`, cualquiera con la clave publica —sin login—
-- podia regalarse, o regalarle a CUALQUIER organizacion, una suscripcion paga y
-- reactivar orgs vencidas. Reproducido contra la org de un cliente real el
-- 07/08 (revertido): trial -> annual + un evento de pago falso insertado.
--
-- El unico control era el trigger guard_billing_columns, que trata
-- `auth.uid() IS NULL` como camino confiable (para el webhook y el soporte
-- directo). Pero el rol `anon` de PostgREST TAMBIEN produce uid NULL, asi que
-- caia en ese bypass.
--
-- El webhook legitimo de dLocal usa SUPABASE_SERVICE_ROLE_KEY, no la anon key,
-- asi que revocar anon/authenticated no rompe ningun pago real.
REVOKE ALL ON FUNCTION public.apply_subscription_payment(uuid, text, numeric, text, bigint, jsonb, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_subscription_payment(uuid, text, numeric, text, bigint, jsonb, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. ALTO — record_email_sent invocable por anon/authenticated
--
-- Mismo patron: SECURITY DEFINER que salta RLS, EXECUTE para anon, sin verificar
-- el org del que llama. Aceptaba un p_organization_id arbitrario y sumaba al
-- contador de emails de esa org. Permitia empujar a un competidor sobre su cupo
-- (DoS de sus notificaciones) o bajar el contador propio en negativo. La
-- migracion 20260728140000 ya declaraba service_role only; produccion habia
-- derivado.
REVOKE ALL ON FUNCTION public.record_email_sent(uuid, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_email_sent(uuid, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. MEDIO/ALTO intra-organizacion — cualquier miembro editaba su propia org
--
-- La policy ALL "Users see own organization" tenia USING = (owner_id = uid() OR
-- id = get_my_organization_id()) y, por ser ALL y permisiva, se OR-eaba con las
-- policies por comando. Efecto: para UPDATE y DELETE, CUALQUIER miembro de la
-- org —incluido un rol bajo como 'rrpp', ni dueno ni admin— pasaba el USING y
-- podia, por ejemplo, renombrar la organizacion. No es fuga entre
-- organizaciones (siempre es la propia), pero un miembro cualquiera no deberia
-- poder editar la entidad organizacion.
--
-- La policy era ademas REDUNDANTE para lectura: "Org member read" ya cubre el
-- SELECT con el mismo USING. Borrarla deja la lectura intacta y restringe
-- INSERT/UPDATE/DELETE al dueno (policies "Org owner *"). Verificado en tx
-- revertida: el no-dueno pierde el UPDATE, sigue viendo su org, y el dueno
-- conserva el UPDATE.
DROP POLICY IF EXISTS "Users see own organization" ON public.organizations;

-- ---------------------------------------------------------------------------
-- NOTA sobre users_profile "Profile self update" (no se cambia aca, a proposito)
--
-- La auditoria marco que su WITH CHECK (user_id = uid()) no impide, a nivel RLS,
-- que un usuario se suba el rol a 'superadmin' o cambie su organization_id. Es
-- correcto QUE lo marque, pero un WITH CHECK de RLS NO PUEDE arreglarlo: solo ve
-- la fila NUEVA, no la vieja, asi que no puede exigir "el rol no cambio". La
-- herramienta correcta para eso es el trigger guard_profile_self_update (BEFORE
-- UPDATE, SECURITY DEFINER), que SI compara OLD vs NEW y ya:
--   - aborta con FORBIDDEN_SUPERADMIN_GRANT cualquier intento de otorgar superadmin
--   - fuerza NEW.role := OLD.role y NEW.organization_id := OLD.organization_id
--     en auto-updates
-- Verificado en la auditoria: un admin NO puede auto-escalar. La defensa es
-- solida; su unico riesgo es depender de un solo trigger. No se agrega un WITH
-- CHECK falso que aparente proteger sin proteger; el endurecimiento real seria
-- una prueba de regresion que falle si el trigger se cae (pendiente).
