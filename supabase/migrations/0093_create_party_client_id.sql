-- Offline-capable party creation (tier 2).
--
-- The daily "add a new customer / supplier" sheet now mints the party's
-- UUID on the device, so the create can be written to the local mirror
-- and queued for background upload — it works fully offline (a debt sale
-- to a brand-new customer no longer needs a live connection).
--
-- Mirrors the category-create idempotency pattern (0076_manage_categories):
-- a client-supplied id + client_op_id make a retried create a safe no-op.
-- Backward-compatible — both new params default null, in which case the
-- server generates the id exactly as before, so existing callers (and the
-- Products editor) are unaffected. The old 4-arg overload is dropped so a
-- 4-arg call resolves unambiguously to this function via the defaults.

drop function if exists public.create_party(uuid, text, text, text);

create or replace function public.create_party(
  p_shop_id      uuid,
  p_name         text,
  p_phone        text default null,
  p_type_code    text default 'customer',
  p_party_id     uuid default null,   -- client-generated; optimistic id == server id
  p_client_op_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type_id  uuid;
  v_name     text;
  v_phone    text;
  v_party_id uuid;
  v_cached   text;
begin
  -- Idempotent replay: a queued create retried with the same client_op_id
  -- returns the original id instead of inserting a duplicate.
  if p_client_op_id is not null then
    select return_value into v_cached
      from public.mutation_idempotency
     where shop_id = p_shop_id
       and client_op_id = p_client_op_id
       and rpc_name = 'create_party'
       and created_at > pg_catalog.now() - interval '1 hour';
    if found then
      return v_cached::uuid;
    end if;
  end if;

  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to create parties for this shop';
  end if;

  v_name := nullif(pg_catalog.btrim(p_name), '');
  if v_name is null then
    raise exception 'Party name is required';
  end if;

  -- v1 surface: only the two operational types are creatable from the
  -- daily UI. 'both' stays a setup-only choice (admin portal).
  if p_type_code not in ('customer', 'supplier') then
    raise exception 'Party type must be customer or supplier (got %)', p_type_code;
  end if;

  select id into v_type_id
  from public.party_type
  where code = p_type_code and is_active;

  if v_type_id is null then
    raise exception 'Party type % is not active', p_type_code;
  end if;

  v_phone := nullif(pg_catalog.btrim(coalesce(p_phone, '')), '');

  if p_party_id is null then
    -- Legacy/online path: let the table default mint the id.
    insert into public.party (shop_id, name, phone, type_id, created_by)
    values (p_shop_id, v_name, v_phone, v_type_id, auth.uid())
    returning id into v_party_id;
  else
    -- Offline path: honour the client-supplied id and stay idempotent on
    -- replay (a re-drained create must not duplicate the party).
    v_party_id := p_party_id;
    insert into public.party (id, shop_id, name, phone, type_id, created_by)
    values (v_party_id, p_shop_id, v_name, v_phone, v_type_id, auth.uid())
    on conflict (id) do nothing;
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'create_party', v_party_id::text)
    on conflict do nothing;
  end if;

  return v_party_id;
end;
$$;

revoke all on function public.create_party(uuid, text, text, text, uuid, text) from public;
grant execute on function public.create_party(uuid, text, text, text, uuid, text) to authenticated;
