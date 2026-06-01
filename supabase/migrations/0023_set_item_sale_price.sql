-- Cashier-driven price seeding for items entered via the Sale line
-- editor. When the cashier confirms a sale line whose unit price came
-- out of the long-press / no-price editor, the Sale screen calls this
-- RPC to write the entered price back to item.sale_price so future taps
-- on the same tile fast-add at the new price instead of re-prompting.
--
-- Permission: owner or cashier (auth_can_post_shop). The same role that
-- can ring through a sale can also update the item's default price as a
-- by-product — that mirrors the daily reality of haggle-driven price
-- updates in small shops. The Products admin screen (future) will give
-- owners a non-Sale way to manage prices.
--
-- Behavior: unconditional update of public.item.sale_price. Long-press
-- price overrides therefore become the new default for future sales —
-- the cashier "trains" the price via the editor. If a one-off override
-- is needed without sticking, the cashier would long-press again to
-- restore the previous price.

create or replace function public.set_item_sale_price(
  p_shop_id uuid,
  p_item_id uuid,
  p_sale_price numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if p_shop_id is null or p_item_id is null then
    raise exception 'Shop id and item id are required';
  end if;

  if p_sale_price is null then
    raise exception 'Sale price is required';
  end if;

  if p_sale_price < 0 then
    raise exception 'Sale price cannot be negative';
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to update item prices for this shop';
  end if;

  update public.item
  set sale_price = p_sale_price
  where id = p_item_id
    and shop_id = p_shop_id;

  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'Item not found in this shop';
  end if;
end;
$$;

revoke all on function public.set_item_sale_price(uuid, uuid, numeric) from public;
grant execute on function public.set_item_sale_price(uuid, uuid, numeric) to authenticated;
