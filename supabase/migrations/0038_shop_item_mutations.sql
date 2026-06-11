-- Two owner-only mutations the Settings-tile shop_item editor needs:
--
--   1. set_shop_item_category — change (or clear) the category on an
--      existing shop_item. Safe to call repeatedly; null clears.
--
--   2. deactivate_shop_item_unit — soft-delete a packaging by flipping
--      its is_active flag. Refuses on the base packaging (you can't
--      remove the unit the stock is denominated in) and auto-clears
--      any default flags so the shop_item doesn't end up pointing at
--      an inactive default.
--
-- Both go through auth_can_post_shop (owner privilege; cashier denied).

-- ---- set_shop_item_category ------------------------------------------------

create or replace function public.set_shop_item_category(
  p_shop_id      uuid,
  p_shop_item_id uuid,
  p_category_id  uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit this shop';
  end if;

  -- Validate the category exists (only when non-null). NULL is a
  -- legitimate state meaning "uncategorised".
  if p_category_id is not null then
    if not exists (
      select 1 from public.category where id = p_category_id and is_active
    ) then
      raise exception 'Unknown category';
    end if;
  end if;

  update public.shop_item
     set category_id = p_category_id,
         updated_at  = now()
   where shop_id = p_shop_id
     and id      = p_shop_item_id;

  if not found then
    raise exception 'Shop item not found in this shop';
  end if;
end;
$$;

revoke all on function public.set_shop_item_category(uuid, uuid, uuid) from public;
grant execute on function public.set_shop_item_category(uuid, uuid, uuid) to authenticated;

-- ---- deactivate_shop_item_unit ---------------------------------------------

create or replace function public.deactivate_shop_item_unit(
  p_shop_id           uuid,
  p_shop_item_unit_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_base          boolean;
  v_already_inactive boolean;
  v_found            boolean := false;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit this shop';
  end if;

  -- Locate the packaging + decide whether it's the structural base
  -- (conversion=1 AND unit_code matches shop_item.base_unit_code).
  select true,
         (siu.conversion_to_base = 1
            and siu.unit_code = si.base_unit_code),
         (not siu.is_active)
    into v_found, v_is_base, v_already_inactive
    from public.shop_item_unit siu
    join public.shop_item si on si.id = siu.shop_item_id
   where siu.shop_id = p_shop_id
     and siu.id      = p_shop_item_unit_id;

  if not v_found then
    raise exception 'Packaging not found in this shop';
  end if;
  if v_is_base then
    raise exception 'Cannot remove the base packaging';
  end if;
  if v_already_inactive then
    return;  -- idempotent: already deactivated
  end if;

  update public.shop_item_unit
     set is_active          = false,
         is_default_sale    = false,
         is_default_receive = false,
         updated_at         = now()
   where shop_id = p_shop_id
     and id      = p_shop_item_unit_id;
end;
$$;

revoke all on function public.deactivate_shop_item_unit(uuid, uuid) from public;
grant execute on function public.deactivate_shop_item_unit(uuid, uuid) to authenticated;
