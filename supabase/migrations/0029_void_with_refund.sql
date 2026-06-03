-- Customer-refund on void.
--
-- Voiding a sale that involved cash paid at the till leaves the cash
-- in the drawer. Without a refund record the books don't tie out.
-- This migration adds an optional refund step to the void RPC.
--
-- p_refund_amount semantics:
--   null  → no refund (current behavior preserved)
--   > 0   → record an outbound payment to the customer (direction='O')
--           up to the original paid_amount. The refund payment is
--           linked back to the voided sale via payment.refund_of_transaction_id
--           so reports can trace it.

alter table public.payment
  add column if not exists refund_of_transaction_id uuid;

-- FK matches the existing composite-FK style used elsewhere so
-- cross-shop refunds are blocked at the constraint layer.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'payment_refund_of_transaction_fk'
  ) then
    alter table public.payment
    add constraint payment_refund_of_transaction_fk
    foreign key (shop_id, refund_of_transaction_id)
    references public.txn(shop_id, id) on delete restrict;
  end if;
end;
$$;

create index if not exists payment_refund_of_transaction_idx
  on public.payment (shop_id, refund_of_transaction_id)
  where refund_of_transaction_id is not null;

-- ---- void_sale ------------------------------------------------------------
--
-- Adds the refund parameter. Everything else preserves the 0028
-- behavior (owner-only, 7-day window, idempotency, partial-paid guard,
-- stock + receivable restore).

create or replace function public.void_sale(
  p_shop_id uuid,
  p_txn_id uuid,
  p_client_op_id text default null,
  p_refund_amount numeric default null
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
  v_original_party_type text;
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

  select id into v_existing_reversal_id
  from public.txn
  where shop_id = p_shop_id and reverses_transaction_id = p_txn_id;
  if v_existing_reversal_id is not null then
    raise exception 'Sale was already voided';
  end if;

  -- Refund validation (must happen before any state change).
  if p_refund_amount is not null then
    if p_refund_amount <= 0 then
      raise exception 'Refund amount must be greater than zero';
    end if;
    if v_original_party_id is null then
      raise exception 'Refund requires a customer party on the sale';
    end if;
    if p_refund_amount > v_original_paid then
      raise exception
        'Refund (%) cannot exceed cash paid at the till (%)',
        p_refund_amount, v_original_paid;
    end if;

    -- The customer party must accept inbound (i.e., is a customer or
    -- 'both' type); outbound to a supplier-only party makes no sense.
    select pt.code into v_original_party_type
    from public.party p
    join public.party_type pt on pt.id = p.type_id
    where p.shop_id = p_shop_id and p.id = v_original_party_id;
    if v_original_party_type not in ('customer', 'both') then
      raise exception 'Refund target party is not a customer';
    end if;
  end if;

  -- Partial-paid receivable guard (unchanged from 0028).
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

  -- Reversal header.
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

  -- Lines + stock_movements.
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

  -- Receivable revert.
  if v_unpaid > 0 and v_original_party_id is not null then
    update public.party
    set receivable = receivable - v_unpaid
    where shop_id = p_shop_id and id = v_original_party_id;
  end if;

  -- Refund payment (optional).
  if p_refund_amount is not null then
    insert into public.payment (
      shop_id, party_id, direction, amount, method_id,
      occurred_at, refund_of_transaction_id, notes, created_by
    )
    values (
      p_shop_id, v_original_party_id, 'O', p_refund_amount,
      v_original_payment_method_id, v_now, p_txn_id,
      'Refund of voided sale ' || p_txn_id::text,
      auth.uid()
    );
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

-- Replace the 3-arg signature's grants so the new 4-arg overload is
-- the only callable form. The function is `create or replace` above
-- but Postgres considers (uuid, uuid, text) and (uuid, uuid, text,
-- numeric) as different functions until we drop the old one.
drop function if exists public.void_sale(uuid, uuid, text);

revoke all on function public.void_sale(uuid, uuid, text, numeric) from public;
grant execute on function public.void_sale(uuid, uuid, text, numeric) to authenticated;
