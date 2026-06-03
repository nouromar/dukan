-- Receive history + narrow same-shift void.
--
-- Scope intentionally tighter than sale void (decisions.md Q12):
--   * Same-day window (not 7 days). Receives are paper-anchored and
--     mistakes are usually caught while the bono is still on the
--     counter. After today, the cashier should reach for Returns
--     (v1.1 — first-class returns are deferred per CLAUDE.md).
--   * Owner-only.
--   * Refuses if ANY item on the receive has been sold (or had any
--     other stock movement) AFTER this receive posted. The void would
--     otherwise push current_stock negative or unwind cost basis we
--     already used to price a later sale.
--   * No refund parameter — v1 receives always post as fully credit
--     (paid_amount = 0). If we ever exercise cash-paid-at-receive,
--     the refund direction is supplier → shop (direction='I'), but
--     that case isn't reachable from the current UI.
--
-- Pitched at the cashier as a typo-only fix. Real-world supplier
-- returns / damaged goods belong in the v1.1 Returns slice.

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

create or replace function public.get_receive_lines(
  p_shop_id uuid,
  p_txn_id uuid
)
returns table (
  line_no int,
  item_id uuid,
  item_name text,
  quantity numeric,
  unit_label text,
  unit_amount numeric,
  line_total numeric
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
  select
    tl.line_no,
    tl.item_id,
    coalesce(tl.item_name_snapshot, i.name) as item_name,
    tl.quantity,
    coalesce(u.default_label, tl.unit_code_snapshot) as unit_label,
    tl.unit_amount,
    tl.line_total
  from public.transaction_line tl
  left join public.item i on i.id = tl.item_id
  left join public.unit u on u.code = tl.unit_code_snapshot
  where tl.shop_id = p_shop_id
    and tl.transaction_id = p_txn_id
  order by tl.line_no;
end;
$$;

revoke all on function public.get_receive_lines(uuid, uuid) from public;
grant execute on function public.get_receive_lines(uuid, uuid) to authenticated;

-- ---- void_receive ---------------------------------------------------------

create or replace function public.void_receive(
  p_shop_id uuid,
  p_txn_id uuid,
  p_client_op_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_replay uuid;
  v_existing_reversal_id uuid;
  v_original_type_code text;
  v_original_posted_at timestamptz;
  v_original_party_id uuid;
  v_original_total numeric;
  v_original_paid numeric;
  v_original_payment_method_id uuid;
  v_unpaid numeric;
  v_party_payable numeric;
  v_reversal_txn_id uuid;
  v_receive_type_id uuid;
  v_posted_status_id uuid;
  v_now timestamptz := pg_catalog.now();
  -- Narrow window: same calendar day in the server's tz. The intent
  -- is "caught it on the same shift" — generous enough to span a long
  -- shift, tight enough to keep cashiers from using void for returns.
  v_void_window interval := interval '24 hours';
  r record;
  v_new_line_id uuid;
  v_existing_movement_unit_cost numeric;
  v_post_receive_movement_id uuid;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only the shop owner can void a receive';
  end if;

  if p_client_op_id is not null then
    select id into v_existing_replay
    from public.txn
    where shop_id = p_shop_id and client_op_id = p_client_op_id;
    if v_existing_replay is not null then
      return v_existing_replay;
    end if;
  end if;

  -- Lock + validate original.
  select tt.code, t.posted_at, t.party_id, t.total_amount,
         t.paid_amount, t.payment_method_id
  into v_original_type_code, v_original_posted_at,
       v_original_party_id, v_original_total, v_original_paid,
       v_original_payment_method_id
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  where t.shop_id = p_shop_id
    and t.id = p_txn_id
    and t.reverses_transaction_id is null
  for update of t;

  if v_original_type_code is null then
    raise exception 'Receive not found (or it is itself a reversal)';
  end if;
  if v_original_type_code <> 'receive' then
    raise exception 'void_receive only voids receive transactions';
  end if;
  if v_original_posted_at is null then
    raise exception 'Receive has no posted_at — cannot void';
  end if;
  if v_original_posted_at < v_now - v_void_window then
    raise exception
      'Receive is outside the same-shift void window (%). Use a return instead.',
      v_void_window;
  end if;

  -- Already voided?
  select id into v_existing_reversal_id
  from public.txn
  where shop_id = p_shop_id and reverses_transaction_id = p_txn_id;
  if v_existing_reversal_id is not null then
    raise exception 'Receive was already voided';
  end if;

  -- Stock-movement guard: refuse if anything happened on any of this
  -- receive's items after it posted. That covers sales of received
  -- stock, inventory adjustments, or any further receives that may
  -- have changed avg_cost. The cashier corrects those by hand-rolling
  -- the right operation, not by a blanket reversal.
  -- Any later stock movement on any item from this receive (other than
  -- the receive's own movements) blocks the void. `>=` because rapid
  -- back-to-back ops (e.g., harness test or real-world batch) can share
  -- a transaction timestamp; the line-id exclusion still keeps the
  -- receive's own movements out of the match.
  if exists (
    select 1
    from public.stock_movement later
    where later.shop_id = p_shop_id
      and later.item_id in (
        select tl.item_id
        from public.transaction_line tl
        where tl.shop_id = p_shop_id and tl.transaction_id = p_txn_id
      )
      and later.occurred_at >= v_original_posted_at
      and (
        later.transaction_line_id is null
        or later.transaction_line_id not in (
          select tl.id
          from public.transaction_line tl
          where tl.shop_id = p_shop_id and tl.transaction_id = p_txn_id
        )
      )
  ) then
    raise exception
      'One or more items from this receive have had stock activity since. '
      'Void blocked.';
  end if;

  -- Partial-paid guard (mirror of sale): if the shop has already paid
  -- the supplier some money against this bono, refuse — the cashier
  -- should record a refund-from-supplier payment manually.
  v_unpaid := v_original_total - v_original_paid;
  if v_unpaid > 0 and v_original_party_id is not null then
    select payable into v_party_payable
    from public.party
    where shop_id = p_shop_id and id = v_original_party_id
    for update;
    if v_party_payable < v_unpaid then
      raise exception
        'Shop has paid down some of this bono; void blocked. '
        'Record a refund payment from the supplier instead.';
    end if;
  end if;

  v_receive_type_id := public._ref_id('transaction_type', 'receive');
  v_posted_status_id := public._ref_id('transaction_status', 'posted');

  -- Reversal header. Same positive amounts; semantics from
  -- reverses_transaction_id.
  insert into public.txn (
    shop_id, type_id, status_id, party_id, occurred_at, posted_at,
    total_amount, paid_amount, payment_method_id,
    reverses_transaction_id, client_op_id, notes, created_by
  )
  values (
    p_shop_id, v_receive_type_id, v_posted_status_id, v_original_party_id,
    v_now, v_now,
    v_original_total, v_original_paid, v_original_payment_method_id,
    p_txn_id, p_client_op_id,
    'Reversal of receive ' || p_txn_id::text,
    auth.uid()
  )
  returning id into v_reversal_txn_id;

  -- Mirror the lines; opposite-sign stock movements undo the receive.
  for r in
    select tl.id as original_line_id, tl.line_no, tl.item_id, tl.quantity,
           tl.unit_id, tl.base_quantity, tl.unit_amount,
           tl.item_name_snapshot, tl.unit_code_snapshot,
           tl.unit_conversion_to_base_snapshot, tl.catalog_revision_id,
           tl.line_total
    from public.transaction_line tl
    where tl.shop_id = p_shop_id and tl.transaction_id = p_txn_id
    order by tl.line_no
  loop
    insert into public.transaction_line (
      shop_id, transaction_id, line_no, item_id, quantity, unit_id,
      base_quantity, unit_amount, item_name_snapshot, unit_code_snapshot,
      unit_conversion_to_base_snapshot, catalog_revision_id, line_total
    )
    values (
      p_shop_id, v_reversal_txn_id, r.line_no, r.item_id, r.quantity,
      r.unit_id, r.base_quantity, r.unit_amount, r.item_name_snapshot,
      r.unit_code_snapshot, r.unit_conversion_to_base_snapshot,
      r.catalog_revision_id, r.line_total
    )
    returning id into v_new_line_id;

    select unit_cost into v_existing_movement_unit_cost
    from public.stock_movement
    where shop_id = p_shop_id and transaction_line_id = r.original_line_id
    limit 1;

    -- Receive's stock_movement was +base_quantity. Reversal is
    -- -base_quantity.
    insert into public.stock_movement (
      shop_id, item_id, transaction_line_id, quantity_delta,
      unit_cost, occurred_at
    )
    values (
      p_shop_id, r.item_id, v_new_line_id, -r.base_quantity,
      v_existing_movement_unit_cost, v_now
    );

    update public.item
    set current_stock = current_stock - r.base_quantity
    where shop_id = p_shop_id and id = r.item_id;
  end loop;

  -- Reverse the payable.
  if v_unpaid > 0 and v_original_party_id is not null then
    update public.party
    set payable = payable - v_unpaid
    where shop_id = p_shop_id and id = v_original_party_id;
  end if;

  return v_reversal_txn_id;
exception
  when unique_violation then
    if p_client_op_id is not null then
      select id into v_existing_replay
      from public.txn
      where shop_id = p_shop_id and client_op_id = p_client_op_id;
      if v_existing_replay is not null then
        return v_existing_replay;
      end if;
    end if;
    raise;
end;
$$;

revoke all on function public.void_receive(uuid, uuid, text) from public;
grant execute on function public.void_receive(uuid, uuid, text) to authenticated;
