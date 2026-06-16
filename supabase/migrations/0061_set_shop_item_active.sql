-- 0061_set_shop_item_active.sql
--
-- Lets the portal toggle shop_item.is_active so an owner can retire
-- a product without deleting it. Parallels deactivate_shop_item_unit
-- (which handles a single packaging row) but at the parent level.
--
-- Gated by the same capability as the other shop_item edits
-- (inventory.product.edit). Audit-logged with action
-- inventory.product.edit and a before/after payload.

create or replace function public.set_shop_item_active(
  p_shop_id        uuid,
  p_shop_item_id   uuid,
  p_is_active      boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before  jsonb;
begin
  if p_shop_id is null or p_shop_item_id is null then
    raise exception 'shop_id and shop_item_id are required';
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit products for this shop';
  end if;

  select pg_catalog.jsonb_build_object('is_active', is_active)
  into v_before
  from public.shop_item
  where shop_id = p_shop_id and id = p_shop_item_id;

  if v_before is null then
    raise exception 'shop_item not found in this shop';
  end if;

  update public.shop_item
  set is_active = p_is_active,
      updated_at = pg_catalog.now()
  where shop_id = p_shop_id and id = p_shop_item_id;

  perform public._audit_log(
    p_shop_id     => p_shop_id,
    p_action_code => 'inventory.product.edit',
    p_entity_type => 'shop_item',
    p_entity_id   => p_shop_item_id,
    p_before      => v_before,
    p_after       => pg_catalog.jsonb_build_object(
      'is_active', p_is_active
    )
  );
end;
$$;

revoke all on function public.set_shop_item_active(uuid, uuid, boolean) from public;
grant execute on function public.set_shop_item_active(uuid, uuid, boolean) to authenticated;
