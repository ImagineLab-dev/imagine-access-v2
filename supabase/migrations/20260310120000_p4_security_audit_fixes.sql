-- ==========================================
-- P4 SECURITY HARDENING — Audit Fixes (March 2026)
-- Fixes: ILIKE injection, RPC auth, audit_logs RLS
-- ==========================================

-- 1. Fix audit_logs RLS: restrict INSERT to authenticated users only
-- (was: with check (true) — allowed any caller)
drop policy if exists "Services insert logs" on public.audit_logs;
create policy "Authenticated users insert logs" on public.audit_logs
  for insert with check (auth.role() = 'authenticated');

-- 2. Fix increment_event_quota: add auth + tenant verification
create or replace function public.increment_event_quota(p_event_id uuid, p_user_id uuid)
returns boolean
as $$
declare
  v_limit int;
  v_used int;
  v_caller_role text;
  v_caller_org_id uuid;
  v_event_org_id uuid;
begin
  -- Authorization: must be authenticated rrpp or admin
  if auth.uid() is null then
    raise exception 'Unauthorized: no authenticated session';
  end if;

  select coalesce(
    auth.jwt() -> 'app_metadata' ->> 'role',
    (select role from public.users_profile where user_id = auth.uid())
  ) into v_caller_role;

  if v_caller_role is null or v_caller_role not in ('rrpp', 'admin') then
    raise exception 'Forbidden: only rrpp or admin can increment quotas';
  end if;

  -- Multi-tenant: event must belong to caller's org
  select organization_id into v_caller_org_id
  from public.users_profile where user_id = auth.uid();

  select organization_id into v_event_org_id
  from public.events where id = p_event_id;

  if v_caller_org_id is distinct from v_event_org_id then
    raise exception 'Forbidden: event does not belong to your organization';
  end if;

  select quota_limit, quota_used into v_limit, v_used
  from public.event_staff
  where event_id = p_event_id and user_id = p_user_id
  for update;

  if not found then
    return false;
  end if;

  if v_used >= v_limit then
    return false;
  end if;

  update public.event_staff
  set quota_used = quota_used + 1
  where event_id = p_event_id and user_id = p_user_id;

  return true;
end;
$$ language plpgsql security definer
set search_path = public, pg_temp;

-- 3. Fix search_tickets_unified: escape ILIKE special characters
create or replace function public.search_tickets_unified(
  p_query text,
  p_type text,
  p_event_id uuid,
  p_device_id text default null,
  p_device_pin text default null
)
returns jsonb
as $$
declare
  v_uid uuid;
  v_is_authenticated boolean := false;
  v_device_org_id uuid;
  v_results jsonb := '[]'::jsonb;
  v_event_org_id uuid;
  v_user_org_id uuid;
  v_safe_query text;
begin
  -- Sanitize query: escape ILIKE special characters
  v_safe_query := replace(replace(replace(p_query, '\', '\\'), '%', '\%'), '_', '\_');

  v_uid := auth.uid();

  if v_uid is not null then
    v_is_authenticated := true;
  else
    if p_device_id is not null and p_device_pin is not null then
       select d.organization_id
       into v_device_org_id
       from public.devices d
       where d.enabled = true
         and (
           cast(d.id as text) = p_device_id
           or (
             exists (
               select 1
               from information_schema.columns
               where table_schema = 'public'
                 and table_name = 'devices'
                 and column_name = 'device_id'
             )
             and d.device_id = p_device_id
           )
         )
         and (
           (
             d.pin_hash is not null
             and d.pin_salt is not null
             and d.pin_hash = encode(digest(d.pin_salt || ':' || p_device_pin, 'sha256'), 'hex')
           )
           or (d.pin_hash is null and d.pin = p_device_pin)
         )
       limit 1;

       if v_device_org_id is not null then
         v_is_authenticated := true;
       end if;
    end if;
  end if;

  if v_is_authenticated is not true then
    return jsonb_build_object('error', 'Unauthorized: No valid session or device credentials');
  end if;

  if p_type not in ('doc', 'phone') then
    return jsonb_build_object('error', 'Invalid search type. Use doc or phone');
  end if;

  select e.organization_id into v_event_org_id
  from public.events e
  where e.id = p_event_id;

  if not found then
    return '[]'::jsonb;
  end if;

  if v_uid is not null then
    select up.organization_id into v_user_org_id
    from public.users_profile up
    where up.user_id = v_uid;

    if v_event_org_id is not null and v_user_org_id is distinct from v_event_org_id then
      return jsonb_build_object('error', 'Forbidden: event outside your organization');
    end if;
  elsif v_device_org_id is distinct from v_event_org_id then
    return jsonb_build_object('error', 'Forbidden: event outside your organization');
  end if;

  if p_type = 'doc' then
    select jsonb_agg(t) into v_results
    from (
      select tickets.*, events.name as event_name
      from public.tickets
      join public.events on events.id = tickets.event_id
      where tickets.event_id = p_event_id
      and (
        tickets.buyer_doc ilike '%' || v_safe_query || '%' escape '\'
        OR
        regexp_replace(tickets.buyer_doc, '\D', '', 'g') = regexp_replace(p_query, '\D', '', 'g')
      )
    ) t;
  else
    select jsonb_agg(t) into v_results
    from (
      select tickets.*, events.name as event_name
      from public.tickets
      join public.events on events.id = tickets.event_id
      where tickets.event_id = p_event_id
      and (
        tickets.buyer_phone ilike '%' || v_safe_query || '%' escape '\'
        OR
        regexp_replace(tickets.buyer_phone, '\D', '', 'g') = regexp_replace(p_query, '\D', '', 'g')
      )
    ) t;
  end if;

  return coalesce(v_results, '[]'::jsonb);
end;
$$ language plpgsql security definer
set search_path = public, pg_temp;

-- 4. Verify: all SECURITY DEFINER functions have search_path set
-- Expected: 0 rows (all secured)
SELECT p.proname, n.nspname
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.prosecdef = true
  AND p.proconfig IS NULL;
