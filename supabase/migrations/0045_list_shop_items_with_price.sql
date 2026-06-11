-- Extend list_shop_items with two new fields the Phase B Products list
-- needs:
--   * default_sale_price — the sale price of the packaging marked as
--     default-for-sale (or the base packaging if none is marked),
--     null when neither has a price yet.
--   * any_price_set — true if any packaging on the shop_item has a
--     non-null sale_price. Drives the headline "N without price" count.
--
-- Also widen the search predicate so scanning a barcode into the
-- search bar resolves to the right product (matches against
-- shop_item_barcode + global item_barcode, in addition to alias text).
--
-- Signature changes — drop+recreate (return-table mutation).

drop function if exists public.list_shop_items(uuid, uuid, text, text);

create function public.list_shop_items(
  p_shop_id     uuid,
  p_category_id uuid default null,
  p_query       text default null,
  p_locale      text default 'en'
)
returns table (
  shop_item_id        uuid,
  item_id             uuid,
  display_name        text,
  category_name       text,
  base_unit_code      text,
  base_unit_label     text,
  current_stock       numeric,
  reorder_threshold   numeric,
  unit_count          int,
  is_active           boolean,
  default_sale_price  numeric,
  any_price_set       boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_locale  text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
  v_query   text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_query, '')));
  v_pattern text;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list items for this shop';
  end if;

  if v_locale = '' then
    v_locale := 'en';
  end if;
  v_pattern := v_query || '%';

  return query
  with filtered as (
    select si.id, si.item_id, si.base_unit_code, si.category_id,
           si.current_stock, si.reorder_threshold, si.is_active
    from public.shop_item si
    where si.shop_id = p_shop_id
      and (p_category_id is null or si.category_id = p_category_id)
      and (
        v_query = ''
        or exists (
          select 1 from public.shop_item_alias sia
          where sia.shop_id = p_shop_id
            and sia.shop_item_id = si.id
            and sia.is_active
            and sia.alias_text_norm like v_pattern
        )
        or exists (
          select 1 from public.item_alias ia
          where ia.item_id = si.item_id
            and ia.is_active
            and ia.alias_text_norm like v_pattern
        )
        -- Barcode match: scanning a code in the search bar lands on
        -- the right product. Match either shop-printed barcodes or
        -- inherited manufacturer barcodes (global item_barcode).
        or exists (
          select 1
          from public.shop_item_barcode sib
          join public.shop_item_unit siu
            on siu.id = sib.shop_item_unit_id
           and siu.shop_id = sib.shop_id
          where sib.shop_id = p_shop_id
            and siu.shop_item_id = si.id
            and sib.is_active
            and sib.barcode = v_query
        )
        or exists (
          select 1
          from public.item_unit iu
          join public.item_barcode ib on ib.item_unit_id = iu.id
          where iu.item_id = si.item_id
            and ib.is_active
            and ib.barcode = v_query
        )
      )
  )
  select
    f.id as shop_item_id,
    f.item_id,
    public.shop_item_display_name(f.id, v_locale) as display_name,
    (
      select public.tr(c.name, c.name_translations, v_locale)
      from public.category c
      where c.id = f.category_id
    ) as category_name,
    f.base_unit_code,
    (
      select public.tr(u.default_label, u.label_translations, v_locale)
      from public.unit u
      where u.code = f.base_unit_code
    ) as base_unit_label,
    f.current_stock,
    f.reorder_threshold,
    (
      select count(*)::int
      from public.shop_item_unit siu
      where siu.shop_id = p_shop_id
        and siu.shop_item_id = f.id
        and siu.is_active
    ) as unit_count,
    f.is_active,
    -- Default sale price: the price on the is_default_sale=true
    -- packaging, falling back to the base packaging. Null when
    -- neither has a price set.
    (
      select coalesce(
        (
          select siu.sale_price
          from public.shop_item_unit siu
          where siu.shop_id = p_shop_id
            and siu.shop_item_id = f.id
            and siu.is_active
            and siu.is_default_sale
          limit 1
        ),
        (
          select siu.sale_price
          from public.shop_item_unit siu
          where siu.shop_id = p_shop_id
            and siu.shop_item_id = f.id
            and siu.is_active
            and siu.conversion_to_base = 1
            and siu.unit_code = f.base_unit_code
          limit 1
        )
      )
    ) as default_sale_price,
    -- Any packaging priced? (drives "no-price-yet" headline + filter.)
    exists (
      select 1
      from public.shop_item_unit siu
      where siu.shop_id = p_shop_id
        and siu.shop_item_id = f.id
        and siu.is_active
        and siu.sale_price is not null
    ) as any_price_set
  from filtered f
  order by public.shop_item_display_name(f.id, v_locale) asc;
end;
$$;

revoke all on function public.list_shop_items(uuid, uuid, text, text) from public;
grant execute on function public.list_shop_items(uuid, uuid, text, text) to authenticated;
