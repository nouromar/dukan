-- 0070_payment_in_sync.sql
--
-- Payments live in their own `public.payment` table (not in
-- `public.txn` which holds sale/receive/expense). The transactions
-- payload helper introduced in 0069 only scanned `txn`, so the
-- mobile mirror's `local_transaction` table never received any
-- 'payment' rows — Payment History rendered empty even after a
-- successful full sync.
--
-- This migration replaces `_build_transactions_payload` to UNION
-- ALL with a payment-side SELECT, mapping every payment row into
-- the same payload shape the mobile side already consumes for the
-- other transaction types. Mobile expects:
--   txn_id, shop_id, type_code='payment', occurred_at_ms, total,
--   party_id, party_name, payment_method_code, is_voided,
--   server_updated_at_ms, direction, notes, is_refund, plus an
--   empty lines_summary so the JSON shape matches.
--
-- The `get_shop_full_sync` and `get_transactions_delta` RPCs from
-- 0069 already delegate to this helper, so no changes there.

create or replace function public._build_transactions_payload(
  p_shop_id uuid,
  p_since   timestamptz,
  p_limit   int
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at_for_sort desc), '[]'::jsonb)
    into v_rows
  from (
    -- Sale / Receive / Expense (existing path)
    select
      t.id                as txn_id,
      t.shop_id,
      tt.code             as type_code,
      extract(epoch from t.occurred_at) * 1000 as occurred_at_ms,
      t.total_amount      as total,
      t.party_id,
      p.name              as party_name,
      pm.code             as payment_method_code,
      t.reverses_transaction_id is not null
                          as is_voided,
      extract(epoch from t.created_at) * 1000 as server_updated_at_ms,
      null::text          as direction,
      null::text          as notes,
      false               as is_refund,
      (
        select coalesce(jsonb_agg(to_jsonb(l)), '[]'::jsonb)
        from (
          select
            tl.line_no,
            tl.item_name_snapshot         as item_name,
            tl.unit_code_snapshot         as unit_code,
            tl.quantity,
            tl.line_total
          from public.transaction_line tl
          where tl.shop_id = t.shop_id
            and tl.transaction_id = t.id
          order by tl.line_no
        ) l
      )                   as lines_summary,
      t.created_at        as created_at_for_sort
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    left join public.party p on p.id = t.party_id
    left join public.payment_method pm on pm.id = t.payment_method_id
    where t.shop_id = p_shop_id
      and (p_since is null or t.created_at > p_since)

    union all

    -- Payment (new path — was missing from 0069)
    select
      pay.id              as txn_id,
      pay.shop_id,
      'payment'::text     as type_code,
      extract(epoch from pay.occurred_at) * 1000 as occurred_at_ms,
      pay.amount          as total,
      pay.party_id,
      pp.name             as party_name,
      pmm.code            as payment_method_code,
      false               as is_voided,
      extract(epoch from pay.created_at) * 1000 as server_updated_at_ms,
      pay.direction       as direction,
      pay.notes           as notes,
      (pay.refund_of_transaction_id is not null) as is_refund,
      '[]'::jsonb         as lines_summary,
      pay.created_at      as created_at_for_sort
    from public.payment pay
    left join public.party pp on pp.id = pay.party_id
    left join public.payment_method pmm on pmm.id = pay.method_id
    where pay.shop_id = p_shop_id
      and (p_since is null or pay.created_at > p_since)

    order by created_at_for_sort desc
    limit greatest(p_limit, 1)
  ) r;

  return jsonb_build_object('transactions', v_rows);
end;
$$;
