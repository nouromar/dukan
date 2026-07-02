-- Offline-capable product creation (tier 2, slice C).
--
-- The Sale/Receive "+ Add new item" sheet now mints the shop_item UUID AND
-- the default packaging (shop_item_unit) UUID on the device, so a brand-new
-- product can be optimistically mirrored and queued for background upload —
-- it works fully offline, and the freshly-added item drops straight into the
-- cart / receive line using the client-minted default-unit id.
--
-- create_shop_item fans out to up to four rows (shop_item + base unit +
-- optional distinct sold unit + display alias). The client supplies ids for
-- the three the daily flow needs downstream (item + the two possible units);
-- the display alias id stays server-generated (nothing references it offline).
-- All new params default null → the server generates ids exactly as before,
-- so apply_template, the Products editor, and any other caller are unaffected.
-- Idempotent on replay via mutation_idempotency + `on conflict do nothing`.
--
-- gen_random_uuid is taken from pg_catalog (core since PG13) — NOT the
-- extensions schema — so it needs no schema-level grant.

drop function if exists public.create_shop_item(uuid, text, text, text, numeric, uuid, text, numeric, text);

create or replace function public.create_shop_item(
  p_shop_id          uuid,
  p_name             text,
  p_language_code    text,
  p_base_unit_code   text,
  p_sale_price       numeric default null,
  p_category_id      uuid default null,
  p_sold_unit_code   text default null,
  p_sold_conversion  numeric default null,
  p_default_side     text default 'sale',
  p_shop_item_id     uuid default null,   -- client-generated ids (offline path);
  p_base_unit_id     uuid default null,   -- null → server generates as before.
  p_sold_unit_id     uuid default null,
  p_client_op_id     text default null
)
returns table (
  shop_item_id              uuid,
  default_shop_item_unit_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shop_item_id uuid;
  v_base_unit_unit_id uuid;
  v_sold_unit_id uuid;
  v_name text;
  v_unit_exists boolean;
  v_lang_exists boolean;
  v_sold_is_distinct boolean;
  v_base_is_default_sale boolean;
  v_base_is_default_receive boolean;
  v_sold_is_default_sale boolean;
  v_sold_is_default_receive boolean;
  v_cached text;
begin
  -- Idempotent replay: a re-drained create returns the client-supplied ids
  -- instead of fanning out a duplicate item.
  if p_client_op_id is not null then
    select return_value into v_cached
      from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'create_shop_item'
       and created_at > pg_catalog.now() - interval '1 hour';
    if found then
      shop_item_id := v_cached::uuid;
      default_shop_item_unit_id := coalesce(p_sold_unit_id, p_base_unit_id);
      return next;
      return;
    end if;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to create items for this shop';
  end if;

  v_name := pg_catalog.btrim(coalesce(p_name, ''));
  if v_name = '' then
    raise exception 'Item name is required';
  end if;

  if p_language_code is null then
    raise exception 'Language code is required';
  end if;
  select true into v_lang_exists
  from public.language where code = p_language_code and is_active;
  if v_lang_exists is null then
    raise exception 'Language % is not active', p_language_code;
  end if;

  if p_base_unit_code is null then
    raise exception 'Base unit is required';
  end if;
  select true into v_unit_exists
  from public.unit where code = p_base_unit_code and is_active;
  if v_unit_exists is null then
    raise exception 'Unit % is not active', p_base_unit_code;
  end if;

  if p_sale_price is not null and p_sale_price < 0 then
    raise exception 'Sale price cannot be negative';
  end if;

  if p_default_side not in ('sale', 'receive') then
    raise exception
      'p_default_side must be sale or receive, got %', p_default_side;
  end if;

  -- Is the sold packaging genuinely distinct from the base packaging?
  v_sold_is_distinct :=
    p_sold_unit_code is not null
    and not (
      p_sold_unit_code = p_base_unit_code
      and coalesce(p_sold_conversion, 1) = 1
    );

  if v_sold_is_distinct then
    if p_sold_conversion is null or p_sold_conversion <= 0 then
      raise exception
        'Sold conversion must be > 0 when a non-base packaging is picked';
    end if;
    if p_sold_conversion = 1 then
      raise exception
        'Sold conversion must be > 1 when sold unit differs from base';
    end if;
    select true into v_unit_exists
    from public.unit where code = p_sold_unit_code and is_active;
    if v_unit_exists is null then
      raise exception 'Sold unit % is not active', p_sold_unit_code;
    end if;
  end if;

  -- Decide default flags (base wins the opposite side when sold is distinct).
  if v_sold_is_distinct then
    if p_default_side = 'sale' then
      v_sold_is_default_sale     := true;
      v_sold_is_default_receive  := false;
      v_base_is_default_sale     := false;
      v_base_is_default_receive  := true;
    else
      v_sold_is_default_sale     := false;
      v_sold_is_default_receive  := true;
      v_base_is_default_sale     := true;
      v_base_is_default_receive  := false;
    end if;
  else
    v_base_is_default_sale    := true;
    v_base_is_default_receive := true;
  end if;

  -- Ids: client-supplied (offline) or freshly generated (legacy).
  v_shop_item_id      := coalesce(p_shop_item_id, pg_catalog.gen_random_uuid());
  v_base_unit_unit_id := coalesce(p_base_unit_id, pg_catalog.gen_random_uuid());
  if v_sold_is_distinct then
    v_sold_unit_id := coalesce(p_sold_unit_id, pg_catalog.gen_random_uuid());
  end if;

  -- Shop-local item row. category_id may be null.
  insert into public.shop_item (
    id, shop_id, item_id, base_unit_code, category_id, created_by
  )
  values (
    v_shop_item_id, p_shop_id, null, p_base_unit_code, p_category_id, auth.uid()
  )
  on conflict (id) do nothing;

  -- Base packaging (carries the price only when selling in base).
  insert into public.shop_item_unit (
    id, shop_id, shop_item_id, item_unit_id,
    unit_code, conversion_to_base,
    sale_price,
    is_default_sale, is_default_receive, sort_order,
    created_by
  )
  values (
    v_base_unit_unit_id, p_shop_id, v_shop_item_id, null,
    p_base_unit_code, 1,
    case when v_sold_is_distinct then null else p_sale_price end,
    v_base_is_default_sale, v_base_is_default_receive, 0,
    auth.uid()
  )
  on conflict (id) do nothing;

  if v_sold_is_distinct then
    insert into public.shop_item_unit (
      id, shop_id, shop_item_id, item_unit_id,
      unit_code, conversion_to_base,
      sale_price,
      is_default_sale, is_default_receive, sort_order,
      created_by
    )
    values (
      v_sold_unit_id, p_shop_id, v_shop_item_id, null,
      p_sold_unit_code, p_sold_conversion,
      p_sale_price,
      v_sold_is_default_sale, v_sold_is_default_receive, 1,
      auth.uid()
    )
    on conflict (id) do nothing;
  end if;

  -- Display-name alias in the cashier's locale (server-generated id;
  -- idempotent on the (shop, item, language, normalized-text) unique index).
  insert into public.shop_item_alias (
    shop_id, shop_item_id, alias_text, language_code,
    is_display, source, created_by
  )
  values (
    p_shop_id, v_shop_item_id, v_name, p_language_code,
    true, 'manual', auth.uid()
  )
  on conflict do nothing;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'create_shop_item', v_shop_item_id::text)
    on conflict do nothing;
  end if;

  shop_item_id := v_shop_item_id;
  default_shop_item_unit_id := coalesce(v_sold_unit_id, v_base_unit_unit_id);
  return next;
end;
$$;

revoke all on function public.create_shop_item(uuid, text, text, text, numeric, uuid, text, numeric, text, uuid, uuid, uuid, text) from public;
grant execute on function public.create_shop_item(uuid, text, text, text, numeric, uuid, text, numeric, text, uuid, uuid, uuid, text) to authenticated;
