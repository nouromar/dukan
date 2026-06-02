-- list_item_units returns every unit configured for an item (or its
-- catalog candidate when the shop has not yet activated it). Powers
-- the unit pickers on both Receive and Sale.
--
-- After the allow_sale / allow_receive cleanup (pre-pilot), all units
-- are valid for either flow; which one is the "default" per screen is
-- decided by the item's default_sale_unit_code / default_receive_unit_code.
--
-- Either p_item_id or p_catalog_item_id must be set, not both:
--   * Activated item: query item_unit + unit for shop-specific units.
--   * Catalog candidate: query catalog_item_unit + unit + revision for
--     the unactivated catalog product's unit list.
--
-- p_screen ('sale' or 'receive') decides which default flag the picker
-- highlights. Defaults to 'receive' since Receive is the screen that
-- ships with a picker today.

create or replace function public.list_item_units(
  p_shop_id uuid,
  p_item_id uuid default null,
  p_catalog_item_id uuid default null,
  p_screen text default 'receive'
)
returns table (
  unit_id uuid,
  unit_code text,
  unit_label text,
  conversion_to_base numeric,
  is_default boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_screen text := coalesce(nullif(pg_catalog.btrim(p_screen), ''), 'receive');
  v_default_unit_code text;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list item units for this shop';
  end if;

  if v_screen not in ('sale', 'receive') then
    raise exception 'p_screen must be sale or receive (got %)', v_screen;
  end if;

  if (p_item_id is null and p_catalog_item_id is null)
    or (p_item_id is not null and p_catalog_item_id is not null) then
    raise exception 'Pass exactly one of p_item_id or p_catalog_item_id';
  end if;

  if p_item_id is not null then
    if v_screen = 'sale' then
      select u.code into v_default_unit_code
      from public.item i
      join public.unit u on u.id = i.default_sale_unit_id
      where i.id = p_item_id and i.shop_id = p_shop_id;
    else
      select u.code into v_default_unit_code
      from public.item i
      join public.unit u on u.id = i.default_receive_unit_id
      where i.id = p_item_id and i.shop_id = p_shop_id;
    end if;

    if v_default_unit_code is null then
      raise exception 'Item not found in this shop';
    end if;

    return query
    select
      u.id as unit_id,
      u.code as unit_code,
      u.default_label as unit_label,
      iu.conversion_to_base,
      (u.code = v_default_unit_code) as is_default
    from public.item_unit iu
    join public.unit u on u.id = iu.unit_id and u.is_active
    where iu.shop_id = p_shop_id
      and iu.item_id = p_item_id
    order by iu.sort_order, u.code;
  else
    if v_screen = 'sale' then
      select cir.default_sale_unit_code into v_default_unit_code
      from public.catalog_item ci
      join public.catalog_item_revision cir on cir.id = ci.current_revision_id
      where ci.id = p_catalog_item_id and ci.is_active;
    else
      select cir.default_receive_unit_code into v_default_unit_code
      from public.catalog_item ci
      join public.catalog_item_revision cir on cir.id = ci.current_revision_id
      where ci.id = p_catalog_item_id and ci.is_active;
    end if;

    if v_default_unit_code is null then
      raise exception 'Catalog item is not available';
    end if;

    return query
    select
      u.id as unit_id,
      u.code as unit_code,
      u.default_label as unit_label,
      ciu.conversion_to_base,
      (u.code = v_default_unit_code) as is_default
    from public.catalog_item ci
    join public.catalog_item_revision cir on cir.id = ci.current_revision_id
    join public.catalog_item_unit ciu
      on ciu.catalog_item_id = ci.id and ciu.revision_id = cir.id
    join public.unit u on u.code = ciu.unit_code and u.is_active
    where ci.id = p_catalog_item_id
    order by ciu.sort_order, u.code;
  end if;
end;
$$;

revoke all on function public.list_item_units(uuid, uuid, uuid, text) from public;
grant execute on function public.list_item_units(uuid, uuid, uuid, text) to authenticated;
