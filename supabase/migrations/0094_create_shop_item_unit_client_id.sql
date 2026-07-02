-- Offline-capable packaging creation (tier 2, slice B).
--
-- The Receive "+ Add packaging" sheet now mints the shop_item_unit UUID on
-- the device, so a new packaging can be mirrored locally and queued for
-- background upload — it works fully offline.
--
-- Mirrors the category / create_party idempotency pattern: a client-supplied
-- id + client_op_id make a retried create a safe no-op. Backward-compatible —
-- both new params default null (server generates the id as before), so the
-- Products editor, apply_template, and any other caller are unaffected. The
-- old 5-arg overload is dropped so a 5-arg call resolves unambiguously here.

drop function if exists public.create_shop_item_unit(uuid, uuid, text, numeric, numeric);

create or replace function public.create_shop_item_unit(
  p_shop_id            uuid,
  p_shop_item_id       uuid,
  p_unit_code          text,
  p_conversion_to_base numeric,
  p_sale_price         numeric default null,
  p_shop_item_unit_id  uuid default null,   -- client-generated; optimistic id == server id
  p_client_op_id       text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shop_item_unit_id uuid;
  v_unit_exists       boolean;
  v_shop_item_exists  boolean;
  v_cached            text;
begin
  -- Idempotent replay.
  if p_client_op_id is not null then
    select return_value into v_cached
      from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'create_shop_item_unit'
       and created_at > pg_catalog.now() - interval '1 hour';
    if found then
      return v_cached::uuid;
    end if;
  end if;

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

  if p_shop_item_unit_id is null then
    -- Legacy/online path: let the table default mint the id.
    insert into public.shop_item_unit (
      shop_id, shop_item_id, item_unit_id,
      unit_code, conversion_to_base, sale_price, created_by
    )
    values (
      p_shop_id, p_shop_item_id, null,
      p_unit_code, p_conversion_to_base, p_sale_price, auth.uid()
    )
    returning id into v_shop_item_unit_id;
  else
    -- Offline path: honour the client-supplied id, idempotent on replay.
    v_shop_item_unit_id := p_shop_item_unit_id;
    insert into public.shop_item_unit (
      id, shop_id, shop_item_id, item_unit_id,
      unit_code, conversion_to_base, sale_price, created_by
    )
    values (
      v_shop_item_unit_id, p_shop_id, p_shop_item_id, null,
      p_unit_code, p_conversion_to_base, p_sale_price, auth.uid()
    )
    on conflict (id) do nothing;
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'create_shop_item_unit', v_shop_item_unit_id::text)
    on conflict do nothing;
  end if;

  return v_shop_item_unit_id;
end;
$$;

revoke all on function public.create_shop_item_unit(uuid, uuid, text, numeric, numeric, uuid, text) from public;
grant execute on function public.create_shop_item_unit(uuid, uuid, text, numeric, numeric, uuid, text) to authenticated;
