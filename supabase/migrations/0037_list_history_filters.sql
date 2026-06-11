-- Adds date-range + party-id filter params to list_sales / list_receives
-- so the Sale + Receive history screens can ship server-side filtering
-- (necessary because the limit must apply to the filtered set, not the
-- pre-filtered tail). Voided toggle stays client-side — list_* always
-- returns originals with is_voided flagged, and the filter just hides
-- voided rows when the user leaves "include voided" off.
--
-- Signature changes — drop+recreate (we cannot CREATE OR REPLACE across
-- arg-count changes). Existing callers passing only (shop_id, before,
-- limit) keep working because the new params default to null = no
-- filter.

drop function if exists public.list_sales(uuid, timestamptz, int);

create function public.list_sales(
  p_shop_id    uuid,
  p_before     timestamptz default null,
  p_limit      int         default 50,
  p_date_from  timestamptz default null,
  p_date_to    timestamptz default null,
  p_party_id   uuid        default null
)
returns table (
  txn_id              uuid,
  occurred_at         timestamptz,
  posted_at           timestamptz,
  party_id            uuid,
  party_name          text,
  total_amount        numeric,
  paid_amount         numeric,
  payment_method_code text,
  is_voided           boolean,
  reversal_txn_id     uuid,
  voided_at           timestamptz
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list sales for this shop';
  end if;

  return query
  with sales as (
    select t.id, t.occurred_at, t.posted_at, t.party_id, t.total_amount,
           t.paid_amount, t.payment_method_id, t.reverses_transaction_id
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    where t.shop_id = p_shop_id
      and tt.code = 'sale'
  )
  select
    o.id as txn_id,
    o.occurred_at,
    o.posted_at,
    o.party_id,
    p.name as party_name,
    o.total_amount,
    o.paid_amount,
    pm.code as payment_method_code,
    (r.id is not null) as is_voided,
    r.id as reversal_txn_id,
    r.posted_at as voided_at
  from sales o
  left join public.party p on p.id = o.party_id
  left join public.payment_method pm on pm.id = o.payment_method_id
  left join sales r on r.reverses_transaction_id = o.id
  where o.reverses_transaction_id is null
    and (p_before    is null or o.occurred_at <  p_before)
    and (p_date_from is null or o.occurred_at >= p_date_from)
    and (p_date_to   is null or o.occurred_at <  p_date_to)
    and (p_party_id  is null or o.party_id = p_party_id)
  order by o.occurred_at desc, o.id desc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.list_sales(uuid, timestamptz, int, timestamptz, timestamptz, uuid) from public;
grant execute on function public.list_sales(uuid, timestamptz, int, timestamptz, timestamptz, uuid) to authenticated;

drop function if exists public.list_receives(uuid, timestamptz, int);

create function public.list_receives(
  p_shop_id    uuid,
  p_before     timestamptz default null,
  p_limit      int         default 50,
  p_date_from  timestamptz default null,
  p_date_to    timestamptz default null,
  p_party_id   uuid        default null
)
returns table (
  txn_id              uuid,
  occurred_at         timestamptz,
  posted_at           timestamptz,
  party_id            uuid,
  party_name          text,
  total_amount        numeric,
  paid_amount         numeric,
  payment_method_code text,
  is_voided           boolean,
  reversal_txn_id     uuid,
  voided_at           timestamptz
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list receives for this shop';
  end if;

  return query
  with receives as (
    select t.id, t.occurred_at, t.posted_at, t.party_id, t.total_amount,
           t.paid_amount, t.payment_method_id, t.reverses_transaction_id
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    where t.shop_id = p_shop_id
      and tt.code = 'receive'
  )
  select
    o.id as txn_id,
    o.occurred_at,
    o.posted_at,
    o.party_id,
    p.name as party_name,
    o.total_amount,
    o.paid_amount,
    pm.code as payment_method_code,
    (r.id is not null) as is_voided,
    r.id as reversal_txn_id,
    r.posted_at as voided_at
  from receives o
  left join public.party p on p.id = o.party_id
  left join public.payment_method pm on pm.id = o.payment_method_id
  left join receives r on r.reverses_transaction_id = o.id
  where o.reverses_transaction_id is null
    and (p_before    is null or o.occurred_at <  p_before)
    and (p_date_from is null or o.occurred_at >= p_date_from)
    and (p_date_to   is null or o.occurred_at <  p_date_to)
    and (p_party_id  is null or o.party_id = p_party_id)
  order by o.occurred_at desc, o.id desc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.list_receives(uuid, timestamptz, int, timestamptz, timestamptz, uuid) from public;
grant execute on function public.list_receives(uuid, timestamptz, int, timestamptz, timestamptz, uuid) to authenticated;
