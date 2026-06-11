-- Patch get_shop_item — extend alias + barcode rows to carry their
-- own ids (and the barcode's owning shop_item_unit_id) so the
-- product-detail UI can remove a chip / re-primary a barcode without
-- an extra lookup. Header + units output is unchanged.
--
-- Same signature; same jsonb top-level keys. Only the inner row shapes
-- of `aliases` and `barcodes` gain fields. Existing DTOs ignore unknown
-- fields, so this is non-breaking for callers that don't opt in.

create or replace function public.get_shop_item(
  p_shop_id      uuid,
  p_shop_item_id uuid,
  p_locale       text default 'en'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_locale   text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
  v_header   jsonb;
  v_units    jsonb;
  v_aliases  jsonb;
  v_barcodes jsonb;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to view items for this shop';
  end if;

  if v_locale = '' then
    v_locale := 'en';
  end if;

  -- Header (unchanged from 0019).
  select to_jsonb(h) into v_header
  from (
    select
      si.id as shop_item_id,
      si.item_id,
      public.shop_item_display_name(si.id, v_locale) as display_name,
      (
        select public.tr(c.name, c.name_translations, v_locale)
        from public.category c
        where c.id = si.category_id
      ) as category_name,
      si.base_unit_code,
      (
        select public.tr(u.default_label, u.label_translations, v_locale)
        from public.unit u
        where u.code = si.base_unit_code
      ) as base_unit_label,
      si.current_stock,
      si.reorder_threshold,
      (
        select count(*)::int
        from public.shop_item_unit siu
        where siu.shop_id = p_shop_id
          and siu.shop_item_id = si.id
          and siu.is_active
      ) as unit_count,
      si.is_active
    from public.shop_item si
    where si.shop_id = p_shop_id and si.id = p_shop_item_id
  ) h;

  if v_header is null then
    raise exception 'shop_item % not found in shop %', p_shop_item_id, p_shop_id;
  end if;

  -- Units (unchanged from 0019).
  select coalesce(jsonb_agg(to_jsonb(u_row) order by u_row.sort_order, u_row.conversion_to_base, u_row.unit_code), '[]'::jsonb)
  into v_units
  from (
    select
      siu.id as shop_item_unit_id,
      siu.item_unit_id,
      siu.unit_code,
      public.tr(u.default_label, u.label_translations, v_locale) as unit_label,
      case
        when siu.conversion_to_base = 1 then
          public.tr(u.default_label, u.label_translations, v_locale)
        else
          public._format_conversion(siu.conversion_to_base)
          || ' '
          || coalesce(
            (
              select public.tr(bu.default_label, bu.label_translations, v_locale)
              from public.unit bu
              where bu.code = (
                select base_unit_code from public.shop_item
                where id = p_shop_item_id and shop_id = p_shop_id
              )
            ),
            ''
          )
          || ' '
          || public.tr(u.default_label, u.label_translations, v_locale)
      end as packaging_label,
      siu.conversion_to_base,
      siu.sale_price,
      siu.last_cost,
      siu.is_default_sale,
      siu.is_default_receive,
      (siu.conversion_to_base = 1) as is_base_unit,
      siu.is_active,
      siu.sort_order
    from public.shop_item_unit siu
    join public.unit u on u.code = siu.unit_code
    where siu.shop_id = p_shop_id
      and siu.shop_item_id = p_shop_item_id
  ) u_row;

  -- Aliases — now include alias_id so the UI can remove a chip.
  select coalesce(jsonb_agg(to_jsonb(a_row) order by a_row.is_display desc, a_row.alias_text), '[]'::jsonb)
  into v_aliases
  from (
    select
      sia.id as alias_id,
      sia.alias_text,
      sia.language_code,
      sia.is_display
    from public.shop_item_alias sia
    where sia.shop_id = p_shop_id
      and sia.shop_item_id = p_shop_item_id
      and sia.is_active
  ) a_row;

  -- Barcodes — now include barcode_id + shop_item_unit_id so the UI
  -- can render the chip inside the right packaging tile and address
  -- it for remove / re-primary.
  select coalesce(jsonb_agg(to_jsonb(b_row) order by b_row.is_primary desc, b_row.barcode), '[]'::jsonb)
  into v_barcodes
  from (
    select
      sib.id as barcode_id,
      sib.shop_item_unit_id,
      sib.barcode,
      sib.symbology,
      sib.is_primary
    from public.shop_item_barcode sib
    join public.shop_item_unit siu
      on siu.id = sib.shop_item_unit_id
     and siu.shop_id = sib.shop_id
    where sib.shop_id = p_shop_id
      and siu.shop_item_id = p_shop_item_id
      and sib.is_active
  ) b_row;

  return jsonb_build_object(
    'header',   v_header,
    'units',    v_units,
    'aliases',  v_aliases,
    'barcodes', v_barcodes
  );
end;
$$;
