-- Phase 1 of full offline-first architecture (#373).
-- See docs/offline-first-architecture.md for the design.
--
-- Adds:
--   * `(shop_id, updated_at)` indexes on the mutable tables that
--     get sync'd to mobile mirror tables.
--   * `shop_sync_audit` table to rate-limit `get_shop_full_sync`
--     (once per (user, shop) per 24h unless p_force=true).
--   * RPCs:
--       get_shop_full_sync       — one mega-call for first-sync
--       get_shop_items_delta     — items/units/aliases/barcodes since cutoff
--       get_parties_delta        — parties since cutoff
--       get_categories_delta     — expense + product categories since cutoff
--       get_transactions_delta   — denormalized recent txns since cutoff
--
-- Notes on what does NOT need touching:
--   * `updated_at` columns + triggers already exist on shop_item,
--     shop_item_unit, shop_item_alias, shop_item_barcode, party,
--     expense_category, category, unit — installed by their
--     respective creation migrations (see set_updated_at usage in
--     0001_extensions.sql).
--   * `txn` (transactions) is append-only by design — no
--     `updated_at` (voids are reversing entries, not in-place
--     updates). The transactions delta uses `created_at` instead.
--   * `transaction_line` is also immutable; rolled into the txn
--     payload, not synced as a separate resource.

-- ---------------------------------------------------------------------------
-- Indexes on (shop_id, updated_at) — supports delta cutoffs cheaply
-- ---------------------------------------------------------------------------

create index if not exists shop_item_shop_updated_at_idx
  on public.shop_item (shop_id, updated_at);
create index if not exists shop_item_unit_shop_updated_at_idx
  on public.shop_item_unit (shop_id, updated_at);
create index if not exists shop_item_alias_shop_updated_at_idx
  on public.shop_item_alias (shop_id, updated_at);
create index if not exists shop_item_barcode_shop_updated_at_idx
  on public.shop_item_barcode (shop_id, updated_at);
create index if not exists party_shop_updated_at_idx
  on public.party (shop_id, updated_at);
create index if not exists expense_category_shop_updated_at_idx
  on public.expense_category (shop_id, updated_at);
-- Reference data (unit, category) — global, no shop_id.
create index if not exists unit_updated_at_idx
  on public.unit (updated_at);
create index if not exists category_updated_at_idx
  on public.category (updated_at);
-- Transactions are append-only — `created_at` is the delta axis.
create index if not exists txn_shop_created_at_idx
  on public.txn (shop_id, created_at desc);


-- ---------------------------------------------------------------------------
-- shop_sync_audit — track recent sync RPC calls per (user, shop)
-- ---------------------------------------------------------------------------
-- Lets `get_shop_full_sync` rate-limit itself (once per 24h unless
-- the caller explicitly passes `p_force=true`). Also gives us a
-- diagnostic trail when devices behave strangely.

create table public.shop_sync_audit (
  id          uuid primary key default extensions.gen_random_uuid(),
  shop_id     uuid not null references public.shop(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('full', 'delta')),
  ran_at      timestamptz not null default now(),
  notes       text
);

create index shop_sync_audit_lookup_idx
  on public.shop_sync_audit (shop_id, user_id, kind, ran_at desc);

alter table public.shop_sync_audit enable row level security;

-- SELECT: members of the shop. (Used by the rate-limit lookup
-- inside the SECURITY DEFINER RPCs and for human debugging.)
create policy shop_sync_audit_select on public.shop_sync_audit
  for select to authenticated
  using (public.auth_can_access_shop(shop_id));

-- INSERT/UPDATE/DELETE: no direct client writes — only the RPCs
-- (SECURITY DEFINER, bypassing RLS for their own bookkeeping).
-- Withhold all DML by NOT defining a policy.


-- ---------------------------------------------------------------------------
-- Helper: build the items payload for a (shop_id, since_or_null)
-- ---------------------------------------------------------------------------
-- Single helper used by both full_sync and items_delta. When
-- p_since is null, returns ALL active rows. When set, returns
-- rows with updated_at > p_since (includes tombstones — rows
-- where is_active = false — so deletions propagate).

create or replace function public._build_items_payload(
  p_shop_id uuid,
  p_since   timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_items     jsonb;
  v_units     jsonb;
  v_aliases   jsonb;
  v_barcodes  jsonb;
begin
  -- Items
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_items
  from (
    select
      si.id              as shop_item_id,
      si.shop_id,
      si.item_id,
      coalesce(
        (select sa.alias_text from public.shop_item_alias sa
          where sa.shop_id = si.shop_id and sa.shop_item_id = si.id
            and sa.is_display and sa.is_active
          limit 1),
        si.id::text
      )                  as display_name,
      si.category_id,
      si.base_unit_code,
      si.current_stock,
      si.avg_cost,
      si.reorder_threshold,
      si.is_active,
      extract(epoch from si.updated_at) * 1000 as server_updated_at_ms
    from public.shop_item si
    where si.shop_id = p_shop_id
      and (p_since is null or si.updated_at > p_since)
      and (p_since is not null or si.is_active)  -- full_sync only active
  ) r;

  -- Packagings
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_units
  from (
    select
      siu.id              as shop_item_unit_id,
      siu.shop_item_id,
      siu.unit_code,
      case when siu.conversion_to_base = 1
           then u.default_label
           else (siu.conversion_to_base::text || ' ' || u.default_label)
      end                 as packaging_label,
      siu.conversion_to_base,
      siu.sale_price,
      siu.last_cost,
      siu.is_default_sale,
      siu.is_default_receive,
      siu.is_active,
      extract(epoch from siu.updated_at) * 1000 as server_updated_at_ms
    from public.shop_item_unit siu
    join public.unit u on u.code = siu.unit_code
    where siu.shop_id = p_shop_id
      and (p_since is null or siu.updated_at > p_since)
      and (p_since is not null or siu.is_active)
  ) r;

  -- Aliases (excluding the display alias which is folded into item.display_name)
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_aliases
  from (
    select
      sa.shop_item_id,
      sa.alias_text       as alias,
      sa.is_display
    from public.shop_item_alias sa
    where sa.shop_id = p_shop_id
      and (p_since is null or sa.updated_at > p_since)
      and sa.is_active
  ) r;

  -- Barcodes
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_barcodes
  from (
    select
      sib.barcode,
      sib.shop_item_unit_id,
      sib.is_primary
    from public.shop_item_barcode sib
    where sib.shop_id = p_shop_id
      and (p_since is null or sib.updated_at > p_since)
      and sib.is_active
  ) r;

  return jsonb_build_object(
    'items',    v_items,
    'units',    v_units,
    'aliases',  v_aliases,
    'barcodes', v_barcodes
  );
end;
$$;


-- ---------------------------------------------------------------------------
-- Helper: parties payload
-- ---------------------------------------------------------------------------

create or replace function public._build_parties_payload(
  p_shop_id uuid,
  p_since   timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parties jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_parties
  from (
    select
      p.id              as party_id,
      p.shop_id,
      p.name,
      p.phone,
      pt.code           as type_code,
      p.receivable,
      p.payable,
      p.is_active,
      extract(epoch from p.updated_at) * 1000 as server_updated_at_ms
    from public.party p
    join public.party_type pt on pt.id = p.type_id
    where p.shop_id = p_shop_id
      and (p_since is null or p.updated_at > p_since)
      and (p_since is not null or p.is_active)
  ) r;
  return jsonb_build_object('parties', v_parties);
end;
$$;


-- ---------------------------------------------------------------------------
-- Helper: categories payload (expense + product)
-- ---------------------------------------------------------------------------

create or replace function public._build_categories_payload(
  p_shop_id uuid,
  p_since   timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense    jsonb;
  v_categories jsonb;
  v_units      jsonb;
begin
  -- Expense categories (per-shop)
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_expense
  from (
    select
      ec.id     as category_id,
      ec.shop_id,
      ec.code,
      ec.name,
      ec.is_active
    from public.expense_category ec
    where ec.shop_id = p_shop_id
      and (p_since is null or ec.updated_at > p_since)
      and (p_since is not null or ec.is_active)
  ) r;

  -- Product categories (global; not shop-scoped)
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_categories
  from (
    select c.id, c.code, c.parent_id, c.name, c.sort_order, c.is_active
    from public.category c
    where (p_since is null or c.updated_at > p_since)
      and (p_since is not null or c.is_active)
  ) r;

  -- Units (global reference data)
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_units
  from (
    select u.code, u.default_label, u.is_active
    from public.unit u
    where (p_since is null or u.updated_at > p_since)
      and (p_since is not null or u.is_active)
  ) r;

  return jsonb_build_object(
    'expense_categories', v_expense,
    'categories',         v_categories,
    'units',              v_units
  );
end;
$$;


-- ---------------------------------------------------------------------------
-- Helper: transactions payload (recent, denormalized for display)
-- ---------------------------------------------------------------------------
-- Transactions are append-only, so `created_at` is the delta axis.
-- Each row carries the party name + payment method code + a
-- summary of lines so the mobile history screen can render
-- without a join.

create or replace function public._build_transactions_payload(
  p_shop_id uuid,
  p_since   timestamptz,
  p_limit   int
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_rows
  from (
    select
      t.id                as txn_id,
      t.shop_id,
      tt.code             as type_code,
      extract(epoch from t.occurred_at) * 1000 as occurred_at_ms,
      t.total_amount      as total,
      t.party_id,
      p.name              as party_name,
      pm.code             as payment_method_code,
      t.reverses_transaction_id is not null
                          as is_voided,
      extract(epoch from t.created_at) * 1000 as server_updated_at_ms,
      (
        select coalesce(jsonb_agg(to_jsonb(l)), '[]'::jsonb)
        from (
          select
            tl.line_no,
            tl.item_name_snapshot         as item_name,
            tl.unit_code_snapshot         as unit_code,
            tl.quantity,
            tl.line_total
          from public.transaction_line tl
          where tl.shop_id = t.shop_id
            and tl.transaction_id = t.id
          order by tl.line_no
        ) l
      )                   as lines_summary
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    left join public.party p on p.id = t.party_id
    left join public.payment_method pm on pm.id = t.payment_method_id
    where t.shop_id = p_shop_id
      and (p_since is null or t.created_at > p_since)
    order by t.created_at desc
    limit greatest(p_limit, 1)
  ) r;

  return jsonb_build_object('transactions', v_rows);
end;
$$;


-- ---------------------------------------------------------------------------
-- get_shop_full_sync
-- ---------------------------------------------------------------------------
-- Rate-limited: 24h cooldown per (user, shop) unless p_force=true.
-- Returns 30 days of recent transactions plus everything else
-- active.

create or replace function public.get_shop_full_sync(
  p_shop_id uuid,
  p_force   boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_recent   timestamptz;
  v_payload  jsonb;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to access this shop';
  end if;
  if v_uid is null then
    raise exception 'auth.uid() is null';
  end if;

  if not p_force then
    select max(ran_at) into v_recent
      from public.shop_sync_audit
     where shop_id = p_shop_id
       and user_id = v_uid
       and kind    = 'full';
    if v_recent is not null and v_recent > (now() - interval '24 hours') then
      raise exception
        'get_shop_full_sync rate-limited (last call %); pass p_force=true to override',
        v_recent;
    end if;
  end if;

  v_payload := jsonb_build_object(
    'items_payload',
      public._build_items_payload(p_shop_id, null),
    'parties_payload',
      public._build_parties_payload(p_shop_id, null),
    'categories_payload',
      public._build_categories_payload(p_shop_id, null),
    'transactions_payload',
      public._build_transactions_payload(p_shop_id, now() - interval '30 days', 500),
    'server_now_ms',
      extract(epoch from now()) * 1000
  );

  insert into public.shop_sync_audit (shop_id, user_id, kind, notes)
    values (p_shop_id, v_uid, 'full',
            case when p_force then 'forced' else null end);

  return v_payload;
end;
$$;


-- ---------------------------------------------------------------------------
-- get_shop_items_delta
-- ---------------------------------------------------------------------------

create or replace function public.get_shop_items_delta(
  p_shop_id uuid,
  p_since   timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to access this shop';
  end if;
  if p_since is null then
    raise exception 'p_since is required (use get_shop_full_sync for an initial sync)';
  end if;

  insert into public.shop_sync_audit (shop_id, user_id, kind, notes)
    values (p_shop_id, v_uid, 'delta', 'items');

  return public._build_items_payload(p_shop_id, p_since)
       || jsonb_build_object(
            'server_now_ms', extract(epoch from now()) * 1000
          );
end;
$$;


-- ---------------------------------------------------------------------------
-- get_parties_delta
-- ---------------------------------------------------------------------------

create or replace function public.get_parties_delta(
  p_shop_id uuid,
  p_since   timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to access this shop';
  end if;
  if p_since is null then
    raise exception 'p_since is required';
  end if;

  insert into public.shop_sync_audit (shop_id, user_id, kind, notes)
    values (p_shop_id, v_uid, 'delta', 'parties');

  return public._build_parties_payload(p_shop_id, p_since)
       || jsonb_build_object(
            'server_now_ms', extract(epoch from now()) * 1000
          );
end;
$$;


-- ---------------------------------------------------------------------------
-- get_categories_delta
-- ---------------------------------------------------------------------------

create or replace function public.get_categories_delta(
  p_shop_id uuid,
  p_since   timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to access this shop';
  end if;
  if p_since is null then
    raise exception 'p_since is required';
  end if;

  insert into public.shop_sync_audit (shop_id, user_id, kind, notes)
    values (p_shop_id, v_uid, 'delta', 'categories');

  return public._build_categories_payload(p_shop_id, p_since)
       || jsonb_build_object(
            'server_now_ms', extract(epoch from now()) * 1000
          );
end;
$$;


-- ---------------------------------------------------------------------------
-- get_transactions_delta
-- ---------------------------------------------------------------------------

create or replace function public.get_transactions_delta(
  p_shop_id uuid,
  p_since   timestamptz,
  p_limit   int default 200
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to access this shop';
  end if;
  if p_since is null then
    raise exception 'p_since is required';
  end if;

  insert into public.shop_sync_audit (shop_id, user_id, kind, notes)
    values (p_shop_id, v_uid, 'delta', 'transactions');

  return public._build_transactions_payload(p_shop_id, p_since, p_limit)
       || jsonb_build_object(
            'server_now_ms', extract(epoch from now()) * 1000
          );
end;
$$;


-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke all on function public._build_items_payload(uuid, timestamptz) from public;
revoke all on function public._build_parties_payload(uuid, timestamptz) from public;
revoke all on function public._build_categories_payload(uuid, timestamptz) from public;
revoke all on function public._build_transactions_payload(uuid, timestamptz, int) from public;
revoke all on function public.get_shop_full_sync(uuid, boolean) from public;
revoke all on function public.get_shop_items_delta(uuid, timestamptz) from public;
revoke all on function public.get_parties_delta(uuid, timestamptz) from public;
revoke all on function public.get_categories_delta(uuid, timestamptz) from public;
revoke all on function public.get_transactions_delta(uuid, timestamptz, int) from public;

-- Public-facing RPCs are authenticated-only. The _build helpers
-- are not exposed (they're called by the public RPCs).
grant execute on function public.get_shop_full_sync(uuid, boolean)
  to authenticated;
grant execute on function public.get_shop_items_delta(uuid, timestamptz)
  to authenticated;
grant execute on function public.get_parties_delta(uuid, timestamptz)
  to authenticated;
grant execute on function public.get_categories_delta(uuid, timestamptz)
  to authenticated;
grant execute on function public.get_transactions_delta(uuid, timestamptz, int)
  to authenticated;
