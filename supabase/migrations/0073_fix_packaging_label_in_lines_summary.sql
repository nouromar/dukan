-- 0073_fix_packaging_label_in_lines_summary.sql
--
-- Fix: 0071 introduced lines_summary in `_build_transactions_payload`
-- that references `siu.packaging_label` — but `shop_item_unit` has
-- no such column. The label is DERIVED elsewhere via the helper
-- `public._format_conversion(numeric)` from 0028. The bad SELECT
-- causes every call to `get_shop_full_sync` and
-- `get_transactions_delta` to throw PostgrestException with
-- "column siu.packaging_label does not exist" (code 42703).
--
-- User-visible symptoms before this fix:
--   * "Last synced: Never" on Storage & sync screen.
--   * Re-download all data fails with the 42703 error.
--   * Sale/receive history rows never have `serverUpdatedAtMs>0`,
--     so `postedAt` stays null and void affordance never appears.
--   * "Sync now" toast says "Got N updates" every time because the
--     transactions delta fails silently; `last_synced_at` for
--     transactions never advances, so the same items/parties/cats
--     delta re-fires forever.
--
-- This migration re-creates `_build_transactions_payload` with the
-- SOLE change being how `unit_label` and `packaging_label` are
-- computed: both now derive from `_format_conversion` + the
-- unit's `default_label`, with a fallback to the snapshot's unit
-- code for historical rows whose packaging was deleted.
--
-- Apply with `supabase db push`. Mobile devices need to
-- "Re-download all data" once to pick up corrected data — or
-- "Sync now" once the delta starts succeeding.

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
            -- unit_label / packaging_label DERIVED from the live
            -- shop_item_unit + unit row. shop_item_unit has no
            -- stored packaging_label column — every other RPC
            -- uses _format_conversion (helper from 0028). Fall
            -- back to the snapshot code for rows whose packaging
            -- was deleted so the receipt still renders.
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
