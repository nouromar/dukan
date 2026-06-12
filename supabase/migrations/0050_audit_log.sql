-- 0050_audit_log.sql
--
-- Audit log subsystem per docs/audit-log.md. Schema + write helper +
-- maintenance function + RLS + initial partitions + capability seed.
-- Instrumentation of the existing posting RPCs lands separately as
-- migration 0051 so this one stays atomic and reviewable.
--
-- Three tables:
--
--   audit_action_code  -- catalog of legal action codes. FK from
--                         audit_log so unknown codes are refused at
--                         write time, not silently swallowed.
--   audit_log          -- the append-only event store. Partitioned
--                         by occurred_at (month). RLS gated by
--                         auth_can_access_shop. Direct INSERT is
--                         refused; only _audit_log can write.
--   audit_summary      -- daily rollup of counts per (shop, action,
--                         actor). Survives partition drop forever
--                         so compliance reads outlive retention.
--
-- Retention (per docs/audit-log.md §7):
--   Hot tier   = 90 days, full snapshots, indexed.
--   Summary    = forever, counts only.
--   Warm + Cold are deferred (v1.x / v2).
--
-- pg_cron schedules the daily maintenance call when the extension
-- is available (Supabase managed environments). The standalone
-- harness skips the schedule and tests the function via direct
-- call.

-- ---------------------------------------------------------------
-- 1. audit_action_code -- registry of legal codes.
-- ---------------------------------------------------------------

create table public.audit_action_code (
  code              text primary key
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  area              text not null,
  description       text,
  captures_before   boolean not null default false,
  captures_after    boolean not null default false,
  requires_reason   boolean not null default false,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now()
);

insert into public.audit_action_code
  (code, area, description, captures_before, captures_after, requires_reason)
values
  ('sale.post',                          'sale',      'Sale posted',                                false, true,  false),
  ('sale.void',                          'sale',      'Sale voided (reverses_transaction_id chain)', true,  true,  true),
  ('receive.post',                       'receive',   'Receive posted',                             false, true,  false),
  ('receive.void',                       'receive',   'Receive voided',                             true,  true,  true),
  ('payment.post',                       'payment',   'Payment posted',                             false, true,  false),
  ('payment.reallocate',                 'payment',   'Payment allocation rebalanced',              true,  true,  true),
  ('expense.post',                       'expense',   'Expense posted',                             false, true,  false),
  ('inventory.product.create',           'inventory', 'New shop_item created',                      false, true,  false),
  ('inventory.product.edit',             'inventory', 'Product name/category/threshold edited',     true,  true,  false),
  ('inventory.product.activate',         'inventory', 'Catalog item activated for this shop',       false, true,  false),
  ('inventory.unit.create',              'inventory', 'New packaging created',                      false, true,  false),
  ('inventory.unit.deactivate',          'inventory', 'Packaging deactivated',                      true,  false, false),
  ('inventory.unit.price_edit',          'inventory', 'Sale price changed on a packaging',          false, true,  false),
  ('inventory.unit.default_flag_change', 'inventory', 'Default sale/receive flag toggled',          true,  true,  false),
  ('inventory.alias.add',                'inventory', 'Alias added',                                false, true,  false),
  ('inventory.alias.remove',             'inventory', 'Alias removed',                              true,  false, false),
  ('inventory.barcode.add',              'inventory', 'Barcode bound to a packaging',               false, true,  false),
  ('inventory.barcode.remove',           'inventory', 'Barcode unlinked',                           true,  false, false),
  ('inventory.barcode.set_primary',      'inventory', 'Primary barcode promoted',                   true,  true,  false),
  ('inventory.adjustment.post',          'inventory', 'Stock adjustment posted',                    false, true,  true),
  ('people.party.create',                'people',    'Customer or supplier created',               false, true,  false),
  ('people.party.edit',                  'people',    'Party contact info edited',                  true,  true,  false),
  ('people.party.opening_balance',       'people',    'Opening balance posted (one-time)',          false, true,  true),
  ('setup.shop.edit',                    'setup',     'Shop settings changed',                      true,  true,  false),
  ('setup.staff.invite',                 'setup',     'Staff member invited',                       false, true,  false),
  ('setup.staff.role_change',            'setup',     'Staff role changed',                         true,  true,  true),
  ('setup.staff.revoke',                 'setup',     'Staff access revoked',                       true,  false, true),
  ('auth.impersonation.start',           'auth',      'Platform staff impersonation began',         false, true,  true),
  ('auth.impersonation.end',             'auth',      'Platform staff impersonation ended',         false, false, false);

-- ---------------------------------------------------------------
-- 2. audit_summary -- forever rollup.
-- ---------------------------------------------------------------

create table public.audit_summary (
  shop_id           uuid not null references public.shop(id) on delete cascade,
  day               date not null,
  action_code       text not null references public.audit_action_code(code) on delete restrict,
  actor_user_id     uuid,
  source            text not null,
  count             integer not null check (count > 0),
  primary key (shop_id, day, action_code, actor_user_id, source)
);

