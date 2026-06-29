-- 0083_get_payment.sql
--
-- Payment detail header RPC, so the app can open a single payment from the
-- party detail / payment history. Mirrors get_sale (0028): security definer +
-- auth_can_access_shop guard, read-only (stable), no writes. The "what it
-- settled" list reuses the existing list_payment_allocations (0053).

create or replace function public.get_payment(
  p_shop_id    uuid,
  p_payment_id uuid
)
returns table (
  payment_id          uuid,
  occurred_at         timestamptz,
  party_id            uuid,
  party_name          text,
  direction           char(1),
  amount              numeric,
  payment_method_code text,
  notes               text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to view payments for this shop';
  end if;

  return query
  select
    pay.id          as payment_id,
    pay.occurred_at,
    pay.party_id,
    p.name          as party_name,
    pay.direction,
    pay.amount,
    pm.code         as payment_method_code,
    pay.notes
  from public.payment pay
  left join public.party p on p.id = pay.party_id
  join public.payment_method pm on pm.id = pay.method_id
  where pay.shop_id = p_shop_id
    and pay.id = p_payment_id;
end;
$$;

revoke all on function public.get_payment(uuid, uuid) from public;
grant execute on function public.get_payment(uuid, uuid) to authenticated;
