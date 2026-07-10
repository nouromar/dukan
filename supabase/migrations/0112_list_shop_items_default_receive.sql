-- list_shop_items gains default_receive_packaging_label +
-- default_receive_conversion so the mobile Products list can render
-- current_stock in the packaging the shop *restocks* in (the default
-- receive unit) instead of the raw base unit — matching the product
-- detail screen's stock readout.
--
-- Resolution mirrors default_sale_pack: the packaging flagged
-- is_default_receive, else the base packaging (conversion = 1). We only
-- surface a label/conversion when that packaging is NOT the base unit —
-- a base-only item stays null so the client renders plain "12 kg". The
-- label is built the same way every other RPC does it
-- (_format_conversion(conv) || ' ' || unit_label) so it strips cleanly
-- in formatCompoundStock.

drop function if exists public.list_shop_items(uuid, uuid, text, text);

create function public.list_shop_items(
  p_shop_id     uuid,
  p_category_id uuid default null,
  p_query       text default null,
  p_locale      text default 'en'
)
returns table (
  shop_item_id                     uuid,
  item_id                          uuid,
  display_name                     text,
  category_name                    text,
  base_unit_code                   text,
  base_unit_label                  text,
  current_stock                    numeric,
  reorder_threshold                numeric,
  unit_count                       int,
  is_active                        boolean,
  default_sale_price               numeric,
  default_sale_cost                numeric,
  any_price_set                    boolean,
  default_receive_packaging_label  text,
  default_receive_conversion       numeric
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
           si.current_stock, si.reorder_threshold, si.is_active,
           si.avg_cost
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
  ),
  default_pack as (
    -- Resolve the default sale packaging per shop_item: the one
    -- flagged is_default_sale, or fall back to the base packaging.
    select
      f.id as shop_item_id,
      coalesce(
        (
          select siu.id
          from public.shop_item_unit siu
          where siu.shop_id = p_shop_id
            and siu.shop_item_id = f.id
            and siu.is_active
            and siu.is_default_sale
          limit 1
        ),
        (
          select siu.id
          from public.shop_item_unit siu
          where siu.shop_id = p_shop_id
            and siu.shop_item_id = f.id
            and siu.is_active
            and siu.conversion_to_base = 1
            and siu.unit_code = f.base_unit_code
          limit 1
        )
      ) as shop_item_unit_id
    from filtered f
  ),
  default_receive_pack as (
    -- Resolve the default *receive* packaging per shop_item: the one
    -- flagged is_default_receive, or fall back to the base packaging.
    select
      f.id as shop_item_id,
      coalesce(
        (
          select siu.id
          from public.shop_item_unit siu
          where siu.shop_id = p_shop_id
            and siu.shop_item_id = f.id
            and siu.is_active
            and siu.is_default_receive
          limit 1
        ),
        (
          select siu.id
          from public.shop_item_unit siu
          where siu.shop_id = p_shop_id
            and siu.shop_item_id = f.id
            and siu.is_active
            and siu.conversion_to_base = 1
            and siu.unit_code = f.base_unit_code
          limit 1
        )
      ) as shop_item_unit_id
    from filtered f
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
    (
      select siu.sale_price
      from public.shop_item_unit siu
      join default_pack dp on dp.shop_item_unit_id = siu.id
      where dp.shop_item_id = f.id
    ) as default_sale_price,
    (
      select pg_catalog.round(f.avg_cost * siu.conversion_to_base, 4)
      from public.shop_item_unit siu
      join default_pack dp on dp.shop_item_unit_id = siu.id
      where dp.shop_item_id = f.id
    ) as default_sale_cost,
    exists (
      select 1
      from public.shop_item_unit siu
      where siu.shop_id = p_shop_id
        and siu.shop_item_id = f.id
        and siu.is_active
        and siu.sale_price is not null
    ) as any_price_set,
    (
      -- Null for base-only items (conversion = 1) so the client renders
      -- plain base stock; else "50 kg"-style label the formatter strips.
      select case
               when siu.conversion_to_base = 1 then null
               else public._format_conversion(siu.conversion_to_base)
                    || ' '
                    || (
                         select public.tr(u.default_label,
                                          u.label_translations, v_locale)
                         from public.unit u
                         where u.code = siu.unit_code
                       )
             end
      from public.shop_item_unit siu
      join default_receive_pack drp on drp.shop_item_unit_id = siu.id
      where drp.shop_item_id = f.id
    ) as default_receive_packaging_label,
    (
      select case when siu.conversion_to_base = 1 then null
                  else siu.conversion_to_base end
      from public.shop_item_unit siu
      join default_receive_pack drp on drp.shop_item_unit_id = siu.id
      where drp.shop_item_id = f.id
    ) as default_receive_conversion
  from filtered f
  order by public.shop_item_display_name(f.id, v_locale) asc;
end;
$$;

revoke all on function public.list_shop_items(uuid, uuid, text, text) from public;
grant execute on function public.list_shop_items(uuid, uuid, text, text) to authenticated;
