-- Hierarchical config — platform-wide + per-org overrides for the
-- mobile app's tunable defaults (queue caps, cache budgets, retry
-- mechanics, sync mode, alert thresholds, etc.).
--
-- Precedence (lowest → highest): app-coded defaults → org-scoped
-- override → shop_setting (existing KV) → device override. This
-- table covers the bottom two: NULL org_id rows are platform
-- defaults; non-NULL rows are per-org overrides set by platform
-- staff (system admin portal). Shop + device layers live elsewhere.
--
-- RLS:
--   * SELECT: members of the org can read their own org's overrides;
--     platform staff can read all rows (including platform defaults).
--   * WRITE: platform staff only.
--
-- Two RPCs:
--   * get_platform_config(p_org_id): merged view — for each key,
--     returns the org-scoped row if present, else the platform
--     default row. Bypasses the per-row SELECT policy via
--     SECURITY DEFINER so a regular org member can see the
--     resolved defaults even for keys with no org override (the
--     underlying NULL-org rows are otherwise platform-staff-only).
--   * set_platform_config(p_org_id, p_key, p_value): platform staff
--     upsert. p_org_id NULL = platform default.

create table public.platform_config (
  id          uuid primary key default extensions.gen_random_uuid(),
  org_id      uuid references public.organization(id) on delete cascade,
  key         text not null,
  value       jsonb not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id)
);

-- org_id is NULLABLE on purpose: a NULL-org row is the platform-wide
-- default for a key (the bottom of the override stack). A surrogate `id`
-- is the primary key so org_id can be null — Postgres forces every PK
-- column NOT NULL, so org_id must NOT be part of the PK. Uniqueness is
-- enforced per scope by two partial unique indexes: one (org_id, key)
-- for org-scoped rows, and one (key) for the single NULL-org default.
create unique index platform_config_org_key_uq
  on public.platform_config(org_id, key)
  where org_id is not null;
create unique index platform_config_default_uq
  on public.platform_config(key)
  where org_id is null;

create index platform_config_org_idx
  on public.platform_config(org_id);

alter table public.platform_config enable row level security;

-- SELECT: org members for their org's rows; platform staff for all
-- (including NULL-org platform defaults).
create policy platform_config_select on public.platform_config
  for select to authenticated
  using (
    (org_id is null and public.auth_is_platform_staff())
    or (org_id is not null and public.auth_can_access_organization(org_id))
  );

-- INSERT/UPDATE/DELETE: platform staff only.
create policy platform_config_write on public.platform_config
  for all to authenticated
  using (public.auth_is_platform_staff())
  with check (public.auth_is_platform_staff());

-- Table-level SELECT grant so the platform_config_select policy is
-- reachable (RLS gates the rows; without a grant the table is opaque).
-- Writes go only through set_platform_config (SECURITY DEFINER), per the
-- "RPC-only writes" convention — no direct insert/update/delete grant.
grant select on public.platform_config to authenticated;

-- ---------------------------------------------------------------------------
-- get_platform_config: returns merged keys for an org. Org-scoped rows
-- win over platform defaults; missing keys fall through to app-coded
-- defaults on the client.
--
-- SECURITY DEFINER because regular org members need to see the
-- platform-default rows too (which the SELECT policy hides from
-- them). The function authorizes by checking org membership itself.
-- ---------------------------------------------------------------------------
create or replace function public.get_platform_config(p_org_id uuid)
returns table (key text, value jsonb)
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
  if not (
    public.auth_can_access_organization(p_org_id)
    or public.auth_is_platform_staff()
  ) then
    raise exception 'Not allowed to read this org config';
  end if;

  return query
    with ranked as (
      select pc.key, pc.value,
             case when pc.org_id is null then 0 else 1 end as priority
      from public.platform_config pc
      where pc.org_id is null or pc.org_id = p_org_id
    ),
    winning as (
      select r.key, max(r.priority) as max_priority
      from ranked r
      group by r.key
    )
    select r.key, r.value
    from ranked r
    join winning w on w.key = r.key and w.max_priority = r.priority;
end;
$$;

revoke all on function public.get_platform_config(uuid) from public;
grant execute on function public.get_platform_config(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- set_platform_config: platform-staff-only upsert. p_org_id NULL =
-- platform default (the bottom of the override stack).
-- ---------------------------------------------------------------------------
create or replace function public.set_platform_config(
  p_org_id  uuid,
  p_key     text,
  p_value   jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.auth_is_platform_staff() then
    raise exception 'Only platform staff can set platform_config';
  end if;
  if p_key is null or length(trim(p_key)) = 0 then
    raise exception 'platform_config key cannot be blank';
  end if;
  if p_value is null then
    raise exception 'platform_config value cannot be null';
  end if;

  -- NULL-safe upsert: `org_id is not distinct from p_org_id` matches the
  -- platform-default row (both NULL) as well as an org row. Avoids the
  -- ON CONFLICT-with-partial-index ambiguity now that org_id is nullable.
  update public.platform_config
     set value      = p_value,
         updated_at = pg_catalog.now(),
         updated_by = auth.uid()
   where key = p_key
     and org_id is not distinct from p_org_id;
  if not found then
    insert into public.platform_config (org_id, key, value, updated_at, updated_by)
    values (p_org_id, p_key, p_value, pg_catalog.now(), auth.uid());
  end if;
end;
$$;

revoke all on function public.set_platform_config(uuid, text, jsonb) from public;
grant execute on function public.set_platform_config(uuid, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- get_platform_config_for_shop: convenience wrapper that resolves the
-- shop's organization_id and returns the merged config for that org.
-- Mobile calls this — saves wiring an `organization_id` field onto
-- ShopSummary just to feed the lookup. Authorization happens inside
-- get_platform_config, which is invoked under the same security
-- definer context (SECURITY DEFINER persists through the SQL call).
-- ---------------------------------------------------------------------------
create or replace function public.get_platform_config_for_shop(p_shop_id uuid)
returns table (key text, value jsonb)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_org_id uuid;
begin
  select organization_id into v_org_id
    from public.shop where id = p_shop_id;
  if v_org_id is null then
    raise exception 'Shop % not found', p_shop_id;
  end if;
  return query select gpc.key, gpc.value
    from public.get_platform_config(v_org_id) gpc;
end;
$$;

revoke all on function public.get_platform_config_for_shop(uuid) from public;
grant execute on function public.get_platform_config_for_shop(uuid) to authenticated;
