-- Cashier-driven party creation. Customers and suppliers are
-- operational data created naturally during daily work (a new
-- customer wants to buy on debt; a new supplier drops off a bono),
-- so cashiers — not just setup admins — can create them.
--
-- The configuration tables (templates, units, expense categories)
-- stay setup-only. Party records are an exception because forcing a
-- "come back tomorrow when support adds you" flow violates the
-- decision-free-daily-use principle (CLAUDE.md north-star).
--
-- Returns the new party's id so the caller can auto-select the party
-- it just created (cashier types name + tap SAVE → continues sale or
-- receive without picking again from a list).

create or replace function public.create_party(
  p_shop_id uuid,
  p_name text,
  p_phone text default null,
  p_type_code text default 'customer'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type_id uuid;
  v_name text;
  v_phone text;
  v_party_id uuid;
begin
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

  insert into public.party (shop_id, name, phone, type_id, created_by)
  values (p_shop_id, v_name, v_phone, v_type_id, auth.uid())
  returning id into v_party_id;

  return v_party_id;
end;
$$;

revoke all on function public.create_party(uuid, text, text, text) from public;
grant execute on function public.create_party(uuid, text, text, text) to authenticated;
