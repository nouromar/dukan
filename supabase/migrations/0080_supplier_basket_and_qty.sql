-- Slice 3 (supplier basket) + Slice 4 (quantity chips) backend.
--
-- Slice 3: sync the EXISTING supplier_item_unit_cost projection (0007,
-- maintained by post_receive/void_receive) to mobile so the offline Receive
-- screen can surface a supplier's usual items (ranked by last_received_at). No
-- new write path — just a payload addition.
--
-- Slice 4: last_sale_qty / last_receive_qty cached on shop_item_unit, stamped
-- per posted non-reversal line by generalizing the 0079 sale-recency trigger,
-- and carried in the units payload. Powers the quantity chips (a learned
-- default the shopkeeper taps — never auto-applied).

-- 1. Quantity columns (cached projections on the packaging).
alter table public.shop_item_unit
  add column if not exists last_sale_qty    numeric(14, 3),
  add column if not exists last_receive_qty numeric(14, 3);

comment on column public.shop_item_unit.last_sale_qty is
  'Cached: quantity of the most recent posted sale line in this packaging. '
  'Maintained by _bump_shop_item_sale_recency; seeds the Sale quantity chips.';
comment on column public.shop_item_unit.last_receive_qty is
  'Cached: quantity of the most recent posted receive line in this packaging. '
  'Maintained by _bump_shop_item_sale_recency; seeds the Receive quantity chips.';

-- 2. Generalize the 0079 trigger fn: still bumps shop_item sale recency, and
-- now also stamps the packaging's last sale/receive quantity. (The trigger
-- transaction_line_bump_sale_recency stays attached; only the body changes.
-- shop_item_unit has a set_updated_at trigger, so the qty write auto-bumps
-- updated_at and rides the items delta.)
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

  if v_status <> 'posted' or v_reverses is not null then
    return new;
  end if;

  if v_type = 'sale' then
    update public.shop_item
       set last_sold_at = greatest(coalesce(last_sold_at, v_occurred), v_occurred),
           sale_count   = sale_count + 1,
           updated_at   = now()
     where shop_id = new.shop_id
       and id = new.item_id;

    if new.shop_item_unit_id is not null then
      update public.shop_item_unit
         set last_sale_qty = new.quantity
       where shop_id = new.shop_id
         and id = new.shop_item_unit_id;
    end if;
  elsif v_type = 'receive' then
    if new.shop_item_unit_id is not null then
      update public.shop_item_unit
         set last_receive_qty = new.quantity
       where shop_id = new.shop_id
         and id = new.shop_item_unit_id;
    end if;
  end if;

  return new;
end;
$$;

-- 3. Items payload: add last_sale_qty/last_receive_qty to the units array and a
-- new supplier_items array (supplier_item_unit_cost). Redefinition of the 0079
-- body with these additions; full sync + delta both call this.
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
  v_items          jsonb;
  v_units          jsonb;
  v_aliases        jsonb;
  v_barcodes       jsonb;
  v_supplier_items jsonb;
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
      siu.last_sale_qty,
      siu.last_receive_qty,
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

  -- Supplier baskets — which packagings each supplier usually brings, with the
  -- last cost. Ranked client-side by last_received_at.
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    into v_supplier_items
  from (
    select
      siuc.party_id,
      siuc.shop_id,
      siuc.shop_item_unit_id,
      siuc.last_unit_cost,
      extract(epoch from siuc.last_received_at) * 1000 as last_received_at_ms,
      extract(epoch from siuc.updated_at) * 1000       as server_updated_at_ms
    from public.supplier_item_unit_cost siuc
    where siuc.shop_id = p_shop_id
      and (p_since is null or siuc.updated_at > p_since)
  ) r;

  return jsonb_build_object(
    'items',          v_items,
    'units',          v_units,
    'aliases',        v_aliases,
    'barcodes',       v_barcodes,
    'supplier_items', v_supplier_items
  );
end;
$$;
