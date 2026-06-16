-- Packaging removal that does the right thing automatically:
--   * if no sale or receive line has ever referenced this packaging
--     it is hard-deleted (cascades to shop_item_barcode and
--     supplier_item_unit_cost — both declared `on delete cascade`).
--   * otherwise it is soft-deactivated (is_active=false + default
--     flags cleared) so the historical transaction lines keep a valid
--     FK target.
--
-- The base packaging is always refused; the stock is denominated in
-- it. Owner-only (auth_can_post_shop). Returns 'removed' or
-- 'disabled' so the caller can show an accurate confirmation.
--
-- The older deactivate_shop_item_unit RPC stays in place — the mobile
-- app still calls it directly and its "always soft-delete" semantic
-- is a valid subset of the new behaviour.

create or replace function public.remove_or_disable_shop_item_unit(
  p_shop_id           uuid,
  p_shop_item_unit_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_found    boolean := false;
  v_is_base  boolean;
  v_has_refs boolean;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit this shop';
  end if;

  select true,
         (siu.conversion_to_base = 1
            and siu.unit_code = si.base_unit_code)
    into v_found, v_is_base
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

  select exists (
    select 1
      from public.transaction_line
     where shop_id           = p_shop_id
       and shop_item_unit_id = p_shop_item_unit_id
  ) into v_has_refs;

  if v_has_refs then
    update public.shop_item_unit
       set is_active          = false,
           is_default_sale    = false,
           is_default_receive = false,
           updated_at         = now()
     where shop_id = p_shop_id
       and id      = p_shop_item_unit_id;
    return 'disabled';
  end if;

  delete from public.shop_item_unit
   where shop_id = p_shop_id
     and id      = p_shop_item_unit_id;
  return 'removed';
end;
$$;

revoke all on function public.remove_or_disable_shop_item_unit(uuid, uuid) from public;
grant execute on function public.remove_or_disable_shop_item_unit(uuid, uuid) to authenticated;
