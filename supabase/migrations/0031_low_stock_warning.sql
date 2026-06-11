-- ---------------------------------------------------------------------------
-- Low-stock warning configuration.
-- ---------------------------------------------------------------------------
--
-- Two pieces:
--   1. `shop.low_stock_warning_enabled` — per-shop toggle (default off).
--      When false, the Sale screen skips its post-sale stock probe and
--      the cashier sees no "running low" toasts.
--   2. `set_shop_item_reorder_threshold(shop_id, shop_item_id, threshold)`
--      — sanctioned writer for `shop_item.reorder_threshold` (already a
--      column, see 0007). Threshold is in base units; null clears it.
--
-- The shop_item.reorder_threshold column itself already exists since
-- 0007. The 4 read RPCs (search_items, list_shop_items, get_shop_item,
-- get_shop_item_stocks) were extended in-place in 0019 to surface it.
-- This migration adds the missing shop toggle and the per-item setter
-- so the Flutter side can drive both ends of the feature.

alter table public.shop
  add column if not exists low_stock_warning_enabled boolean not null default false;

comment on column public.shop.low_stock_warning_enabled is
  'Default off. When true, Sale screen probes post-sale stocks and toasts items at or below their reorder_threshold (or below 1 if no threshold set).';

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
