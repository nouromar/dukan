-- 0072_full_sync_format_conversion.sql
--
-- Fix: packaging_label in `_build_items_payload` (from 0069) used
-- `(siu.conversion_to_base::text || ' ' || u.default_label)` which
-- renders `numeric(14,6)` values like "14.000000 Box" — the literal
-- Postgres text-cast of the numeric, including trailing zeros. The
-- user reported a "Bakeeri" tile showing "14.000000 Box · $..." and
-- stock "50 14.000000 Box" on the iPhone sale screen.
--
-- Every other RPC that derives a packaging_label (search_items,
-- list_item_units, get_shop_item, get_sale_lines, etc.) uses the
-- `public._format_conversion(numeric)` helper from 0028, which
-- strips trailing zeros and the decimal point for whole-number
-- conversions. 0069 missed it.
--
-- This migration re-creates `_build_items_payload` with the SOLE
-- change being the packaging_label expression. After applying via
-- `supabase db push`, devices need to trigger a fresh full sync
-- (via Storage & sync → "Re-download all data") so local
-- shop_item_unit rows pick up the corrected labels.

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