create index audit_summary_shop_day on public.audit_summary (shop_id, day desc);

alter table public.audit_summary enable row level security;

create policy audit_summary_select_member on public.audit_summary
  for select to authenticated
  using (public.auth_can_access_shop(audit_summary.shop_id));

-- INSERT, UPDATE, DELETE are not granted to authenticated -- the
-- maintenance function (security definer) is the only writer.

-- ---------------------------------------------------------------
-- 3. audit_log -- partitioned event store.
-- ---------------------------------------------------------------

create table public.audit_log (
  id                       uuid not null default extensions.gen_random_uuid(),
  shop_id                  uuid not null,
  actor_user_id            uuid,
  action_code              text not null references public.audit_action_code(code) on delete restrict,
  entity_type              text not null,
  entity_id                uuid,
  entity_ids               uuid[],
  before_state             jsonb,
  after_state              jsonb,
  reason                   text,
  client_op_id             text,
  source                   text not null
    check (source in ('mobile','shop_admin_web','system_admin_web','rpc','system')),
  impersonation_session_id uuid,
  occurred_at              timestamptz not null default now(),
  primary key (occurred_at, id),
  -- shop_id and actor_user_id FKs replicated on every partition
  -- via PG inheritance.
  foreign key (shop_id) references public.shop(id) on delete cascade,
  foreign key (actor_user_id) references auth.users(id) on delete set null
) partition by range (occurred_at);

create index audit_log_shop_recent
  on public.audit_log (shop_id, occurred_at desc);

create index audit_log_entity
  on public.audit_log (shop_id, entity_type, entity_id, occurred_at desc)
  where entity_id is not null;

alter table public.audit_log enable row level security;

create policy audit_log_select_member on public.audit_log
  for select to authenticated
  using (public.auth_can_access_shop(audit_log.shop_id));

-- Direct INSERT/UPDATE/DELETE are NOT granted. Writes flow through
-- _audit_log (security definer) only. Append-only by design.

-- Grants: authenticated reads everything that's RLS-gated. INSERT/
-- UPDATE/DELETE are NOT granted -- _audit_log + maintain_partitions
-- (both security definer) are the only writers.
grant select on public.audit_action_code to authenticated;
grant select on public.audit_log         to authenticated;
grant select on public.audit_summary     to authenticated;

-- ---------------------------------------------------------------
-- 4. _audit_log -- the single write path.
-- ---------------------------------------------------------------

create or replace function public._audit_log(
  p_shop_id      uuid,
  p_action_code  text,
  p_entity_type  text,
  p_entity_id    uuid    default null,
  p_entity_ids   uuid[]  default null,
  p_before       jsonb   default null,
  p_after        jsonb   default null,
  p_reason       text    default null,
  p_client_op_id text    default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meta   public.audit_action_code%rowtype;
  v_source text;
  v_id     uuid;
begin
  select * into v_meta from public.audit_action_code where code = p_action_code;
  if not found then
    raise exception 'unknown audit action_code: %', p_action_code;
  end if;
  if not v_meta.is_active then
    raise exception 'audit action_code % is not active', p_action_code;
  end if;

  if v_meta.requires_reason then
    if p_reason is null or length(btrim(p_reason)) < 10 then
      raise exception 'audit action % requires a reason of at least 10 chars',
        p_action_code;
    end if;
    if length(p_reason) > 300 then
      raise exception 'audit reason capped at 300 chars (got %)', length(p_reason);
    end if;
  end if;

  -- Source resolved from a custom JWT claim set by each client SDK.
  -- Falls back to 'rpc' when no claim is present (server-internal).
  v_source := coalesce(
    nullif(current_setting('request.jwt.claim.source', true), ''),
    'rpc'
  );
  if v_source not in ('mobile','shop_admin_web','system_admin_web','rpc','system') then
    v_source := 'rpc';
  end if;

  insert into public.audit_log (
    shop_id, actor_user_id, action_code, entity_type,
    entity_id, entity_ids,
    before_state, after_state,
    reason, client_op_id, source
  ) values (
    p_shop_id,
    auth.uid(),
    p_action_code,
    p_entity_type,
    p_entity_id,
    p_entity_ids,
    case when v_meta.captures_before then p_before else null end,
    case when v_meta.captures_after  then p_after  else null end,
    case when v_meta.requires_reason then p_reason else nullif(p_reason, '') end,
    p_client_op_id,
    v_source
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public._audit_log(
  uuid, text, text, uuid, uuid[], jsonb, jsonb, text, text
) from public;
-- Only RPCs (themselves security definer) call this; authenticated
-- clients never call it directly. Grant nothing.

-- ---------------------------------------------------------------
-- 5. _audit_log_maintain_partitions -- daily cron target.
-- ---------------------------------------------------------------

create or replace function public._audit_log_maintain_partitions()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_table      text;
  v_partition  text;
  v_drop_before date := current_date - interval '90 days';
  v_create_through date := current_date + interval '60 days';
  v_month      date;
  v_count      bigint;
begin
  -- 1) Create future partitions when missing (current + 2 ahead).
  v_month := date_trunc('month', current_date);
  while v_month <= v_create_through loop
    v_partition := 'audit_log_' || to_char(v_month, 'YYYY_MM');
    if not exists (
      select 1 from pg_catalog.pg_class
       where relname = v_partition and relnamespace = 'public'::regnamespace
    ) then
      execute format(
        'create table public.%I partition of public.audit_log
         for values from (%L) to (%L)',
        v_partition,
        v_month,
        v_month + interval '1 month'
      );
    end if;
    v_month := v_month + interval '1 month';
  end loop;

  -- 2) Roll up + drop expired partitions.
  for v_partition in
    select tablename
      from pg_catalog.pg_tables
     where schemaname = 'public'
       and tablename ~ '^audit_log_\d{4}_\d{2}$'
       and to_date(substring(tablename from 'audit_log_(\d{4}_\d{2})'), 'YYYY_MM')
           < date_trunc('month', v_drop_before)
  loop
    -- The rollup INSERT runs inside the same transaction as the DROP
    -- so the data isn't lost if the drop fails.
    execute format(
      'insert into public.audit_summary
         (shop_id, day, action_code, actor_user_id, source, count)
       select shop_id,
              date_trunc(''day'', occurred_at)::date,
              action_code,
              actor_user_id,
              source,
              count(*)
         from public.%I
         group by shop_id,
                  date_trunc(''day'', occurred_at)::date,
                  action_code,
                  actor_user_id,
                  source
       on conflict (shop_id, day, action_code, actor_user_id, source)
         do update set count = public.audit_summary.count + excluded.count',
      v_partition
    );
    get diagnostics v_count = row_count;
    -- Log via NOTICE for the cron job's stdout. NOTICE is visible to
    -- pg_cron's job_run_details so we get a trail for free.
    raise notice 'audit_log: rolled up % rows from %, dropping', v_count, v_partition;
    execute format('drop table public.%I', v_partition);
  end loop;
