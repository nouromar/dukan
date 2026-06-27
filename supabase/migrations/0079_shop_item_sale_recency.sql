-- Sale recency on shop_item: last_sold_at + sale_count.
--
-- Powers "items you sell most / most recently float to the top" on the Sale
-- screen (today it's alphabetical). Maintained server-side as cached
-- projections on the item row (like current_stock) and carried in the items
-- delta, so every phone in a shop converges on the COMBINED cross-device count
-- through the item sync that already happens on each sale. The app also bumps a
-- local copy optimistically for instant feedback on its own sales.
--
-- This is the one "learning" write we keep: unlike the dead 0014 aggregates
-- (dropped in 0078), shop_item is synced and read, so the write is consumed.

-- 1. Columns (cached projections).
alter table public.shop_item
  add column if not exists last_sold_at timestamptz,
  add column if not exists sale_count   integer not null default 0;

comment on column public.shop_item.last_sold_at is
  'Cached: occurred_at of the most recent posted sale line for this item. '
  'Maintained by _bump_shop_item_sale_recency; ranks the Sale item list.';
comment on column public.shop_item.sale_count is
  'Cached: count of posted sale lines for this item (combined across a shop''s '
  'devices). Maintained by _bump_shop_item_sale_recency.';

-- 2. Bump trigger: on each posted, non-reversal SALE line, move the item's
-- recency forward and increment its count. Reversals (voids) are skipped, so a
-- void neither bumps nor decrements — sale_count is a soft ranking signal, not
-- accounting. transaction_line.item_id is the per-shop shop_item.id.
create or replace function public._bump_shop_item_sale_recency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type     text;
  v_status   text;
  v_occurred timestamptz;
  v_reverses uuid;
begin
  if new.item_id is null then
    return new;
  end if;

  select tt.code, ts.code, t.occurred_at, t.reverses_transaction_id
    into v_type, v_status, v_occurred, v_reverses
  from public.txn t
  join public.transaction_type   tt on tt.id = t.type_id
  join public.transaction_status ts on ts.id = t.status_id
  where t.shop_id = new.shop_id
    and t.id = new.transaction_id;

  if v_type <> 'sale' or v_status <> 'posted' or v_reverses is not null then
    return new;
  end if;

  update public.shop_item
     set last_sold_at = greatest(coalesce(last_sold_at, v_occurred), v_occurred),
         sale_count   = sale_count + 1,
         updated_at   = now()
   where shop_id = new.shop_id
     and id = new.item_id;

  return new;
end;
$$;

create trigger transaction_line_bump_sale_recency
after insert on public.transaction_line
for each row
execute function public._bump_shop_item_sale_recency();

-- 3. Carry the two fields in the items payload (full sync + delta both call
-- _build_items_payload). Redefinition of the 0072 body + last_sold_at_ms and
-- sale_count.
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
      extract(epoch from si.last_sold_at) * 1000 as last_sold_at_ms,
      si.sale_count,
      si.is_active,
      extract(epoch from si.updated_at) * 1000 as server_updated_at_ms
    from public.shop_item si
    where si.shop_id = p_shop_id
      and (p_since is null or si.updated_at > p_since)
      and (p_since is not null or si.is_active)  -- full_sync only active
  ) r;

  -- Packagings — packaging_label uses public._format_conversion
  -- so whole numbers render as "14 Box" not "14.000000 Box".
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_units
  from (
    select
      siu.id              as shop_item_unit_id,
      siu.shop_item_id,
      siu.unit_code,
      case when siu.conversion_to_base = 1
           then u.default_label
           else public._format_conversion(siu.conversion_to_base)
                || ' ' || u.default_label
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
