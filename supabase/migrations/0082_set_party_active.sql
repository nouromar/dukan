-- set_party_active: hide/restore a customer or supplier (soft-delete).
--
-- party.is_active already exists (0007) and both search_parties (0077) and the
-- local mirror's search already filter on it, so flipping is_active=false hides
-- the party from lists + pickers immediately. Owner-gated, idempotent for the
-- offline queue — mirrors set_shop_category_active (0076).

create or replace function public.set_party_active(
  p_shop_id      uuid,
  p_party_id     uuid,
  p_is_active    boolean,
  p_client_op_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_client_op_id is not null and exists (
    select 1 from public.mutation_idempotency
     where shop_id = p_shop_id and client_op_id = p_client_op_id
       and rpc_name = 'set_party_active'
       and created_at > pg_catalog.now() - interval '1 hour'
  ) then
    return;
  end if;

  if not public.auth_can_manage_shop_setup(p_shop_id) then
    raise exception 'Not allowed to manage parties for this shop';
  end if;

  update public.party
     set is_active = coalesce(p_is_active, true), updated_at = now()
   where id = p_party_id
     and shop_id = p_shop_id;
  if not found then
    raise exception 'Party not found in this shop';
  end if;

  if p_client_op_id is not null then
    insert into public.mutation_idempotency(shop_id, client_op_id, rpc_name, return_value)
    values (p_shop_id, p_client_op_id, 'set_party_active', null)
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.set_party_active(uuid, uuid, boolean, text) from public;
grant execute on function public.set_party_active(uuid, uuid, boolean, text) to authenticated;
