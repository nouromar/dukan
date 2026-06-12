-- ---------------------------------------------------------------------------
-- Per-item low-stock threshold setter.
-- ---------------------------------------------------------------------------
--
-- `shop_item.reorder_threshold` already exists (since 0007) and is surfaced
-- by `search_items`, `list_shop_items`, and `get_shop_item` (extended in
-- 0019). The mobile + portal product tiles render a color-coded warning
-- whenever `current_stock <= reorder_threshold` (or < 1 when null) — no
-- per-shop toggle, no per-sale toast.
--
-- This migration provides the sanctioned writer so cashiers and owners
-- can adjust thresholds without touching the column directly. Null
-- clears the threshold; passing a negative value is rejected.

-- ---------------------------------------------------------------------------
-- set_shop_item_reorder_threshold — owner or cashier can adjust the
-- warning threshold. Null clears it (no per-item warning beyond the
-- shop-wide "below 1" fallback).
-- ---------------------------------------------------------------------------

create or replace function public.set_shop_item_reorder_threshold(
  p_shop_id          uuid,
  p_shop_item_id     uuid,
  p_reorder_threshold numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if p_shop_id is null or p_shop_item_id is null then
    raise exception 'Shop id and shop_item id are required';
  end if;

  if p_reorder_threshold is not null and p_reorder_threshold < 0 then
    raise exception 'Reorder threshold cannot be negative';
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to update reorder threshold for this shop';
  end if;

  update public.shop_item
  set reorder_threshold = p_reorder_threshold,
      updated_at = pg_catalog.now()
  where shop_id = p_shop_id
    and id = p_shop_item_id;

  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'shop_item not found in this shop';
  end if;
end;
$$;

revoke all on function public.set_shop_item_reorder_threshold(uuid, uuid, numeric) from public;
grant execute on function public.set_shop_item_reorder_threshold(uuid, uuid, numeric) to authenticated;
