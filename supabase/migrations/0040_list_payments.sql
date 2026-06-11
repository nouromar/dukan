-- list_payments — reverse-chronological list of past payment rows.
-- Same pagination + scope-filter shape as list_sales/list_receives.
--
-- Filters:
--   * p_date_from / p_date_to — clamp by occurred_at
--   * p_party_id — narrow to one party (inbound from a customer or
--                  outbound to a supplier)
--   * p_direction — 'I' (inbound) or 'O' (outbound); null = both
--
-- Refund payments (those with refund_of_transaction_id set) are
-- included; the row is flagged via `is_refund` so the UI can render a
-- subtle marker without filtering them out by default.

create or replace function public.list_payments(
  p_shop_id    uuid,
  p_before     timestamptz default null,
  p_limit      int         default 50,
  p_date_from  timestamptz default null,
  p_date_to    timestamptz default null,
  p_party_id   uuid        default null,
  p_direction  char        default null
)
returns table (
  payment_id          uuid,
  occurred_at         timestamptz,
  created_at          timestamptz,
  party_id            uuid,
  party_name          text,
  amount              numeric,
  direction           char(1),
  payment_method_code text,
  notes               text,
  is_refund           boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list payments for this shop';
  end if;
  if p_direction is not null and p_direction not in ('I', 'O') then
    raise exception 'Direction must be I, O, or null';
  end if;

  return query
  select
    p.id            as payment_id,
    p.occurred_at,
    p.created_at,
    p.party_id,
    party.name      as party_name,
    p.amount,
    p.direction,
    pm.code         as payment_method_code,
    p.notes,
    (p.refund_of_transaction_id is not null) as is_refund
  from public.payment p
  left join public.party party on party.id = p.party_id
  left join public.payment_method pm on pm.id = p.method_id
  where p.shop_id = p_shop_id
    and (p_before    is null or p.occurred_at <  p_before)
    and (p_date_from is null or p.occurred_at >= p_date_from)
    and (p_date_to   is null or p.occurred_at <  p_date_to)
    and (p_party_id  is null or p.party_id = p_party_id)
    and (p_direction is null or p.direction = p_direction)
  order by p.occurred_at desc, p.id desc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.list_payments(uuid, timestamptz, int, timestamptz, timestamptz, uuid, char) from public;
grant execute on function public.list_payments(uuid, timestamptz, int, timestamptz, timestamptz, uuid, char) to authenticated;
