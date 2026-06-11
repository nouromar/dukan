-- ---------------------------------------------------------------------------
-- list_shop_item_units — list every packaging the shop has on a shop_item.
-- ---------------------------------------------------------------------------
--
-- Powers the unit pickers on Receive and Sale. Under the v2 schema there
-- is no "catalog candidate" branch — by the time a packaging is being
-- shown in a picker, the shop_item has been activated (or created
-- locally) by ensure_shop_item / create_shop_item. The picker therefore
-- only ever needs to walk shop_item_unit.
--
-- p_screen ('sale' | 'receive') controls only the sort order: the
-- screen's default packaging floats to the top so the cashier can
-- confirm-without-looking. Same rows either way.
--
-- Returns one row per packaging:
--   packaging_label is the same derived label search_items emits
--   ("25 kg bag" / "kg"), so picker tiles and search tiles stay
--   visually consistent.
--   is_base_unit is derived from (conversion_to_base = 1), which the
--   partial-unique index in 0007 guarantees is unique per shop_item.

drop function if exists public.list_item_units(uuid, uuid, uuid, text);

create or replace function public.list_shop_item_units(
  p_shop_id      uuid,
  p_shop_item_id uuid,
  p_screen       text default 'sale'
)
returns table (
  shop_item_unit_id   uuid,
  unit_code           text,
  unit_label          text,
  conversion_to_base  numeric,
  packaging_label     text,
  sale_price          numeric,
  last_cost           numeric,
  is_default_sale     boolean,
  is_default_receive  boolean,
  is_base_unit        boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_screen         text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_screen, 'sale')));
  v_locale         text := 'en';
  v_base_unit_code text;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list packagings for this shop';
  end if;

  if v_screen not in ('sale', 'receive') then
    raise exception 'p_screen must be sale or receive (got %)', v_screen;
  end if;

  select si.base_unit_code into v_base_unit_code
  from public.shop_item si
  where si.id = p_shop_item_id and si.shop_id = p_shop_id;
  if v_base_unit_code is null then
    raise exception 'shop_item % not found in shop %', p_shop_item_id, p_shop_id;
  end if;

  return query
  select
    siu.id as shop_item_unit_id,
    siu.unit_code,
    public.tr(u.default_label, u.label_translations, v_locale) as unit_label,
    siu.conversion_to_base,
    case
      when siu.conversion_to_base = 1 then
        public.tr(u.default_label, u.label_translations, v_locale)
      else
        pg_catalog.rtrim(pg_catalog.rtrim(siu.conversion_to_base::text, '0'), '.')
        || ' '
        || coalesce(
          (
            select public.tr(bu.default_label, bu.label_translations, v_locale)
            from public.unit bu where bu.code = v_base_unit_code
          ),
          v_base_unit_code
        )
        || ' '
        || public.tr(u.default_label, u.label_translations, v_locale)
    end as packaging_label,
    siu.sale_price,
    siu.last_cost,
    siu.is_default_sale,
    siu.is_default_receive,
    (siu.conversion_to_base = 1) as is_base_unit
  from public.shop_item_unit siu
  join public.unit u on u.code = siu.unit_code
  where siu.shop_id = p_shop_id
    and siu.shop_item_id = p_shop_item_id
    and siu.is_active
  order by
    case
      when v_screen = 'sale'    and siu.is_default_sale    then 0
      when v_screen = 'receive' and siu.is_default_receive then 0
      else 1
    end,
    siu.sort_order asc,
    siu.conversion_to_base asc,
    siu.unit_code asc;
end;
$$;

revoke all on function public.list_shop_item_units(uuid, uuid, text) from public;
grant execute on function public.list_shop_item_units(uuid, uuid, text) to authenticated;
