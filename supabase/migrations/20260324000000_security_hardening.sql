-- ============================================================
-- Security Hardening Migration
-- Fixes: RLS privilege escalation, org deletion, audit_logs cross-org INSERT
-- ============================================================

-- -------------------------------------------------------
-- FIX 1: Prevent role self-escalation via users_profile UPDATE
-- A rrpp user could previously UPDATE their own row and set role='admin'
-- because WITH CHECK only verified organization_id, not the role column.
-- Now non-admins can only update non-sensitive fields (not role or org).
-- -------------------------------------------------------
DROP POLICY IF EXISTS "Users Profile Guard Update" ON public.users_profile;
CREATE POLICY "Users Profile Guard Update" ON public.users_profile
FOR UPDATE
USING (
  (COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
   AND organization_id = public.get_my_organization_id())
  OR (user_id = auth.uid())
)
WITH CHECK (
  -- Admin/owner: can change anything within their org
  (COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'rrpp') IN ('owner', 'admin')
   AND organization_id = public.get_my_organization_id())
  OR
  -- Non-admin self-update: allowed ONLY if role and organization_id are not changed
  (user_id = auth.uid()
   AND role = (SELECT role FROM public.users_profile WHERE user_id = auth.uid())
   AND organization_id = (SELECT organization_id FROM public.users_profile WHERE user_id = auth.uid()))
);

-- -------------------------------------------------------
-- FIX 2: Prevent any org member from deleting the organization
-- The old "FOR ALL" policy covered DELETE, letting any member destroy org+all data.
-- Split into separate SELECT/INSERT/UPDATE and DELETE (owner only).
-- -------------------------------------------------------
DROP POLICY IF EXISTS "Users see own organization" ON public.organizations;
DROP POLICY IF EXISTS "Org member read" ON public.organizations;
DROP POLICY IF EXISTS "Org owner insert" ON public.organizations;
DROP POLICY IF EXISTS "Org owner update" ON public.organizations;
DROP POLICY IF EXISTS "Org owner delete" ON public.organizations;

CREATE POLICY "Org member read" ON public.organizations
FOR SELECT USING (
  owner_id = auth.uid()
  OR id = public.get_my_organization_id()
);

CREATE POLICY "Org owner insert" ON public.organizations
FOR INSERT WITH CHECK (
  owner_id = auth.uid()
);

CREATE POLICY "Org owner update" ON public.organizations
FOR UPDATE USING (
  owner_id = auth.uid()
)
WITH CHECK (
  owner_id = auth.uid()
);

-- Only the org owner can delete the organization
CREATE POLICY "Org owner delete" ON public.organizations
FOR DELETE USING (
  owner_id = auth.uid()
);

-- -------------------------------------------------------
-- FIX 3: Prevent users from inserting audit_logs into other orgs
-- The old policy was: FOR INSERT WITH CHECK (auth.role() = 'authenticated')
-- This allowed any user to forge audit records in any org.
-- Now the inserted organization_id must match the caller's org.
-- -------------------------------------------------------
DROP POLICY IF EXISTS "Audit Logs Insert" ON public.audit_logs;
CREATE POLICY "Audit Logs Insert" ON public.audit_logs
FOR INSERT WITH CHECK (
  auth.role() = 'authenticated'
  AND organization_id = public.get_my_organization_id()
);
