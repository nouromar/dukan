-- Lazy activation primitives (decisions.md Q11, DECIDED 2026-05-31).
--
-- Two small additions for v1:
--   1. Relax activate_catalog_item's permission check so the posting
--      roles (owner + cashier) can also activate, not only the setup
--      roles. Required because lazy activation happens at first
--      Sale/Receive — which a cashier may post.
--   2. Add ensure_shop_item(shop_id, catalog_item_id) — a thin
--      idempotent wrapper the Flutter client calls right before
--      post_sale / post_receive / post_inventory_adjustment when the
--      user picked a catalog item the shop hasn't activated yet.
--      Returns the existing shop item_id if there is one, otherwise
--      activates the catalog item with defaults and returns the new id.
--
-- Posting RPCs (post_sale / post_receive / post_inventory_adjustment)
-- are NOT modified in v1. They still take item_id; the client resolves
-- catalog_item_id → item_id via ensure_shop_item one round trip earlier.
-- The atomicity gap (post fails after activation → orphan zero-stock
-- item row) is acceptable for pilot scale and can be closed in a v2
-- migration by moving the resolution into each RPC's line loop.

create or replace function public.activate_catalog_item(
  p_shop_id uuid,
  p_catalog_item_id uuid,
  p_catalog_revision_id uuid default null,
  p_code text default null,
  p_sale_price numeric default null,
  p_name_override text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_catalog_code text;
  v_revision_id uuid;
  v_revision public.catalog_item_revision%rowtype;
  v_item_id uuid;
  v_code text;
  v_base_unit_id uuid;
  v_default_sale_unit_id uuid;
  v_default_receive_unit_id uuid;
  v_inserted_units integer;
begin
  -- v1 lazy activation: either a setup actor (owner/org-admin) pinning
  -- a favorite, or a posting actor (owner/cashier) ringing through the
  -- first sale/receive of a catalog item is allowed to activate.
  if not (
    public.auth_can_manage_shop_setup(p_shop_id)
    or public.auth_can_post_shop(p_shop_id)
  ) then
    raise exception 'Not allowed to activate catalog items for this shop';
  end if;

  if p_sale_price is not null and p_sale_price < 0 then
    raise exception 'Sale price cannot be negative';
  end if;

  if p_name_override is not null and length(pg_catalog.btrim(p_name_override)) = 0 then
    raise exception 'Name override cannot be blank';
  end if;

  select ci.code, coalesce(p_catalog_revision_id, ci.current_revision_id)
  into v_catalog_code, v_revision_id
  from public.catalog_item ci
  where ci.id = p_catalog_item_id
    and ci.is_active;

  if v_catalog_code is null then
    raise exception 'Catalog item is not available';
  end if;

  if v_revision_id is null then
    raise exception 'Catalog item has no current revision';
  end if;

  select *
  into v_revision
  from public.catalog_item_revision cir
  where cir.catalog_item_id = p_catalog_item_id
    and cir.id = v_revision_id;

  if v_revision.id is null then
    raise exception 'Catalog revision does not belong to catalog item';
  end if;

  v_code := coalesce(nullif(pg_catalog.btrim(p_code), ''), v_catalog_code);

  if v_code <> lower(v_code) or v_code !~ '^[a-z][a-z0-9_]*$' then
    raise exception 'Item code must be lowercase snake_case';
  end if;

  if exists (
    select 1 from public.item where shop_id = p_shop_id and code = v_code
  ) then
    raise exception 'Item code already exists in this shop';
  end if;

  select id into v_base_unit_id
  from public.unit
  where code = v_revision.base_unit_code and is_active;

  select id into v_default_sale_unit_id
  from public.unit
  where code = v_revision.default_sale_unit_code and is_active;

  select id into v_default_receive_unit_id
  from public.unit
  where code = v_revision.default_receive_unit_code and is_active;

  if v_base_unit_id is null or v_default_sale_unit_id is null or v_default_receive_unit_id is null then
    raise exception 'Catalog revision references inactive or missing units';
  end if;

  insert into public.item (
    shop_id, code, catalog_item_id, catalog_revision_id, name, name_override,
    base_unit_id, default_sale_unit_id, default_receive_unit_id,
    sale_price, reorder_threshold, created_by
  )
  values (
    p_shop_id, v_code, p_catalog_item_id, v_revision_id, v_revision.name, p_name_override,
    v_base_unit_id, v_default_sale_unit_id, v_default_receive_unit_id,
    coalesce(p_sale_price, v_revision.suggested_sale_price),
    v_revision.reorder_threshold, auth.uid()
  )
  returning id into v_item_id;

  insert into public.item_unit (
    shop_id, item_id, unit_id, source_catalog_item_unit_id, source,
    conversion_to_base, is_base_unit, sort_order, created_by
  )
  select
    p_shop_id, v_item_id, u.id, ciu.id, 'catalog',
    ciu.conversion_to_base, ciu.is_base_unit, ciu.sort_order, auth.uid()
  from public.catalog_item_unit ciu
  join public.unit u on u.code = ciu.unit_code and u.is_active
  where ciu.catalog_item_id = p_catalog_item_id
    and ciu.revision_id = v_revision_id;

  get diagnostics v_inserted_units = row_count;

  if v_inserted_units = 0 then
    raise exception 'Catalog revision has no active units';
  end if;

  if not exists (
    select 1
    from public.item_unit
    where shop_id = p_shop_id
      and item_id = v_item_id
      and is_base_unit
  ) then
    raise exception 'Catalog revision must include one base unit';
  end if;

  return v_item_id;
end;
$$;

revoke all on function public.activate_catalog_item(uuid, uuid, uuid, text, numeric, text) from public;
grant execute on function public.activate_catalog_item(uuid, uuid, uuid, text, numeric, text) to authenticated;

-- Client convenience: returns the shop's item_id for a catalog item,
-- activating the catalog item with defaults if the shop has not yet
-- activated it. Idempotent: callers can invoke once per Sale/Receive
-- line that carries a catalog_item_id and then pass the returned
-- item_id into the existing post_* RPCs unchanged.
create or replace function public.ensure_shop_item(
  p_shop_id uuid,
  p_catalog_item_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item_id uuid;
begin
  if p_catalog_item_id is null then
    raise exception 'Catalog item id is required';
  end if;

  if not (
    public.auth_can_manage_shop_setup(p_shop_id)
    or public.auth_can_post_shop(p_shop_id)
  ) then
    raise exception 'Not allowed to activate catalog items for this shop';
  end if;

  select id
  into v_item_id
  from public.item
  where shop_id = p_shop_id
    and catalog_item_id = p_catalog_item_id;

  if v_item_id is not null then
    return v_item_id;
  end if;

  return public.activate_catalog_item(
    p_shop_id, p_catalog_item_id, null, null, null, null
  );
end;
$$;

revoke all on function public.ensure_shop_item(uuid, uuid) from public;
grant execute on function public.ensure_shop_item(uuid, uuid) to authenticated;
