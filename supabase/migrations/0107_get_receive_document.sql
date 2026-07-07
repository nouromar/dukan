-- 0107_get_receive_document.sql
--
-- View-bono feature: get_receive now returns the attached bono's document_id +
-- storage_path, so the receive detail screen can show the original photo. The
-- txn already carries document_id (0009); we left-join document for its path.
--
-- Append-only (0030 is already applied on hosted, so an in-place edit there
-- would never reach it). CREATE OR REPLACE can't change a function's OUT
-- columns, so drop first.

drop function if exists public.get_receive(uuid, uuid);

create or replace function public.get_receive(
  p_shop_id uuid,
  p_txn_id uuid
)
returns table (
  txn_id uuid,
  occurred_at timestamptz,
  posted_at timestamptz,
  party_id uuid,
  party_name text,
  total_amount numeric,
  paid_amount numeric,
  payment_method_code text,
  is_voided boolean,
  reversal_txn_id uuid,
  voided_at timestamptz,
  document_id uuid,
  document_path text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to view receives for this shop';
  end if;

  return query
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
    r.posted_at as voided_at,
    o.document_id,
    d.storage_path as document_path
  from public.txn o
  join public.transaction_type tt on tt.id = o.type_id
  left join public.party p on p.id = o.party_id
  left join public.payment_method pm on pm.id = o.payment_method_id
  left join public.txn r
    on r.shop_id = o.shop_id and r.reverses_transaction_id = o.id
  left join public.document d
    on d.shop_id = o.shop_id and d.id = o.document_id
  where o.shop_id = p_shop_id
    and o.id = p_txn_id
    and tt.code = 'receive'
    and o.reverses_transaction_id is null;
end;
$$;

revoke all on function public.get_receive(uuid, uuid) from public;
grant execute on function public.get_receive(uuid, uuid) to authenticated;
