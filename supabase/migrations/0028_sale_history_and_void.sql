-- Sale history + void. Three read RPCs (list / get header / get lines)
-- and one write RPC that creates a reversing transaction per the
-- architecture rule "posted transactions are immutable; corrections
-- via reversing entries" (decisions.md Q12).
--
-- Read RPCs: any shop member (cashier or owner).
-- void_sale: owner-only, 7-day window, refuses if already voided or
-- if the customer has paid down the receivable since.

-- ---- list_sales -----------------------------------------------------------
--
-- Returns originals only (reverses_transaction_id IS NULL) with a flag
-- + reversal id when a reversal exists. Reverse-chronological,
-- paginated by `p_before` cursor (typically the oldest occurred_at the
-- caller has seen).

create or replace function public.list_sales(
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
    raise exception 'Not allowed to list sales for this shop';
  end if;

  return query
  with sales as (
    select t.id, t.occurred_at, t.posted_at, t.party_id, t.total_amount,
           t.paid_amount, t.payment_method_id, t.reverses_transaction_id
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    where t.shop_id = p_shop_id
      and tt.code = 'sale'
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
  from sales o
  left join public.party p on p.id = o.party_id
  left join public.payment_method pm on pm.id = o.payment_method_id
  left join sales r on r.reverses_transaction_id = o.id
  where o.reverses_transaction_id is null
    and (p_before is null or o.occurred_at < p_before)
  order by o.occurred_at desc, o.id desc
  limit greatest(p_limit, 1);
end;
$$;

revoke all on function public.list_sales(uuid, timestamptz, int) from public;
grant execute on function public.list_sales(uuid, timestamptz, int) to authenticated;

-- ---- get_sale -------------------------------------------------------------
--
-- Single-row variant of list_sales for the detail screen. Returns null
-- if the txn isn't a sale or doesn't belong to this shop.

create or replace function public.get_sale(
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
    raise exception 'Not allowed to view sales for this shop';
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
    and tt.code = 'sale'
    and o.reverses_transaction_id is null;
end;
$$;

revoke all on function public.get_sale(uuid, uuid) from public;
grant execute on function public.get_sale(uuid, uuid) to authenticated;

-- ---- get_sale_lines -------------------------------------------------------
--
-- Item lines for one sale. Snapshots (item_name_snapshot,
-- unit_code_snapshot) ensure the detail keeps reading correctly even
-- if the underlying item was renamed or its units changed after the
-- sale posted.

create or replace function public.get_sale_lines(
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
    raise exception 'Not allowed to view sale lines for this shop';
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

revoke all on function public.get_sale_lines(uuid, uuid) from public;
grant execute on function public.get_sale_lines(uuid, uuid) to authenticated;

-- ---- void_sale ------------------------------------------------------------
--
-- Creates a reversing transaction that nets the original to zero
-- (stock + receivable both reverted). Owner-only, 7-day window.
-- Refuses when the customer has already paid down the receivable
-- created by this sale — that case requires a manual correction
-- (issuing credit or a refund payment) outside the void scope.

create or replace function public.void_sale(
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
  v_party_receivable numeric;
  v_reversal_txn_id uuid;
  v_sale_type_id uuid;
  v_posted_status_id uuid;
  v_now timestamptz := pg_catalog.now();
  v_void_window interval := interval '7 days';
  r record;
  v_new_line_id uuid;
  v_existing_movement_unit_cost numeric;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only the shop owner can void a sale';
  end if;

  -- Idempotency.
  if p_client_op_id is not null then
    select id into v_existing_replay
    from public.txn
    where shop_id = p_shop_id and client_op_id = p_client_op_id;
    if v_existing_replay is not null then
      return v_existing_replay;
    end if;
  end if;

  -- Lock original.
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
    raise exception 'Sale not found (or it is itself a reversal)';
  end if;
  if v_original_type_code <> 'sale' then
    raise exception 'void_sale only voids sale transactions';
  end if;
  if v_original_posted_at is null then
    raise exception 'Sale has no posted_at — cannot void';
  end if;
  if v_original_posted_at < v_now - v_void_window then
    raise exception 'Sale is outside the % void window', v_void_window;
  end if;

  -- Refuse if already voided.
  select id into v_existing_reversal_id
  from public.txn
  where shop_id = p_shop_id and reverses_transaction_id = p_txn_id;
  if v_existing_reversal_id is not null then
    raise exception 'Sale was already voided';
  end if;

  -- Refuse partial-paid debt sale if customer has paid down. The party's
  -- current receivable must be >= the unpaid portion the original sale
  -- created, or undoing it would leave a credit we can't represent.
  v_unpaid := v_original_total - v_original_paid;
  if v_unpaid > 0 and v_original_party_id is not null then
    select receivable into v_party_receivable
    from public.party
    where shop_id = p_shop_id and id = v_original_party_id
    for update;
    if v_party_receivable < v_unpaid then
      raise exception
        'Customer has paid down some of this sale; void blocked. '
        'Record a refund payment instead.';
    end if;
  end if;

  v_sale_type_id := public._ref_id('transaction_type', 'sale');
  v_posted_status_id := public._ref_id('transaction_status', 'posted');

  -- Reversal header. Same positive amounts; reversal semantics come
  -- from reverses_transaction_id, which the read RPCs surface as
  -- is_voided on the original.
  insert into public.txn (
    shop_id, type_id, status_id, party_id, occurred_at, posted_at,
    total_amount, paid_amount, payment_method_id,
    reverses_transaction_id, client_op_id, notes, created_by
  )
  values (
    p_shop_id, v_sale_type_id, v_posted_status_id, v_original_party_id,
    v_now, v_now,
    v_original_total, v_original_paid, v_original_payment_method_id,
    p_txn_id, p_client_op_id,
    'Reversal of ' || p_txn_id::text,
    auth.uid()
  )
  returning id into v_reversal_txn_id;

  -- Copy lines + insert opposite-sign stock_movements + restore stock.
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

    -- Original sale's stock_movement was -base_quantity. The reversal
    -- is +base_quantity. Preserve the unit_cost the sale recorded so
    -- reports keep matching.
    select unit_cost into v_existing_movement_unit_cost
    from public.stock_movement
    where shop_id = p_shop_id and transaction_line_id = r.original_line_id
    limit 1;

    insert into public.stock_movement (
      shop_id, item_id, transaction_line_id, quantity_delta,
      unit_cost, occurred_at
    )
    values (
      p_shop_id, r.item_id, v_new_line_id, r.base_quantity,
      v_existing_movement_unit_cost, v_now
    );

    update public.item
    set current_stock = current_stock + r.base_quantity
    where shop_id = p_shop_id and id = r.item_id;
  end loop;

  -- Revert the receivable on debt sales.
  if v_unpaid > 0 and v_original_party_id is not null then
    update public.party
    set receivable = receivable - v_unpaid
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

revoke all on function public.void_sale(uuid, uuid, text) from public;
grant execute on function public.void_sale(uuid, uuid, text) to authenticated;
