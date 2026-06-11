-- ---------------------------------------------------------------------------
-- set_shop_item_unit_default_flags — flip the per-screen "default
-- packaging" markers on a shop_item_unit row. Owners + cashiers can call
-- it (matches `set_shop_item_unit_sale_price`'s permission model — same
-- role that rings a sale can train its defaults).
--
-- Each shop_item has at most one is_default_sale=true row and one
-- is_default_receive=true row at a time. Setting either flag to true
-- flips the previous holder off in the same shop_item; setting it to
-- false leaves the other rows alone (the shop_item ends up with no
-- default for that side, which is OK — the picker falls back to the
-- base packaging at runtime).
-- ---------------------------------------------------------------------------

create or replace function public.set_shop_item_unit_default_flags(
  p_shop_id            uuid,
  p_shop_item_unit_id  uuid,
  p_is_default_sale    boolean,
  p_is_default_receive boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shop_item_id uuid;
begin
  if p_shop_id is null or p_shop_item_unit_id is null then
    raise exception 'Shop id and shop_item_unit id are required';
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception
      'Not allowed to update default packaging flags for this shop';
  end if;

  select shop_item_id into v_shop_item_id
  from public.shop_item_unit
  where shop_id = p_shop_id
    and id = p_shop_item_unit_id;

  if v_shop_item_id is null then
    raise exception 'shop_item_unit not found in this shop';
  end if;

  -- Flip previous defaults off for whichever flags we're turning on.
  -- (If the flag stays false, we leave siblings untouched.)
  if p_is_default_sale then
    update public.shop_item_unit
    set is_default_sale = false,
        updated_at = pg_catalog.now()
    where shop_id = p_shop_id
      and shop_item_id = v_shop_item_id
      and id <> p_shop_item_unit_id
      and is_default_sale;
  end if;

  if p_is_default_receive then
    update public.shop_item_unit
    set is_default_receive = false,
        updated_at = pg_catalog.now()
    where shop_id = p_shop_id
      and shop_item_id = v_shop_item_id
      and id <> p_shop_item_unit_id
      and is_default_receive;
  end if;

  update public.shop_item_unit
  set is_default_sale = p_is_default_sale,
      is_default_receive = p_is_default_receive,
      updated_at = pg_catalog.now()
  where shop_id = p_shop_id
    and id = p_shop_item_unit_id;
end;
$$;

revoke all on function public.set_shop_item_unit_default_flags(
  uuid, uuid, boolean, boolean
) from public;
grant execute on function public.set_shop_item_unit_default_flags(
  uuid, uuid, boolean, boolean
) to authenticated;
