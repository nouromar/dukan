-- Activation + creation RPCs for shop_item / shop_item_unit /
-- shop_item_alias. All gated by auth_can_post_shop (cashier-accessible
-- because daily flows can trigger activation; see decisions.md Q11).
--
-- Four entry points:
--   ensure_shop_item        — idempotent activation from the global catalog.
--   create_shop_item        — shop-local item ("+ Add new item" mid-sale).
--   create_shop_item_unit   — shop-local packaging ("+ Add packaging").
--   add_shop_item_alias     — display-name override + OCR-learning sink.
--
-- All four are SECURITY DEFINER so they bypass RLS; they validate the
-- caller against the shop's posting permission themselves.


-- ---------------------------------------------------------------------------
-- ensure_shop_item — idempotent activation of a global catalog item.
-- ---------------------------------------------------------------------------
--
-- If the shop has already activated this global item, returns the
-- existing shop_item.id. Otherwise snapshots the global item +
-- item_units + display aliases into the shop overlay and returns the
-- new shop_item.id.
--
-- Snapshot semantics (data-model-v2 §3 critique #4):
--   shop_item.base_unit_code           ← item.base_unit_code
--   shop_item.category_id              ← item.category_id
--   shop_item_unit.unit_code           ← item_unit.unit_code
--   shop_item_unit.conversion_to_base  ← item_unit.conversion_to_base
--   shop_item_unit.is_default_sale     ← item_unit.is_default_sale
--   shop_item_unit.is_default_receive  ← item_unit.is_default_receive
--   shop_item_alias rows (is_display=true only)
--                                      ← item_alias rows where is_display=true
--
-- Money fields (sale_price, last_cost) start NULL — cashier fills them
-- in via the priceRequired editor on first sale.

create or replace function public.ensure_shop_item(
  p_shop_id uuid,
  p_item_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shop_item_id uuid;
  v_base_unit_code text;
  v_category_id uuid;
  v_inserted_units int;
begin
  if p_item_id is null then
    raise exception 'Item id is required';
  end if;

  if not (
    public.auth_can_post_shop(p_shop_id)
    or public.auth_can_manage_shop_setup(p_shop_id)
  ) then
    raise exception 'Not allowed to activate items for this shop';
  end if;

  -- Idempotent: if already activated, just return the existing row.
  select id into v_shop_item_id
  from public.shop_item
  where shop_id = p_shop_id and item_id = p_item_id;
  if v_shop_item_id is not null then
    return v_shop_item_id;
  end if;

  -- Resolve the global item (must be active).
  select base_unit_code, category_id
  into v_base_unit_code, v_category_id
  from public.item
  where id = p_item_id and is_active;
  if v_base_unit_code is null then
    raise exception 'Item % is not available', p_item_id;
  end if;

  -- Snapshot the structural fields into shop_item.
  insert into public.shop_item (
    shop_id, item_id, base_unit_code, category_id, created_by
  )
  values (
    p_shop_id, p_item_id, v_base_unit_code, v_category_id, auth.uid()
  )
  returning id into v_shop_item_id;

  -- Snapshot every active item_unit into shop_item_unit. Money fields
  -- left NULL; defaults inherited from global flags.
  insert into public.shop_item_unit (
    shop_id, shop_item_id, item_unit_id,
    unit_code, conversion_to_base,
    is_default_sale, is_default_receive, sort_order,
    created_by
  )
  select
    p_shop_id, v_shop_item_id, iu.id,
    iu.unit_code, iu.conversion_to_base,
    iu.is_default_sale, iu.is_default_receive, iu.sort_order,
    auth.uid()
  from public.item_unit iu
  where iu.item_id = p_item_id and iu.is_active;

  get diagnostics v_inserted_units = row_count;

  if v_inserted_units = 0 then
    raise exception 'Item % has no active packagings', p_item_id;
  end if;

  -- Snapshot display-name aliases (one per language). Search aliases
  -- (is_display=false) stay on the global table — search walks both
  -- tiers so we don't need to duplicate them per shop.
  insert into public.shop_item_alias (
    shop_id, shop_item_id, alias_text, language_code,
    is_display, source, weight, created_by
  )
  select
    p_shop_id, v_shop_item_id, ia.alias_text, ia.language_code,
    true, 'manual', ia.weight, auth.uid()
  from public.item_alias ia
  where ia.item_id = p_item_id
    and ia.is_display
    and ia.is_active;

  return v_shop_item_id;
end;
$$;

revoke all on function public.ensure_shop_item(uuid, uuid) from public;
grant execute on function public.ensure_shop_item(uuid, uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- create_shop_item — shop-local item creation ("+ Add new item").
-- ---------------------------------------------------------------------------
--
-- Used by the cashier's mid-sale add-new-item sheet AND the Products
-- screen editor. Atomically inserts the shop_item, one or two
-- shop_item_unit rows (base + optional sold packaging), and the
-- display alias.
--
-- Sold-in-base case (p_sold_unit_code null OR equals (base, 1)):
--   one shop_item_unit row at conversion=1 — both default flags on,
--   sale_price = p_sale_price.
--
-- Sold-packaged case (p_sold_unit_code given AND ≠ base):
--   two shop_item_unit rows:
--     base   — conversion=1, sale_price NULL, default flags per §1.4.
--     sold   — conversion=p_sold_conversion, sale_price=p_sale_price,
--              gets the variant-side default; the base gets the other.
--
-- Default flag assignment uses p_default_side ('sale' | 'receive'):
--   'sale':    sold→is_default_sale=true,  base→is_default_receive=true.
--   'receive': sold→is_default_receive=true, base→is_default_sale=true.
--
-- Returns (shop_item_id, default_shop_item_unit_id) — the second is
-- the row matching the cashier's pick so the cart / receive form can
-- bind without a follow-up listShopItemUnits call.

-- Drop the old single-return signature so the rename of the return
-- type is clean (CREATE OR REPLACE can't change return type).
drop function if exists public.create_shop_item(uuid, text, text, text, numeric, uuid);

create or replace function public.create_shop_item(
  p_shop_id          uuid,
  p_name             text,
  p_language_code    text,
  p_base_unit_code   text,
  p_sale_price       numeric default null,
  p_category_id      uuid default null,
  p_sold_unit_code   text default null,
  p_sold_conversion  numeric default null,
  p_default_side     text default 'sale'
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
begin
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
  -- Treat (null sold) OR (sold == base AND conv == 1 / null) as
  -- "sold in base", taking the single-packaging path.
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

  -- Decide default flags. The base row always wins the default flag
  -- on the *opposite* side when sold is distinct — see §1.4.
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
    -- Single packaging: own both defaults.
    v_base_is_default_sale    := true;
    v_base_is_default_receive := true;
  end if;

  -- Create the shop-local item row. category_id may be null.
  insert into public.shop_item (
    shop_id, item_id, base_unit_code, category_id, created_by
  )
  values (
    p_shop_id, null, p_base_unit_code, p_category_id, auth.uid()
  )
  returning id into v_shop_item_id;

  -- Insert the base packaging row. When the cashier is selling in
  -- base, this row carries the price; otherwise it stays unpriced.
  insert into public.shop_item_unit (
    shop_id, shop_item_id, item_unit_id,
    unit_code, conversion_to_base,
    sale_price,
    is_default_sale, is_default_receive, sort_order,
    created_by
  )
  values (
    p_shop_id, v_shop_item_id, null,
    p_base_unit_code, 1,
    case when v_sold_is_distinct then null else p_sale_price end,
    v_base_is_default_sale, v_base_is_default_receive, 0,
    auth.uid()
  )
  returning id into v_base_unit_unit_id;

  if v_sold_is_distinct then
    insert into public.shop_item_unit (
      shop_id, shop_item_id, item_unit_id,
      unit_code, conversion_to_base,
      sale_price,
      is_default_sale, is_default_receive, sort_order,
      created_by
    )
    values (
      p_shop_id, v_shop_item_id, null,
      p_sold_unit_code, p_sold_conversion,
      p_sale_price,
      v_sold_is_default_sale, v_sold_is_default_receive, 1,
      auth.uid()
    )
    returning id into v_sold_unit_id;
  end if;

  -- Display-name alias in the cashier's locale.
  insert into public.shop_item_alias (
    shop_id, shop_item_id, alias_text, language_code,
    is_display, source, created_by
  )
  values (
    p_shop_id, v_shop_item_id, v_name, p_language_code,
    true, 'manual', auth.uid()
  );

  shop_item_id := v_shop_item_id;
  default_shop_item_unit_id :=
    coalesce(v_sold_unit_id, v_base_unit_unit_id);
  return next;
end;
$$;

revoke all on function public.create_shop_item(uuid, text, text, text, numeric, uuid, text, numeric, text) from public;
grant execute on function public.create_shop_item(uuid, text, text, text, numeric, uuid, text, numeric, text) to authenticated;


-- ---------------------------------------------------------------------------
-- create_shop_item_unit — shop-local packaging ("+ Add packaging").
-- ---------------------------------------------------------------------------
--
-- Adds a non-base packaging to an existing shop_item. The base
-- packaging (conversion=1) was created by ensure_shop_item or
-- create_shop_item — this RPC is for additional packagings the
-- cashier types in mid-receive.

create or replace function public.create_shop_item_unit(
  p_shop_id uuid,
  p_shop_item_id uuid,
  p_unit_code text,
  p_conversion_to_base numeric,
  p_sale_price numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shop_item_unit_id uuid;
  v_unit_exists boolean;
  v_shop_item_exists boolean;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to add packagings for this shop';
  end if;

  if p_unit_code is null then
    raise exception 'Unit code is required';
  end if;
  select true into v_unit_exists
  from public.unit where code = p_unit_code and is_active;
  if v_unit_exists is null then
    raise exception 'Unit % is not active', p_unit_code;
  end if;

  if p_conversion_to_base is null or p_conversion_to_base <= 0 then
    raise exception 'Conversion to base must be > 0';
  end if;

  if p_sale_price is not null and p_sale_price < 0 then
    raise exception 'Sale price cannot be negative';
  end if;

  select true into v_shop_item_exists
  from public.shop_item
  where id = p_shop_item_id and shop_id = p_shop_id;
  if v_shop_item_exists is null then
    raise exception 'shop_item % not found in shop %', p_shop_item_id, p_shop_id;
  end if;

  insert into public.shop_item_unit (
    shop_id, shop_item_id, item_unit_id,
    unit_code, conversion_to_base,
    sale_price,
    created_by
  )
  values (
    p_shop_id, p_shop_item_id, null,
    p_unit_code, p_conversion_to_base,
    p_sale_price,
    auth.uid()
  )
  returning id into v_shop_item_unit_id;

  return v_shop_item_unit_id;
end;
$$;

revoke all on function public.create_shop_item_unit(uuid, uuid, text, numeric, numeric) from public;
grant execute on function public.create_shop_item_unit(uuid, uuid, text, numeric, numeric) to authenticated;


-- ---------------------------------------------------------------------------
-- add_shop_item_alias — used by OCR feedback + cashier rename.
-- ---------------------------------------------------------------------------
--
-- When is_display=true, supersedes any existing display alias for the
-- same (shop_item, language) — the partial unique index would
-- otherwise reject the insert, so we flip the existing one off first.

create or replace function public.add_shop_item_alias(
  p_shop_id uuid,
  p_shop_item_id uuid,
  p_alias_text text,
  p_language_code text default null,
  p_is_display boolean default false,
  p_source text default 'manual'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alias_id uuid;
  v_alias_text text;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to add aliases for this shop';
  end if;

  v_alias_text := pg_catalog.btrim(coalesce(p_alias_text, ''));
  if v_alias_text = '' then
    raise exception 'Alias text is required';
  end if;

  if p_source not in ('manual', 'ocr_correction', 'learned') then
    raise exception 'source must be one of manual, ocr_correction, learned';
  end if;

  if not exists (
    select 1 from public.shop_item
    where id = p_shop_item_id and shop_id = p_shop_id
  ) then
    raise exception 'shop_item % not found in shop %', p_shop_item_id, p_shop_id;
  end if;

  -- If marking as display, clear any prior display alias in the same
  -- language so the partial unique index doesn't reject the insert.
  if p_is_display then
    update public.shop_item_alias
    set is_display = false
    where shop_id = p_shop_id
      and shop_item_id = p_shop_item_id
      and language_code is not distinct from p_language_code
      and is_display;
  end if;

  insert into public.shop_item_alias (
    shop_id, shop_item_id, alias_text, language_code,
    is_display, source, created_by
  )
  values (
    p_shop_id, p_shop_item_id, v_alias_text, p_language_code,
    p_is_display, p_source, auth.uid()
  )
  on conflict (shop_id, shop_item_id, language_code, alias_text_norm)
  do update set
    is_display = excluded.is_display,
    source = excluded.source,
    is_active = true,
    updated_at = now()
  returning id into v_alias_id;

  return v_alias_id;
end;
$$;

revoke all on function public.add_shop_item_alias(uuid, uuid, text, text, boolean, text) from public;
grant execute on function public.add_shop_item_alias(uuid, uuid, text, text, boolean, text) to authenticated;
