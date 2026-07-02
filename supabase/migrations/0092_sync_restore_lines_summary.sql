-- 0092_sync_restore_lines_summary.sql
--
-- Regression fix (same root cause as 0091): rebuilding
-- `_build_transactions_payload` in 0089 was based on the older 0070 body and
-- clobbered the richer lines_summary that 0073 had established. The dropped
-- per-line fields — unit_amount, unit_label, packaging_label, item_id,
-- shop_item_unit_id — are exactly what SaleLineDetail.fromJson reads, so on a
-- useLocalDb shop the sale/receive receipt renders each line as
-- "1  × — = $1.50": empty unit label and a "—" for the missing unit price.
--
-- Fix: re-create the function with 0073's full lines_summary restored, while
-- keeping 0089's paid_amount and 0091's client_op_id on the outer rows. This
-- is the complete, correct payload — no further re-download should be needed
-- after this one.
--
-- Apply with `supabase db push`; devices "Re-download all data" once so local
-- rows pick up the full line snapshots.

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
        select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb)
        from (
          select
            tl.line_no,
            tl.item_id,
            tl.shop_item_unit_id,
            tl.item_name_snapshot       as item_name,
            tl.unit_code_snapshot       as unit_code,
            -- unit_label / packaging_label DERIVED from the live
            -- shop_item_unit + unit row. shop_item_unit has no stored
            -- packaging_label column — every RPC uses _format_conversion
            -- (helper from 0028). Fall back to the snapshot code for rows
            -- whose packaging was deleted so the receipt still renders.
            case
              when siu.id is null
                then tl.unit_code_snapshot
              when siu.conversion_to_base = 1
                then u.default_label
              else public._format_conversion(siu.conversion_to_base)
                   || ' ' || u.default_label
            end                          as unit_label,
            case
              when siu.id is null
                then tl.unit_code_snapshot
              when siu.conversion_to_base = 1
                then u.default_label
              else public._format_conversion(siu.conversion_to_base)
                   || ' ' || u.default_label
            end                          as packaging_label,
            tl.quantity,
            tl.unit_amount,
            tl.line_total
          from public.transaction_line tl
          left join public.shop_item_unit siu
                 on siu.shop_id = tl.shop_id
                and siu.id      = tl.shop_item_unit_id
          left join public.unit u
                 on u.code = siu.unit_code
          where tl.shop_id = t.shop_id
            and tl.transaction_id = t.id
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