end;
$$;

revoke all on function public._audit_log_maintain_partitions() from public;
-- Cron / Edge Function calls this with a service-role token; no
-- end-user grant.

-- ---------------------------------------------------------------
-- 6. Initial partitions.
-- ---------------------------------------------------------------

-- Materialize current + 2 future months immediately so the first
-- _audit_log call lands in a partition that exists. The maintain
-- function does the same job on its daily run.
select public._audit_log_maintain_partitions();

-- ---------------------------------------------------------------
-- 7. Capability seeds.
-- ---------------------------------------------------------------

insert into public.capability (code, label, description) values
  ('audit.view',          'View audit log',          'See who did what on this shop. Cashier baseline.'),
  ('audit.export',        'Export audit log',        'Download audit data (web-only). Owner-and-above.'),
  ('audit.view_org',      'View org-wide audit',     'Cross-shop audit feed. Org owner only.'),
  ('audit.staff_actions', 'View staff-action audit', 'See impersonation rows. Platform staff only.')
on conflict (code) do update set
  label = excluded.label,
  description = excluded.description,
  is_active = excluded.is_active;

-- Default role assignments. Cashier baseline gets audit.view so the
-- "voided by Asha 10 min ago" inline cue works. Owner gets export
-- additionally. Org owner gets the cross-shop view. Platform staff
-- get the staff-action view via system_admin_web; the org-level
-- role catalog doesn't include audit.staff_actions intentionally.

with cashier as (
  select id from public.shop_role where code = 'cashier'
), owner as (
  select id from public.shop_role where code = 'owner'
)
insert into public.shop_role_capability (role_id, capability_code)
  select (select id from cashier), 'audit.view'
  union all
  select (select id from owner), 'audit.view'
  union all
  select (select id from owner), 'audit.export'
on conflict do nothing;

with org_owner as (
  select id from public.organization_role where code = 'org_owner'
), org_admin as (
  select id from public.organization_role where code = 'org_admin'
)
insert into public.organization_role_capability (role_id, capability_code)
  select (select id from org_owner), 'audit.view'
  union all
  select (select id from org_owner), 'audit.export'
  union all
  select (select id from org_owner), 'audit.view_org'
  union all
  select (select id from org_admin), 'audit.view'
  union all
  select (select id from org_admin), 'audit.export'
on conflict do nothing;

-- ---------------------------------------------------------------
-- 8. pg_cron schedule (when available).
-- ---------------------------------------------------------------

-- Daily at 02:00 UTC. Skipped silently in environments without
-- pg_cron (e.g., the standalone test harness). Supabase managed
-- envs have pg_cron pre-installed; in fresh self-hosted setups
-- the operator enables the extension and re-runs this DO block.
do $$
begin
  if exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'audit-log-maintain',
      '0 2 * * *',
      $cmd$select public._audit_log_maintain_partitions()$cmd$
    );
  end if;
end
$$;
