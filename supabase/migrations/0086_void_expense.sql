-- 0086_void_expense.sql
--
-- Void a posted expense + a single-expense read for the detail screen.
--
-- An expense is a plain `txn` (transaction_type='expense', no party, no stock,
-- fully cash-paid — post_expense, 0010:947-1071). So void_expense is void_sale
-- (0085) MINUS the stock/COGS loop, the party-receivable reversal, and the
-- refund param: it just writes a reversing expense txn + mirrors the one line.
-- Owner-only; per-shop window (default 7) via _void_window_days (0085); audit
-- 'expense.void' (seeded in 0085); capability 'expense.void' (seeded in 0085).

create or replace function public.void_expense(
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
  v_original_total numeric;
  v_original_paid numeric;
  v_original_payment_method_id uuid;
  v_original_category_id uuid;
  v_reversal_txn_id uuid;
  v_expense_type_id uuid;
  v_posted_status_id uuid;
  v_now timestamptz := pg_catalog.now();
  v_void_window_days int;
  r record;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only the shop owner can void an expense';
  end if;

  v_void_window_days := public._void_window_days(
    p_shop_id, 'void_window_days_expense', 7);

  if p_client_op_id is not null then
    select id into v_existing_replay
    from public.txn
    where shop_id = p_shop_id and client_op_id = p_client_op_id;
    if v_existing_replay is not null then
      return v_existing_replay;
    end if;
  end if;

  select tt.code, t.posted_at, t.total_amount, t.paid_amount, t.payment_method_id
  into v_original_type_code, v_original_posted_at,
       v_original_total, v_original_paid, v_original_payment_method_id
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  where t.shop_id = p_shop_id
    and t.id = p_txn_id
    and t.reverses_transaction_id is null
  for update of t;

  if v_original_type_code is null then
    raise exception 'Expense not found (or it is itself a reversal)';
  end if;
  if v_original_type_code <> 'expense' then
    raise exception 'void_expense only voids expense transactions';
  end if;
  if v_original_posted_at is null then
    raise exception 'Expense has no posted_at — cannot void';
  end if;
  if v_original_posted_at < v_now - make_interval(days => v_void_window_days) then
    raise exception 'Expense is outside the %-day void window', v_void_window_days;
  end if;

  select id into v_existing_reversal_id
  from public.txn
  where shop_id = p_shop_id and reverses_transaction_id = p_txn_id;
  if v_existing_reversal_id is not null then
    raise exception 'Expense was already voided';
  end if;

  v_expense_type_id := public._ref_id('transaction_type', 'expense');
  v_posted_status_id := public._ref_id('transaction_status', 'posted');

  insert into public.txn (
    shop_id, type_id, status_id, occurred_at, posted_at,
    total_amount, paid_amount, payment_method_id,
    reverses_transaction_id, client_op_id, notes, created_by
  )
  values (
    p_shop_id, v_expense_type_id, v_posted_status_id, v_now, v_now,
    v_original_total, v_original_paid, v_original_payment_method_id,
    p_txn_id, p_client_op_id,
    'Reversal of expense ' || p_txn_id::text,
    auth.uid()
  )
  returning id into v_reversal_txn_id;

  -- Mirror the expense line(s) (no stock, no party). Capture the category
  -- for the audit before-image.
  for r in
    select tl.line_no, tl.expense_category_id, tl.unit_amount, tl.line_total
    from public.transaction_line tl
    where tl.shop_id = p_shop_id and tl.transaction_id = p_txn_id
    order by tl.line_no
  loop
    v_original_category_id := coalesce(v_original_category_id, r.expense_category_id);
    insert into public.transaction_line (
      shop_id, transaction_id, line_no, expense_category_id, unit_amount, line_total
    )
    values (
      p_shop_id, v_reversal_txn_id, r.line_no, r.expense_category_id,
      r.unit_amount, r.line_total
    );
  end loop;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'expense.void',
    p_entity_type  => 'txn',
    p_entity_id    => p_txn_id,
    p_before       => pg_catalog.jsonb_build_object(
      'total_amount', v_original_total,
      'category_id',  v_original_category_id
    ),
    p_after        => pg_catalog.jsonb_build_object(
      'reversal_txn_id', v_reversal_txn_id
    ),
    p_reason       => coalesce(
      nullif(pg_catalog.btrim(p_reason), ''),
      'Owner-initiated void within the expense correction window'
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

revoke all on function public.void_expense(uuid, uuid, text, text) from public;
grant execute on function public.void_expense(uuid, uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- get_expense — single expense for the detail screen (mirror get_sale +
-- list_expenses 0039). is_voided follows the reverses_transaction_id chain.
-- ---------------------------------------------------------------------------

create or replace function public.get_expense(
  p_shop_id uuid,
  p_txn_id  uuid,
  p_locale  text default 'en'
)
returns table (
  txn_id              uuid,
  occurred_at         timestamptz,
  posted_at           timestamptz,
  amount              numeric,
  payment_method_code text,
  category_id         uuid,
  category_name       text,
  notes               text,
  is_voided           boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_locale text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_locale, 'en')));
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to view expenses for this shop';
  end if;
  if v_locale = '' then
    v_locale := 'en';
  end if;

  return query
  select
    t.id as txn_id,
    t.occurred_at,
    t.posted_at,
    t.total_amount as amount,
    pm.code as payment_method_code,
    tl.expense_category_id as category_id,
    public.tr(ec.name, ec.name_translations, v_locale) as category_name,
    t.notes,
    exists (
      select 1 from public.txn rev
      where rev.shop_id = p_shop_id and rev.reverses_transaction_id = t.id
    ) as is_voided
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  left join public.transaction_line tl
    on tl.shop_id = t.shop_id and tl.transaction_id = t.id
  left join public.expense_category ec on ec.id = tl.expense_category_id
  left join public.payment_method pm on pm.id = t.payment_method_id
  where t.shop_id = p_shop_id
    and t.id = p_txn_id
    and tt.code = 'expense'
    and t.reverses_transaction_id is null;
end;
$$;

revoke all on function public.get_expense(uuid, uuid, text) from public;
grant execute on function public.get_expense(uuid, uuid, text) to authenticated;
