-- 0116_sync_void_state.sql
--
-- Make void state converge across devices via sync. Today a void is an
-- append-only reversal row; the original is never edited (immutability), and
-- `is_voided` is DERIVED in the sync payload. But 0111 derived it as
-- `reverses_* IS NOT NULL` — which flags only the reversal MARKER, never the
-- reversed ORIGINAL — and the delta is append-only (keyed on created_at), so a
-- reversed original is never re-shipped. Net: a sale/receive/expense voided on
-- device A shows voided on A (optimistic local flag) but NOT on device B, and
-- a full re-sync un-voids it even on A. Payments were worse — `is_voided` was
-- hardcoded `false`, so payment voids never synced at all (and voided payments
-- would wrongly count in money-in/out after a resync).
--
-- Fix (no edit to any immutable row — just a corrected derivation + delivery):
--   1. is_voided = reverses_* IS NOT NULL OR EXISTS(a reversal of me). Now a
--      reversed original derives `true`, on every device, on full OR delta sync.
--   2. Re-emit the original when its reversal is newer than the cursor, so the
--      corrected flag rides the normal delta (not only a full re-sync). The
--      re-emitted original keeps its old created_at, so it neither advances the
--      cursor nor jumps in history ordering.
--   3. Add `is_reversal` (the row IS a reversal/command row) so the client can
--      hide those command rows from history while still showing the struck-
--      through original. Distinguishes a reversal marker (is_reversal=true)
--      from a reversed original (is_voided=true, is_reversal=false) — both
--      carry is_voided=true otherwise.
--
-- Columns are otherwise byte-identical to 0111 (client_op_id, paid_amount,
-- lines_summary, document_id/path, direction, notes, is_refund are all
-- load-bearing — see the §SS harness guards). After `supabase db push`, devices
-- "Re-download all data" once to pick up corrected flags for pre-existing voids.

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
      -- Voided iff this row IS a reversal OR a reversal of it exists. The
      -- second arm is what makes a reversed ORIGINAL derive true on every
      -- device (the fix); the delta re-emits it via the WHERE clause below.
      (
        t.reverses_transaction_id is not null
        or exists (
          select 1 from public.txn rev
          where rev.reverses_transaction_id = t.id
        )
      )                   as is_voided,
      -- The row itself is the reversal/command row (hide from history lists).
      (t.reverses_transaction_id is not null) as is_reversal,
      extract(epoch from t.created_at) * 1000 as server_updated_at_ms,
      null::text          as direction,
      null::text          as notes,
      false               as is_refund,
      t.document_id       as document_id,
      d.storage_path      as document_path,
      (
        select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb)
        from (
          select
            tl.line_no,
            tl.item_id,
            tl.shop_item_unit_id,
            tl.item_name_snapshot       as item_name,
            tl.unit_code_snapshot       as unit_code,
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
    left join public.document d on d.shop_id = t.shop_id and d.id = t.document_id
    where t.shop_id = p_shop_id
      and (
        p_since is null
        or t.created_at > p_since
        -- Re-emit an original whose reversal is newer than the cursor so the
        -- corrected is_voided reaches this device on the normal delta.
        or exists (
          select 1 from public.txn rev
          where rev.reverses_transaction_id = t.id
            and rev.created_at > p_since
        )
      )

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
      -- Was hardcoded false → payment voids never synced. Same derivation as
      -- txns now: this row is a reversal, or a reversal of it exists.
      (
        pay.reverses_payment_id is not null
        or exists (
          select 1 from public.payment rev
          where rev.shop_id = pay.shop_id
            and rev.reverses_payment_id = pay.id
        )
      )                   as is_voided,
      (pay.reverses_payment_id is not null) as is_reversal,
      extract(epoch from pay.created_at) * 1000 as server_updated_at_ms,
      pay.direction       as direction,
      pay.notes           as notes,
      (pay.refund_of_transaction_id is not null) as is_refund,
      null::uuid          as document_id,
      null::text          as document_path,
      '[]'::jsonb         as lines_summary,
      pay.created_at      as created_at_for_sort
    from public.payment pay
    left join public.party pp on pp.id = pay.party_id
    left join public.payment_method pmm on pmm.id = pay.method_id
    where pay.shop_id = p_shop_id
      and (
        p_since is null
        or pay.created_at > p_since
        or exists (
          select 1 from public.payment rev
          where rev.shop_id = pay.shop_id
            and rev.reverses_payment_id = pay.id
            and rev.created_at > p_since
        )
      )

    order by created_at_for_sort desc
    limit greatest(p_limit, 1)
  ) r;

  return jsonb_build_object('transactions', v_rows);
end;
$$;
