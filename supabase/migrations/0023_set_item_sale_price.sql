-- ---------------------------------------------------------------------------
-- set_shop_item_unit_sale_price — write a cashier-entered price back to the
-- packaging row so the next tap on the same tile fast-adds at the new price
-- instead of re-prompting via the priceRequired editor.
-- ---------------------------------------------------------------------------
--
-- v2 rename: pricing now lives per-packaging (`shop_item_unit.sale_price`)
-- instead of per-item, so the function signature shifts from
-- `set_item_sale_price(shop_id, item_id, price)` to
-- `set_shop_item_unit_sale_price(shop_id, shop_item_unit_id, price)`. The
-- old function is dropped so callers fail fast at deploy time.
--
-- Permission: owner or cashier (auth_can_post_shop). Same role that can
-- ring a sale can train its default price — mirrors the haggle-driven
-- reality of small-shop pricing.
--
-- NULL price IS allowed (it "un-prices" the packaging, causing the
-- priceRequired editor to re-fire on next use). Non-null prices must
-- be >= 0. Idempotent: repeated calls with the same value are no-ops at
-- the data level.

drop function if exists public.set_item_sale_price(uuid, uuid, numeric);

create or replace function public.set_shop_item_unit_sale_price(
  p_shop_id           uuid,
  p_shop_item_unit_id uuid,
  p_sale_price        numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if p_shop_id is null or p_shop_item_unit_id is null then
    raise exception 'Shop id and shop_item_unit id are required';
  end if;

  if p_sale_price is not null and p_sale_price < 0 then
    raise exception 'Sale price cannot be negative';
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to update item prices for this shop';
  end if;

  update public.shop_item_unit
  set sale_price = p_sale_price,
      updated_at = pg_catalog.now()
  where shop_id = p_shop_id
    and id = p_shop_item_unit_id;

  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'shop_item_unit not found in this shop';
  end if;
end;
$$;

revoke all on function public.set_shop_item_unit_sale_price(uuid, uuid, numeric) from public;
grant execute on function public.set_shop_item_unit_sale_price(uuid, uuid, numeric) to authenticated;
