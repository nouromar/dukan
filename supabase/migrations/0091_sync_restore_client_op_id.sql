-- 0091_sync_restore_client_op_id.sql
--
-- Regression fix: on useLocalDb shops every on-device sale/receive shows up
-- TWICE — once as the optimistic local row (written at SAVE time with
-- txn_id = client_op_id), once as the server-synced row.
--
-- Root cause: `_build_transactions_payload` re-created in 0089 (to add
-- paid_amount) accidentally DROPPED the `client_op_id` column that 0073
-- carried. The mobile dedup in applyTransactionsPayload keys on
-- client_op_id ("DELETE the optimistic row WHERE client_op_id = ? AND
-- txn_id != ?"); with the server payload's client_op_id null, that dedup is
-- skipped and the optimistic row survives beside the authoritative one.
--
-- Fix: re-create the function keeping 0089's paid_amount AND restoring
-- client_op_id in both UNION arms. Apply with `supabase db push`; existing
-- duplicates clear once devices "Re-download all data" (a full sync re-sends
-- every row with client_op_id, so the dedup finally fires).

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
      t.client_op_id      as client_op_id,
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
      pay.client_op_id    as client_op_id,
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
