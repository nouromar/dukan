-- 0090_sync_packaging_label_base_unit.sql
--
-- Bug: a packaging shows as "50 Sack" on the mobile app instead of
-- "50 Kg Sack" — the size (which base unit the conversion is in) is lost.
--
-- Root cause: the ONLINE label builders (search_items §0019, get_shop_item
-- §0044) format packaging_label as
--     _format_conversion(conv) || ' ' || <base unit label> || ' ' || <sold label>
-- i.e. "50 Kg Sack". But the OFFLINE sync builder `_build_items_payload`
-- (last touched in §0080) omits the base unit label:
--     _format_conversion(conv) || ' ' || <sold label>   -> "50 Sack".
-- On useLocalDb shops the app reads the mirror, so it shows the shorter,
-- ambiguous form.
--
-- Fix: re-create `_build_items_payload` with the SOLE change being the
-- packaging_label expression — join the item's base unit and include its
-- label, matching the online RPCs. Apply with `supabase db push`; devices
-- must "Re-download all data" once so local shop_item_unit rows pick up the
-- corrected labels.

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

  -- Packagings — packaging_label uses public._format_conversion so whole
  -- numbers render as "14 Box" not "14.000000 Box", and now includes the
  -- item's base unit ("50 Kg Sack") to match the online search_items /
  -- get_shop_item labels.
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
                || ' ' || coalesce(bu.default_label, si.base_unit_code)
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
    join public.shop_item si
      on si.shop_id = siu.shop_id and si.id = siu.shop_item_id
    left join public.unit bu on bu.code = si.base_unit_code
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
