-- Followup to 0065: the onboarding form needs cashiers (not just
-- owners) to be able to attach a photo to a freshly-created shop_item.
-- shop_item's UPDATE policy is auth_can_manage_shop_setup (owner +
-- org-level), so a direct PostgREST update is owner-only. This RPC
-- mirrors the sibling pattern (set_shop_item_category /
-- set_shop_item_reorder_threshold) but gates on auth_can_post_shop so
-- cashier-driven onboarding works.
--
-- The client uploads the file to shop-item-images first (Storage policy
-- gates on auth_can_post_shop too), then calls this RPC with the
-- resulting path. Passing null clears the link (the orphan file in
-- Storage is left for back-office cleanup in v1).

create or replace function public.set_shop_item_image_path(
  p_shop_id      uuid,
  p_shop_item_id uuid,
  p_image_path   text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_found boolean;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to edit this shop';
  end if;

  -- If non-null, the path MUST conform to the bucket's shape. Reusing
  -- the bucket helper avoids a separate regex here.
  if p_image_path is not null then
    if public.storage_object_shop_item_image_shop_id(p_image_path) <> p_shop_id then
      raise exception 'image_path does not match this shop';
    end if;
  end if;

  update public.shop_item
     set image_path = p_image_path,
         updated_at = pg_catalog.now()
   where shop_id = p_shop_id
     and id      = p_shop_item_id
   returning true into v_found;

  if not v_found then
    raise exception 'Shop item not found in this shop';
  end if;
end;
$$;

revoke all on function public.set_shop_item_image_path(uuid, uuid, text) from public;
grant execute on function public.set_shop_item_image_path(uuid, uuid, text) to authenticated;
