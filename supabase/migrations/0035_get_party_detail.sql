-- ---------------------------------------------------------------------------
-- get_party_detail — header (name, phone, type, balances) plus the last N
-- transactions involving this party. Powers the Party detail screen
-- (V1-E), which lets the shopkeeper open a customer/supplier directly
-- to see what they owe and pay it down.
--
-- Returns one jsonb object: { header, sales, receives, payments }.
-- ---------------------------------------------------------------------------

create or replace function public.get_party_detail(
  p_shop_id  uuid,
  p_party_id uuid,
  p_limit    int default 20
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_header   jsonb;
  v_sales    jsonb;
  v_receives jsonb;
  v_payments jsonb;
  v_limit    int := greatest(1, least(coalesce(p_limit, 20), 100));
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to read this shop';
  end if;

  select to_jsonb(h) into v_header
  from (
    select
      p.id,
      p.name,
      p.phone,
      pt.code as type_code,
      p.receivable,
      p.payable,
      p.is_active
    from public.party p
    join public.party_type pt on pt.id = p.type_id
    where p.shop_id = p_shop_id and p.id = p_party_id
  ) h;

  if v_header is null then
    raise exception 'party % not found in shop %', p_party_id, p_shop_id;
  end if;

  select coalesce(jsonb_agg(to_jsonb(row) order by row.occurred_at desc), '[]'::jsonb)
  into v_sales
  from (
    select
      t.id as txn_id,
      t.occurred_at,
      t.total_amount,
      t.paid_amount,
      (t.reverses_transaction_id is not null
       or exists (
         select 1 from public.txn rev
         where rev.reverses_transaction_id = t.id
       )) as is_voided
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    where t.shop_id = p_shop_id
      and t.party_id = p_party_id
      and tt.code = 'sale'
    order by t.occurred_at desc
    limit v_limit
  ) row;

  select coalesce(jsonb_agg(to_jsonb(row) order by row.occurred_at desc), '[]'::jsonb)
  into v_receives
  from (
    select
      t.id as txn_id,
      t.occurred_at,
      t.total_amount,
      t.paid_amount,
      (t.reverses_transaction_id is not null
       or exists (
         select 1 from public.txn rev
         where rev.reverses_transaction_id = t.id
       )) as is_voided
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    where t.shop_id = p_shop_id
      and t.party_id = p_party_id
      and tt.code = 'receive'
    order by t.occurred_at desc
    limit v_limit
  ) row;

  select coalesce(jsonb_agg(to_jsonb(row) order by row.occurred_at desc), '[]'::jsonb)
  into v_payments
  from (
    select
      pay.id as payment_id,
      pay.occurred_at,
      pay.amount,
      pay.direction
    from public.payment pay
    where pay.shop_id = p_shop_id
      and pay.party_id = p_party_id
    order by pay.occurred_at desc
    limit v_limit
  ) row;

  return jsonb_build_object(
    'header', v_header,
    'sales', v_sales,
    'receives', v_receives,
    'payments', v_payments
  );
end;
$$;

revoke all on function public.get_party_detail(uuid, uuid, int) from public;
grant execute on function public.get_party_detail(uuid, uuid, int) to authenticated;
