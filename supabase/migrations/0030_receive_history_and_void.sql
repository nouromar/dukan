-- Receive history read RPCs. Three RPCs: list_receives / get_receive /
-- get_receive_lines.
--
-- The fourth RPC, `void_receive`, was merged into 0010_posting_rpcs.sql
-- alongside the other write-path RPCs (see data-model-v2 §7
-- sanctioned-writers rule). Same-day window, owner-only, and the
-- "no subsequent stock activity" guard all carried over.

-- ---- list_receives --------------------------------------------------------

create or replace function public.list_receives(
  p_shop_id uuid,
  p_before timestamptz default null,
  p_limit int default 50
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
  voided_at timestamptz
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to list receives for this shop';
  end if;

  return query
  with receives as (
    select t.id, t.occurred_at, t.posted_at, t.party_id, t.total_amount,
           t.paid_amount, t.payment_method_id, t.reverses_transaction_id
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    where t.shop_id = p_shop_id
      and tt.code = 'receive'
  )
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
    r.posted_at as voided_at
  from receives o
  left join public.party p on p.id = o.party_id
  left join public.payment_method pm on pm.id = o.payment_method_id
  left join receives r on r.reverses_transaction_id = o.id
  where o.reverses_transaction_id is null
    and (p_before is null or o.occurred_at < p_before)
  order by o.occurred_at desc, o.id desc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.list_receives(uuid, timestamptz, int) from public;
grant execute on function public.list_receives(uuid, timestamptz, int) to authenticated;

-- ---- get_receive ----------------------------------------------------------

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
  voided_at timestamptz
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
    r.posted_at as voided_at
  from public.txn o
  join public.transaction_type tt on tt.id = o.type_id
  left join public.party p on p.id = o.party_id
  left join public.payment_method pm on pm.id = o.payment_method_id
  left join public.txn r
    on r.shop_id = o.shop_id and r.reverses_transaction_id = o.id
  where o.shop_id = p_shop_id
    and o.id = p_txn_id
    and tt.code = 'receive'
    and o.reverses_transaction_id is null;
end;
$$;

revoke all on function public.get_receive(uuid, uuid) from public;
grant execute on function public.get_receive(uuid, uuid) to authenticated;

-- ---- get_receive_lines ----------------------------------------------------
--
-- The bono receipt. unit_amount on a receive line is the per-receive-
-- unit cost the cashier typed (matches the price-pre-fill convention).
-- `packaging_label` is derived from the snapshot fields exactly like
-- get_sale_lines uses `public._format_conversion` (defined in 0028).

create or replace function public.get_receive_lines(
  p_shop_id uuid,
  p_txn_id uuid
)
returns table (
  line_no int,
  item_id uuid,
  shop_item_unit_id uuid,
  item_name text,
  quantity numeric,
  unit_label text,
  unit_amount numeric,
  line_total numeric,
  packaging_label text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to view receive lines for this shop';
  end if;

  return query
  with base as (
    select
      tl.line_no,
      tl.item_id,
      tl.shop_item_unit_id,
      tl.item_name_snapshot,
      tl.quantity,
      tl.unit_amount,
      tl.line_total,
      tl.unit_code_snapshot,
      tl.unit_conversion_to_base_snapshot,
      si.base_unit_code
    from public.transaction_line tl
    left join public.shop_item si
      on si.shop_id = tl.shop_id and si.id = tl.item_id
    where tl.shop_id = p_shop_id
      and tl.transaction_id = p_txn_id
  )
  select
    b.line_no,
    b.item_id,
    b.shop_item_unit_id,
    coalesce(b.item_name_snapshot, '(unnamed)') as item_name,
    b.quantity,
    coalesce(u.default_label, b.unit_code_snapshot) as unit_label,
    b.unit_amount,
    b.line_total,
    case
      when b.unit_code_snapshot is null then null
      when b.unit_conversion_to_base_snapshot = 1
        then coalesce(u.default_label, b.unit_code_snapshot)
      else
        public._format_conversion(b.unit_conversion_to_base_snapshot)
        || ' '
        || coalesce(bu.default_label, b.base_unit_code)
        || ' '
        || coalesce(u.default_label, b.unit_code_snapshot)
    end as packaging_label
  from base b
  left join public.unit u on u.code = b.unit_code_snapshot
  left join public.unit bu on bu.code = b.base_unit_code
  order by b.line_no;
end;
$$;

revoke all on function public.get_receive_lines(uuid, uuid) from public;
grant execute on function public.get_receive_lines(uuid, uuid) to authenticated;

-- void_receive is owned by 0010_posting_rpcs.sql (post-v2 merge).
-- Earlier drafts of this file tried to DROP a stale signature here —
-- but the canonical signature `(uuid, uuid, text)` never changed, so
-- the drop would clobber the live function. Nothing to clean up here.
