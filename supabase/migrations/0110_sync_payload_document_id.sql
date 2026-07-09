-- 0110_sync_payload_document_id.sql
--
-- Bug fix: a bono-linked receive lost its "View bono" button after syncing.
--
-- The receive-detail screen shows View bono when its header carries a
-- document_id. The optimistic (just-saved) local row carries it (the app writes
-- document_id into the mirror payload), but `_build_transactions_payload` — the
-- server function whose output replaces that row on the next delta sync — never
-- selected document_id. So once a bono receive synced, the mirror row lost the
-- link and the button vanished (a second, still-optimistic receive kept it,
-- which is how the "same bono twice → only the first is broken" repro surfaced).
--
-- Fix: re-create the function (copied from 0092, the current full definition)
-- with `document_id` AND `document_path` added to both UNION branches —
-- `t.document_id` + the joined `document.storage_path` for transaction rows,
-- `null` for payments (payments have no bono). document_id keys the on-device
-- cache; document_path lets "View bono" sign a Storage URL when the cache is
-- empty (e.g. after a reinstall, where the synced mirror is the only source —
-- without the path the button shows "Bono photo unavailable"). The client reads
-- both from the payload (LocalRepository.toSaleSummary). Apply with
-- `supabase db push`; devices re-download once so synced rows pick up the link.

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
      t.document_id       as document_id,   -- bono link → View bono survives sync
      d.storage_path      as document_path, -- Storage fallback when cache is empty
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
    left join public.document d on d.shop_id = t.shop_id and d.id = t.document_id
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
      null::uuid          as document_id,   -- payments have no bono
      null::text          as document_path,
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
