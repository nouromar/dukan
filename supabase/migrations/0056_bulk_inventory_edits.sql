-- 0056_bulk_inventory_edits.sql
--
-- Bulk write paths for the shop-admin portal's Inventory module
-- (#289). Two RPCs, both:
--   * Gated on the existing inventory.product.bulk_edit capability
--     (owner-only by default; portal can grant to other roles via
--     custom-role assignment later).
--   * Transactional — either every row succeeds or none.
--   * Audit-logged per-row so the trail looks identical to single-
--     item edits done from the cashier UI. Uses the existing action
--     codes (inventory.unit.price_edit, inventory.product.edit).
--
-- 1. bulk_set_default_sale_price(p_shop_id, p_shop_item_ids, p_price)
--    For each shop_item, resolves the default-sale shop_item_unit
--    (or falls back to the base-unit row when no default-sale flag
--    is set), updates sale_price, audit-logs each change. Skips any
--    shop_item that has no shop_item_unit rows at all.
--
-- 2. bulk_set_reorder_threshold(p_shop_id, p_shop_item_ids, p_threshold)
--    Updates reorder_threshold on each shop_item row directly. The
--    threshold is stored in base units (UI converts at render).
--
-- Both return an int: count of shop_item rows actually written.
-- Callers (portal Server Action) toast that count back to the user.

create or replace function public.bulk_set_default_sale_price(
  p_shop_id        uuid,
  p_shop_item_ids  uuid[],
  p_price          numeric
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count        int := 0;
  v_id           uuid;
  v_unit_id      uuid;
begin
  if p_shop_id is null then
    raise exception 'shop_id is required';
  end if;
  if p_shop_item_ids is null or array_length(p_shop_item_ids, 1) is null then
    raise exception 'shop_item_ids array is required';
  end if;
  if p_price is not null and p_price < 0 then
    raise exception 'Sale price cannot be negative';
  end if;
  if not public.auth_user_has_capability('inventory.product.bulk_edit', p_shop_id) then
    raise exception 'Not allowed to bulk-edit products for this shop';
  end if;

  foreach v_id in array p_shop_item_ids loop
    -- Prefer the explicitly-flagged default-sale packaging; fall
    -- back to the base-unit row (conversion = 1) when none is
    -- marked. is_active filter so we don't write to a retired unit.
    select id into v_unit_id
    from public.shop_item_unit
    where shop_id = p_shop_id
      and shop_item_id = v_id
      and is_active
    order by is_default_sale desc, (conversion_to_base = 1) desc, sort_order
    limit 1;

    if v_unit_id is null then
      continue;
    end if;

    update public.shop_item_unit
    set sale_price = p_price,
        updated_at = pg_catalog.now()
    where shop_id = p_shop_id and id = v_unit_id;

    perform public._audit_log(
      p_shop_id     => p_shop_id,
      p_action_code => 'inventory.unit.price_edit',
      p_entity_type => 'shop_item_unit',
      p_entity_id   => v_unit_id,
      p_after       => pg_catalog.jsonb_build_object(
        'sale_price', p_price,
        'via',        'bulk'
      )
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.bulk_set_default_sale_price(uuid, uuid[], numeric) from public;
grant execute on function public.bulk_set_default_sale_price(uuid, uuid[], numeric) to authenticated;

-- ---------------------------------------------------------------

create or replace function public.bulk_set_reorder_threshold(
  p_shop_id        uuid,
  p_shop_item_ids  uuid[],
  p_threshold      numeric
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count   int := 0;
  v_id      uuid;
  v_before  jsonb;
begin
  if p_shop_id is null then
    raise exception 'shop_id is required';
  end if;
  if p_shop_item_ids is null or array_length(p_shop_item_ids, 1) is null then
    raise exception 'shop_item_ids array is required';
  end if;
  if p_threshold is not null and p_threshold < 0 then
    raise exception 'Reorder threshold cannot be negative';
  end if;
  if not public.auth_user_has_capability('inventory.product.bulk_edit', p_shop_id) then
    raise exception 'Not allowed to bulk-edit products for this shop';
  end if;

  foreach v_id in array p_shop_item_ids loop
    select pg_catalog.jsonb_build_object('reorder_threshold', reorder_threshold)
    into v_before
    from public.shop_item
    where shop_id = p_shop_id and id = v_id;

    if v_before is null then
      continue;
    end if;

    update public.shop_item
    set reorder_threshold = p_threshold,
        updated_at = pg_catalog.now()
    where shop_id = p_shop_id and id = v_id;

    perform public._audit_log(
      p_shop_id     => p_shop_id,
      p_action_code => 'inventory.product.edit',
      p_entity_type => 'shop_item',
      p_entity_id   => v_id,
      p_before      => v_before,
      p_after       => pg_catalog.jsonb_build_object(
        'reorder_threshold', p_threshold,
        'via',               'bulk'
      )
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.bulk_set_reorder_threshold(uuid, uuid[], numeric) from public;
grant execute on function public.bulk_set_reorder_threshold(uuid, uuid[], numeric) to authenticated;
