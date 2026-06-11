-- list_product_velocity — Top movers report (Phase C of the products
-- redesign). One RPC, two segments:
--
--   * top    — top-selling products in the period, sorted by base
--              units sold DESC, capped at p_limit. Each row: shop_item
--              id + name, total base-unit quantity, revenue (sum of
--              line_total minus voided), sales_count (distinct txns).
--   * dead   — active products with positive current_stock and zero
--              sales in the period. Sorted by display name. The hint
--              for "this is sitting on the shelf".
--
-- Voided sales are netted out via reverses_transaction_id: a reversal
-- inserts a negative line_total + a negative base_quantity for the
-- same shop_item, so summing the raw rows would already be
-- self-cancelling. We subtract the originals' contributions
-- explicitly to be safe regardless of how a future void RPC writes
-- its reversal.

create or replace function public.list_product_velocity(
  p_shop_id     uuid,
  p_period_days int   default 7,
  p_limit       int   default 10,
  p_locale      text  default 'en'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_locale     text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
  v_since      timestamptz;
  v_top        jsonb;
  v_dead       jsonb;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to read this shop';
  end if;
  if v_locale = '' then v_locale := 'en'; end if;
  if p_period_days <= 0 then
    raise exception 'period_days must be > 0';
  end if;
  v_since := pg_catalog.now() - (p_period_days || ' days')::interval;

  -- Aggregate sale-line quantities per shop_item, excluding lines on
  -- voided originals (their reversal would cancel them anyway, but
  -- excluding the original keeps the count clean too).
  with sale_lines as (
    select
      tl.item_id              as shop_item_id,
      tl.base_quantity,
      tl.line_total,
      tl.transaction_id
    from public.transaction_line tl
    join public.txn t
      on t.shop_id = tl.shop_id and t.id = tl.transaction_id
    join public.transaction_type tt on tt.id = t.type_id
    where tl.shop_id = p_shop_id
      and tt.code = 'sale'
      and t.reverses_transaction_id is null   -- exclude reversals
      and t.occurred_at >= v_since
      and not exists (
        select 1 from public.txn rev
        where rev.shop_id = t.shop_id
          and rev.reverses_transaction_id = t.id
      )
      and tl.item_id is not null
  ),
  agg as (
    select
      shop_item_id,
      sum(base_quantity)             as units_sold_base,
      sum(line_total)                as revenue,
      count(distinct transaction_id) as sales_count
    from sale_lines
    group by shop_item_id
  )
  select coalesce(
    jsonb_agg(
      to_jsonb(t_row)
      order by t_row.units_sold_base desc nulls last,
               t_row.display_name asc
    ),
    '[]'::jsonb
  )
  into v_top
  from (
    select
      si.id              as shop_item_id,
      public.shop_item_display_name(si.id, v_locale) as display_name,
      si.base_unit_code,
      public.tr(u.default_label, u.label_translations, v_locale)
                         as base_unit_label,
      a.units_sold_base,
      a.revenue,
      a.sales_count
    from agg a
    join public.shop_item si on si.id = a.shop_item_id
    join public.unit u on u.code = si.base_unit_code
    where si.shop_id = p_shop_id
    order by a.units_sold_base desc nulls last
    limit greatest(p_limit, 1)
  ) t_row;

  -- Dead-stock: active items with stock on hand and no sale rows in
  -- the period. Capped at p_limit too so the response stays small.
  select coalesce(
    jsonb_agg(
      to_jsonb(d_row)
      order by d_row.current_stock desc, d_row.display_name asc
    ),
    '[]'::jsonb
  )
  into v_dead
  from (
    select
      si.id              as shop_item_id,
      public.shop_item_display_name(si.id, v_locale) as display_name,
      si.base_unit_code,
      public.tr(u.default_label, u.label_translations, v_locale)
                         as base_unit_label,
      si.current_stock
    from public.shop_item si
    join public.unit u on u.code = si.base_unit_code
    where si.shop_id = p_shop_id
      and si.is_active
      and si.current_stock > 0
      and not exists (
        select 1
        from public.transaction_line tl
        join public.txn t on t.shop_id = tl.shop_id and t.id = tl.transaction_id
        join public.transaction_type tt on tt.id = t.type_id
        where tl.shop_id = p_shop_id
          and tt.code = 'sale'
          and tl.item_id = si.id
          and t.reverses_transaction_id is null
          and t.occurred_at >= v_since
      )
    limit greatest(p_limit, 1)
  ) d_row;

  return jsonb_build_object('top', v_top, 'dead', v_dead);
end;
$$;

revoke all on function public.list_product_velocity(uuid, int, int, text) from public;
grant execute on function public.list_product_velocity(uuid, int, int, text) to authenticated;
