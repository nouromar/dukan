-- 0071_transactions_payload_enrich.sql
--
-- Two related fixes for #385:
--
-- 1) `_build_transactions_payload` (added in 0069, extended for
--    payments in 0070) emitted only a sparse `lines_summary` with
--    line_no, item_name, unit_code, quantity, line_total. The
--    mobile receipt screen needs more — `item_id`,
--    `shop_item_unit_id`, `unit_amount`, `unit_label`,
--    `packaging_label` — to render the middle section of the sale
--    detail. The screen was rendering empty for any sale opened
--    from history; this enriches the payload to match
--    `SaleLineDetail.fromJson` on the client.
--
-- 2) The mobile app now writes an optimistic row to
--    `local_transaction` at enqueue time (so sales appear in
--    history immediately, not after the queue drains + the
--    delta-sync round-trip). When the server's authoritative row
--    arrives via delta sync, the client needs to dedupe-and-
--    replace by `client_op_id`. That means the server payload
--    must carry `client_op_id` for both `txn` and `payment` rows.
--
-- Recreates the helper; `get_shop_full_sync`/`get_transactions_delta`
-- already delegate to it, no changes there.

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
    -- Sale / Receive / Expense ------------------------------------
    select
      t.id                                       as txn_id,
      t.shop_id,
      tt.code                                    as type_code,
      extract(epoch from t.occurred_at) * 1000   as occurred_at_ms,
      t.total_amount                             as total,
      t.party_id,
      p.name                                     as party_name,
      pm.code                                    as payment_method_code,
      t.reverses_transaction_id is not null      as is_voided,
      extract(epoch from t.created_at) * 1000    as server_updated_at_ms,
      null::text                                 as direction,
      null::text                                 as notes,
      false                                      as is_refund,
      t.client_op_id                             as client_op_id,
      (
        select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb)
        from (
          select
            tl.line_no,
            tl.item_id,
            tl.shop_item_unit_id,
            tl.item_name_snapshot       as item_name,
            tl.unit_code_snapshot       as unit_code,
            -- unit_label / packaging_label come from the live
            -- shop_item_unit row when available. For historical
            -- rows whose packaging was deleted, fall back to the
            -- snapshot code so the receipt still renders.
            coalesce(siu.packaging_label, tl.unit_code_snapshot)
                                        as unit_label,
            siu.packaging_label         as packaging_label,
            tl.quantity,
            tl.unit_amount,
            tl.line_total
          from public.transaction_line tl
          left join public.shop_item_unit siu
                 on siu.shop_id = tl.shop_id
                and siu.id      = tl.shop_item_unit_id
          where tl.shop_id = t.shop_id
            and tl.transaction_id = t.id
        ) l
      )                                          as lines_summary,
      t.created_at                               as created_at_for_sort
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    left join public.party p          on p.id = t.party_id
    left join public.payment_method pm on pm.id = t.payment_method_id
    where t.shop_id = p_shop_id
      and (p_since is null or t.created_at > p_since)

    union all

    -- Payment -----------------------------------------------------
    select
      pay.id                                     as txn_id,
      pay.shop_id,
      'payment'::text                            as type_code,
      extract(epoch from pay.occurred_at) * 1000 as occurred_at_ms,
      pay.amount                                 as total,
      pay.party_id,
      pp.name                                    as party_name,
      pmm.code                                   as payment_method_code,
      false                                      as is_voided,
      extract(epoch from pay.created_at) * 1000  as server_updated_at_ms,
      pay.direction                              as direction,
      pay.notes                                  as notes,
      (pay.refund_of_transaction_id is not null) as is_refund,
      pay.client_op_id                           as client_op_id,
      '[]'::jsonb                                as lines_summary,
      pay.created_at                             as created_at_for_sort
    from public.payment pay
    left join public.party pp           on pp.id = pay.party_id
    left join public.payment_method pmm on pmm.id = pay.method_id
    where pay.shop_id = p_shop_id
      and (p_since is null or pay.created_at > p_since)

    order by created_at_for_sort desc
    limit greatest(p_limit, 1)
  ) r;

  return jsonb_build_object('transactions', v_rows);
end;
$$;
