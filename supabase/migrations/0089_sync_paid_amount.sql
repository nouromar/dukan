-- 0089_sync_paid_amount.sql
--
-- Bug: a credit (debt) sale opened from the local mirror renders as a fully-paid
-- CASH sale. Root cause: _build_transactions_payload (0070) never included
-- `paid_amount`, and the mobile mirror's toSaleSummary defaults a missing
-- paid_amount to the full total — so every synced credit sale looks fully paid.
--
-- Fix: carry `paid_amount` in the transactions payload (both arms, so the UNION
-- columns stay aligned). Sale/Receive use txn.paid_amount (the at-till cash,
-- fixed at posting); Payment uses its own amount (unused by the sale receipt but
-- keeps the shape consistent). Devices pick it up on the next delta/full sync.

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
    -- Sale / Receive / Expense
    select
      t.id                as txn_id,
      t.shop_id,
      tt.code             as type_code,
      extract(epoch from t.occurred_at) * 1000 as occurred_at_ms,
      t.total_amount      as total,
      t.paid_amount       as paid_amount,
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

    -- Payment
    select
      pay.id              as txn_id,
      pay.shop_id,
      'payment'::text     as type_code,
      extract(epoch from pay.occurred_at) * 1000 as occurred_at_ms,
      pay.amount          as total,
      pay.amount          as paid_amount,
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
