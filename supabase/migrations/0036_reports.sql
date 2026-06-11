-- ---------------------------------------------------------------------------
-- v1 dashboard + 3 reports.
--
-- All four are SECURITY DEFINER, stable, read-only. RLS access is gated
-- by `auth_can_access_shop`.
--
--   get_today_summary(shop_id, locale)
--     → { sales_today, receivables_total, payables_total, low_stock_count }
--
--   list_receivables(shop_id, locale)
--     → rows of (party_id, name, phone, receivable) where receivable > 0
--
--   list_payables(shop_id, locale)
--     → rows of (party_id, name, phone, payable) where payable > 0
--
--   list_low_stock(shop_id, locale)
--     → rows of (shop_item_id, display_name, current_stock,
--                base_unit_label, reorder_threshold) where stock < 1
--       OR (threshold IS NOT NULL AND stock <= threshold)
-- ---------------------------------------------------------------------------

-- get_today_summary -----------------------------------------------------------
create or replace function public.get_today_summary(
  p_shop_id uuid,
  p_locale  text default 'en'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_today_start timestamptz;
  v_sales_today numeric;
  v_receivables numeric;
  v_payables    numeric;
  v_low_count   int;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to read this shop';
  end if;

  -- "Today" in the shop's configured timezone. Falls back to UTC if
  -- shop.timezone is null (shouldn't happen in v1; column is NOT NULL).
  select pg_catalog.date_trunc(
    'day',
    pg_catalog.timezone(s.timezone, pg_catalog.now())
  ) at time zone s.timezone
  into v_today_start
  from public.shop s
  where s.id = p_shop_id;

  -- Sales total for today, excluding voids (a voided sale has a
  -- matching reverse-of row that we subtract from the gross — same
  -- pattern history uses).
  select coalesce(sum(t.total_amount), 0)
  into v_sales_today
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  where t.shop_id = p_shop_id
    and tt.code = 'sale'
    and t.occurred_at >= v_today_start
    and t.reverses_transaction_id is null
    and not exists (
      select 1 from public.txn rev
      where rev.reverses_transaction_id = t.id
    );

  select coalesce(sum(receivable), 0)
  into v_receivables
  from public.party
  where shop_id = p_shop_id and is_active and receivable > 0;

  select coalesce(sum(payable), 0)
  into v_payables
  from public.party
  where shop_id = p_shop_id and is_active and payable > 0;

  select count(*)::int
  into v_low_count
  from public.shop_item si
  where si.shop_id = p_shop_id
    and si.is_active
    and (
      si.current_stock < 1
      or (si.reorder_threshold is not null
          and si.current_stock <= si.reorder_threshold)
    );

  return jsonb_build_object(
    'sales_today', v_sales_today,
    'receivables_total', v_receivables,
    'payables_total', v_payables,
    'low_stock_count', v_low_count
  );
end;
$$;

revoke all on function public.get_today_summary(uuid, text) from public;
grant execute on function public.get_today_summary(uuid, text) to authenticated;

-- list_receivables ------------------------------------------------------------
create or replace function public.list_receivables(
  p_shop_id uuid,
  p_locale  text default 'en'
)
returns table (
  party_id   uuid,
  name       text,
  phone      text,
  receivable numeric
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to read this shop';
  end if;
  return query
  select p.id, p.name, p.phone, p.receivable
  from public.party p
  where p.shop_id = p_shop_id
    and p.is_active
    and p.receivable > 0
  order by p.receivable desc, p.name asc;
end;
$$;

revoke all on function public.list_receivables(uuid, text) from public;
grant execute on function public.list_receivables(uuid, text) to authenticated;

-- list_payables ---------------------------------------------------------------
create or replace function public.list_payables(
  p_shop_id uuid,
  p_locale  text default 'en'
)
returns table (
  party_id uuid,
  name     text,
  phone    text,
  payable  numeric
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to read this shop';
  end if;
  return query
  select p.id, p.name, p.phone, p.payable
  from public.party p
  where p.shop_id = p_shop_id
    and p.is_active
    and p.payable > 0
  order by p.payable desc, p.name asc;
end;
$$;

revoke all on function public.list_payables(uuid, text) from public;
grant execute on function public.list_payables(uuid, text) to authenticated;

-- list_low_stock --------------------------------------------------------------
create or replace function public.list_low_stock(
  p_shop_id uuid,
  p_locale  text default 'en'
)
returns table (
  shop_item_id      uuid,
  display_name      text,
  current_stock     numeric,
  reorder_threshold numeric,
  base_unit_code    text,
  base_unit_label   text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_locale text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to read this shop';
  end if;
  if v_locale = '' then
    v_locale := 'en';
  end if;
  return query
  select
    si.id,
    public.shop_item_display_name(si.id, v_locale) as display_name,
    si.current_stock,
    si.reorder_threshold,
    si.base_unit_code,
    public.tr(u.default_label, u.label_translations, v_locale) as base_unit_label
  from public.shop_item si
  join public.unit u on u.code = si.base_unit_code
  where si.shop_id = p_shop_id
    and si.is_active
    and (
      si.current_stock < 1
      or (si.reorder_threshold is not null
          and si.current_stock <= si.reorder_threshold)
    )
  order by si.current_stock asc, public.shop_item_display_name(si.id, v_locale)
    asc;
end;
$$;

revoke all on function public.list_low_stock(uuid, text) from public;
grant execute on function public.list_low_stock(uuid, text) to authenticated;
