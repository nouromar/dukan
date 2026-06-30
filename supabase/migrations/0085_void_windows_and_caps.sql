-- 0085_void_windows_and_caps.sql
--
-- Foundations for "void all transaction types" + a configurable, per-type void
-- window.
--
--   * Per-shop void windows live in shop_setting under the keys
--       void_window_days_{sale,receive,payment,expense}
--     read server-side inside each void RPC (the security boundary), falling
--     back to defaults (sale 7, receive 1, payment 7, expense 7).
--   * shop.void_settings jsonb is a projection of those keys, so the mobile app
--     can pre-gate the VOID button without an extra round-trip (mirrors the
--     scanner_settings projection in 0049).
--   * void_sale / void_receive are re-created here to read their window from the
--     helper instead of a hardcoded interval. Every other guard is unchanged.
--   * New capabilities + audit action codes for payment.void / expense.void
--     (the RPCs land in 0086/0087).

-- ---------------------------------------------------------------------------
-- 1. Window resolver — caller's per-type key, else the default.
-- ---------------------------------------------------------------------------

create or replace function public._void_window_days(
  p_shop_id uuid,
  p_key     text,
  p_default int
)
returns int
language sql
security definer
set search_path = ''
stable
as $$
  select coalesce(
    (select (value #>> '{}')::int
       from public.shop_setting
      where shop_id = p_shop_id and key = p_key),
    p_default);
$$;

-- ---------------------------------------------------------------------------
-- 2. shop.void_settings projection (app reads it off the shop row).
--    Stored stripped: {sale, receive, payment, expense}.
-- ---------------------------------------------------------------------------

alter table public.shop
  add column if not exists void_settings jsonb not null default jsonb_build_object(
    'sale', 7,
    'receive', 1,
    'payment', 7,
    'expense', 7
  );

create or replace function public._project_void_settings(p_shop_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb := jsonb_build_object(
    'sale', 7,
    'receive', 1,
    'payment', 7,
    'expense', 7
  );
  v_row record;
  v_field text;
begin
  for v_row in
    select key, value
    from public.shop_setting
    where shop_id = p_shop_id and key like 'void\_window\_days\_%' escape '\'
  loop
    v_field := substring(v_row.key from 'void_window_days_(.+)$');
    if v_field is not null then
      v_result := v_result || jsonb_build_object(v_field, v_row.value);
    end if;
  end loop;
  update public.shop set void_settings = v_result where id = p_shop_id;
end;
$$;

create or replace function public._trg_project_void_settings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or tg_op = 'UPDATE' then
    if new.key like 'void\_window\_days\_%' escape '\' then
      perform public._project_void_settings(new.shop_id);
    end if;
  end if;
  if tg_op = 'DELETE' or tg_op = 'UPDATE' then
    if old.key like 'void\_window\_days\_%' escape '\' then
      perform public._project_void_settings(old.shop_id);
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_project_void_settings on public.shop_setting;
create trigger trg_project_void_settings
after insert or update or delete on public.shop_setting
for each row execute function public._trg_project_void_settings();

-- ---------------------------------------------------------------------------
-- 3. void_sale — window now read per-shop (default 7). Body otherwise verbatim
--    from 0010.
-- ---------------------------------------------------------------------------

create or replace function public.void_sale(
  p_shop_id uuid,
  p_txn_id uuid,
  p_client_op_id text default null,
  p_refund_amount numeric default null,
  p_reason text default null
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
  v_void_window_days int;
  r record;
  v_new_line_id uuid;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only the shop owner can void a sale';
  end if;

  v_void_window_days := public._void_window_days(
    p_shop_id, 'void_window_days_sale', 7);

  if p_client_op_id is not null then
    select id into v_existing_replay
    from public.txn
    where shop_id = p_shop_id and client_op_id = p_client_op_id;
    if v_existing_replay is not null then
      return v_existing_replay;
    end if;
  end if;

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
  if v_original_posted_at < v_now - make_interval(days => v_void_window_days) then
    raise exception 'Sale is outside the %-day void window', v_void_window_days;
  end if;

  select id into v_existing_reversal_id
  from public.txn
  where shop_id = p_shop_id and reverses_transaction_id = p_txn_id;
  if v_existing_reversal_id is not null then
    raise exception 'Sale was already voided';
  end if;

  -- Validate refund before any state change.
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
    select pt.code into v_original_party_type
    from public.party p
    join public.party_type pt on pt.id = p.type_id
    where p.shop_id = p_shop_id and p.id = v_original_party_id;
    if v_original_party_type not in ('customer', 'both') then
      raise exception 'Refund target party is not a customer';
    end if;
  end if;

  -- Partial-paid receivable guard.
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

  -- Mirror each line. cogs snapshot carries over from the original so
  -- profit reports unwind the same value they originally booked.
  for r in
    select tl.id as original_line_id, tl.line_no, tl.item_id, tl.shop_item_unit_id,
           tl.quantity, tl.unit_id, tl.base_quantity, tl.unit_amount,
           tl.item_name_snapshot, tl.unit_code_snapshot,
           tl.unit_conversion_to_base_snapshot, tl.line_total,
           tl.cogs_unit_cost, tl.cogs_total
    from public.transaction_line tl
    where tl.shop_id = p_shop_id and tl.transaction_id = p_txn_id
    order by tl.line_no
  loop
    insert into public.transaction_line (
      shop_id, transaction_id, line_no, item_id, shop_item_unit_id,
      quantity, unit_id, base_quantity, unit_amount,
      item_name_snapshot, unit_code_snapshot,
      unit_conversion_to_base_snapshot, line_total,
      cogs_unit_cost, cogs_total
    )
    values (
      p_shop_id, v_reversal_txn_id, r.line_no, r.item_id, r.shop_item_unit_id,
      r.quantity, r.unit_id, r.base_quantity, r.unit_amount,
      r.item_name_snapshot, r.unit_code_snapshot,
      r.unit_conversion_to_base_snapshot, r.line_total,
      r.cogs_unit_cost, r.cogs_total
    )
    returning id into v_new_line_id;

    -- Original sale movement was -base_quantity at cogs_unit_cost; the
    -- reversal puts the stock back in at the same cost basis.
    insert into public.stock_movement (
      shop_id, item_id, transaction_line_id, quantity_delta,
      unit_cost, occurred_at
    )
    values (
      p_shop_id, r.item_id, v_new_line_id, r.base_quantity,
      r.cogs_unit_cost, v_now
    );

    update public.shop_item
    set current_stock = current_stock + r.base_quantity
    where shop_id = p_shop_id and id = r.item_id;
  end loop;

  if v_unpaid > 0 and v_original_party_id is not null then
    update public.party
    set receivable = receivable - v_unpaid
    where shop_id = p_shop_id and id = v_original_party_id;
  end if;

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

  -- Audit log requires a reason ≥10 chars. Mobile v1 doesn't prompt
  -- for one yet (UX deferred to the shop admin portal); fall back to
  -- a stable default that names the actor + window.
  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'sale.void',
    p_entity_type  => 'txn',
    p_entity_id    => p_txn_id,
    p_before       => pg_catalog.jsonb_build_object(
      'total_amount', v_original_total,
      'paid_amount',  v_original_paid,
      'party_id',     v_original_party_id
    ),
    p_after        => pg_catalog.jsonb_build_object(
      'reversal_txn_id', v_reversal_txn_id,
      'refund_amount',   p_refund_amount
    ),
    p_reason       => coalesce(
      nullif(pg_catalog.btrim(p_reason), ''),
      'Owner-initiated void within the sale correction window'
    ),
    p_client_op_id => p_client_op_id
  );

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

-- ---------------------------------------------------------------------------
-- 4. void_receive — window now read per-shop (default 1). Body otherwise
--    verbatim from 0010, including the no-later-stock-activity guard.
-- ---------------------------------------------------------------------------

create or replace function public.void_receive(
  p_shop_id uuid,
  p_txn_id uuid,
  p_client_op_id text default null,
  p_reason text default null
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
  v_void_window_days int;
  r record;
  v_new_line_id uuid;
  v_existing_movement_unit_cost numeric;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only the shop owner can void a receive';
  end if;

  v_void_window_days := public._void_window_days(
    p_shop_id, 'void_window_days_receive', 1);

  if p_client_op_id is not null then
    select id into v_existing_replay
    from public.txn
    where shop_id = p_shop_id and client_op_id = p_client_op_id;
    if v_existing_replay is not null then
      return v_existing_replay;
    end if;
  end if;

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
  if v_original_posted_at < v_now - make_interval(days => v_void_window_days) then
    raise exception
      'Receive is outside the %-day void window. Use a return instead.',
      v_void_window_days;
  end if;

  select id into v_existing_reversal_id
  from public.txn
  where shop_id = p_shop_id and reverses_transaction_id = p_txn_id;
  if v_existing_reversal_id is not null then
    raise exception 'Receive was already voided';
  end if;

  -- Block if any of the received items has had stock activity since
  -- this receive posted (sales, adjustments, other receives). The
  -- receive's own movements are excluded via the line-id filter; >=
  -- because rapid back-to-back ops can share a timestamp.
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

  for r in
    select tl.id as original_line_id, tl.line_no, tl.item_id, tl.shop_item_unit_id,
           tl.quantity, tl.unit_id, tl.base_quantity, tl.unit_amount,
           tl.item_name_snapshot, tl.unit_code_snapshot,
           tl.unit_conversion_to_base_snapshot, tl.line_total
    from public.transaction_line tl
    where tl.shop_id = p_shop_id and tl.transaction_id = p_txn_id
    order by tl.line_no
  loop
    insert into public.transaction_line (
      shop_id, transaction_id, line_no, item_id, shop_item_unit_id,
      quantity, unit_id, base_quantity, unit_amount,
      item_name_snapshot, unit_code_snapshot,
      unit_conversion_to_base_snapshot, line_total
    )
    values (
      p_shop_id, v_reversal_txn_id, r.line_no, r.item_id, r.shop_item_unit_id,
      r.quantity, r.unit_id, r.base_quantity, r.unit_amount,
      r.item_name_snapshot, r.unit_code_snapshot,
      r.unit_conversion_to_base_snapshot, r.line_total
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
      p_shop_id, r.item_id, v_new_line_id, -r.base_quantity,
      v_existing_movement_unit_cost, v_now
    );

    update public.shop_item
    set current_stock = current_stock - r.base_quantity
    where shop_id = p_shop_id and id = r.item_id;
  end loop;

  if v_unpaid > 0 and v_original_party_id is not null then
    update public.party
    set payable = payable - v_unpaid
    where shop_id = p_shop_id and id = v_original_party_id;
  end if;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'receive.void',
    p_entity_type  => 'txn',
    p_entity_id    => p_txn_id,
    p_before       => pg_catalog.jsonb_build_object(
      'total_amount', v_original_total,
      'paid_amount',  v_original_paid,
      'party_id',     v_original_party_id
    ),
    p_after        => pg_catalog.jsonb_build_object(
      'reversal_txn_id', v_reversal_txn_id
    ),
    p_reason       => coalesce(
      nullif(pg_catalog.btrim(p_reason), ''),
      'Owner-initiated void within the receive correction window'
    ),
    p_client_op_id => p_client_op_id
  );

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

-- ---------------------------------------------------------------------------
-- 5. Capabilities for the two new voids (RPCs land in 0086/0087).
-- ---------------------------------------------------------------------------

insert into public.capability (code, label, description) values
  ('payment.void', 'Void payments', 'Owner-only — reverse a posted payment.'),
  ('expense.void', 'Void expenses', 'Owner-only — reverse a posted expense.')
on conflict (code) do update set
  label = excluded.label,
  description = excluded.description,
  is_active = excluded.is_active;

insert into public.shop_role_capability (role_id, capability_code)
  select id, 'payment.void' from public.shop_role where code = 'owner'
  union all
  select id, 'expense.void' from public.shop_role where code = 'owner'
on conflict do nothing;

insert into public.organization_role_capability (role_id, capability_code)
  select id, cap.code
  from public.organization_role,
       (values ('payment.void'), ('expense.void')) as cap(code)
  where public.organization_role.code in ('org_owner', 'org_admin')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 6. Audit action codes for the two new voids.
-- ---------------------------------------------------------------------------

insert into public.audit_action_code
  (code, area, description, captures_before, captures_after, requires_reason)
values
  ('payment.void', 'payment', 'Payment voided (reverses_payment_id marker)', true, true, true),
  ('expense.void', 'expense', 'Expense voided (reverses_transaction_id chain)', true, true, true)
on conflict (code) do nothing;
