-- Enrich get_today_summary into a full day-activity view for the Home
-- "Today" card: today's sales / received / money-in / money-out / expenses,
-- each as a total + a count, alongside the existing all-time balances +
-- low-stock count.
--
-- "Today" is the shop's own timezone (unchanged). Void handling matches the
-- rest of the app:
--   * txn (sale/receive/expense): skip reversal rows AND any row that has a
--     matching reverse-of row.
--   * payment (money in/out): skip reversal-marker rows (reverses_payment_id
--     set) AND any payment that has a matching reversal pointing at it.
-- Money IN additionally excludes SETTLEMENT LEGS (the hidden payment leg a
-- walk-in cash sale mints, `is_settlement_leg`), so a cash sale is counted
-- once (as a sale) and never double-counted as money in.
--
-- Mobile stays to "today, this shop" activity only — no profit/margin/P&L or
-- cash reconciliation (those live on web). Backward compatible: the four
-- pre-existing keys are unchanged; older clients ignore the new ones.

create or replace function public.get_today_summary(
  p_shop_id uuid,
  p_locale  text default 'en'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_today_start   timestamptz;
  v_sales_today   numeric;
  v_sales_count   int;
  v_recv_today    numeric;
  v_recv_count    int;
  v_exp_today     numeric;
  v_exp_count     int;
  v_in_today      numeric;
  v_in_count      int;
  v_out_today     numeric;
  v_out_count     int;
  v_receivables   numeric;
  v_payables      numeric;
  v_low_count     int;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to read this shop';
  end if;

  -- "Today" in the shop's configured timezone.
  select pg_catalog.date_trunc(
    'day',
    pg_catalog.timezone(s.timezone, pg_catalog.now())
  ) at time zone s.timezone
  into v_today_start
  from public.shop s
  where s.id = p_shop_id;

  -- Sales today (total + count), void-excluded.
  select coalesce(sum(t.total_amount), 0), count(*)::int
  into v_sales_today, v_sales_count
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  where t.shop_id = p_shop_id
    and tt.code = 'sale'
    and t.occurred_at >= v_today_start
    and t.reverses_transaction_id is null
    and not exists (
      select 1 from public.txn rev
      where rev.reverses_transaction_id = t.id
    );

  -- Received today (goods in), void-excluded.
  select coalesce(sum(t.total_amount), 0), count(*)::int
  into v_recv_today, v_recv_count
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  where t.shop_id = p_shop_id
    and tt.code = 'receive'
    and t.occurred_at >= v_today_start
    and t.reverses_transaction_id is null
    and not exists (
      select 1 from public.txn rev
      where rev.reverses_transaction_id = t.id
    );

  -- Expenses today, void-excluded.
  select coalesce(sum(t.total_amount), 0), count(*)::int
  into v_exp_today, v_exp_count
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  where t.shop_id = p_shop_id
    and tt.code = 'expense'
    and t.occurred_at >= v_today_start
    and t.reverses_transaction_id is null
    and not exists (
      select 1 from public.txn rev
      where rev.reverses_transaction_id = t.id
    );

  -- Money in today (customer payments): exclude reversal markers, voided
  -- originals, and settlement legs (cash-sale legs) so cash sales aren't
  -- double-counted.
  select coalesce(sum(pay.amount), 0), count(*)::int
  into v_in_today, v_in_count
  from public.payment pay
  where pay.shop_id = p_shop_id
    and pay.direction = 'I'
    and pay.occurred_at >= v_today_start
    and pay.reverses_payment_id is null
    and not pay.is_settlement_leg
    and not exists (
      select 1 from public.payment rev
      where rev.shop_id = p_shop_id and rev.reverses_payment_id = pay.id
    );

  -- Money out today (supplier payments): exclude reversal markers + voided
  -- originals. (Settlement legs are inbound only, so none here.)
  select coalesce(sum(pay.amount), 0), count(*)::int
  into v_out_today, v_out_count
  from public.payment pay
  where pay.shop_id = p_shop_id
    and pay.direction = 'O'
    and pay.occurred_at >= v_today_start
    and pay.reverses_payment_id is null
    and not exists (
      select 1 from public.payment rev
      where rev.shop_id = p_shop_id and rev.reverses_payment_id = pay.id
    );

  -- All-time balances + low stock (unchanged).
  select coalesce(sum(receivable), 0)
  into v_receivables
  from public.party
  where shop_id = p_shop_id and is_active and receivable > 0;

  select coalesce(sum(payable), 0)
  into v_payables
  from public.party
  where shop_id = p_shop_id and is_active and payable > 0;

  select count(*)::int
  into v_low_count
  from public.shop_item si
  where si.shop_id = p_shop_id
    and si.is_active
    and (
      si.current_stock < 1
      or (si.reorder_threshold is not null
          and si.current_stock <= si.reorder_threshold)
    );

  return jsonb_build_object(
    'sales_today', v_sales_today,
    'sales_count', v_sales_count,
    'received_today', v_recv_today,
    'received_count', v_recv_count,
    'expenses_today', v_exp_today,
    'expenses_count', v_exp_count,
    'money_in_today', v_in_today,
    'money_in_count', v_in_count,
    'money_out_today', v_out_today,
    'money_out_count', v_out_count,
    'receivables_total', v_receivables,
    'payables_total', v_payables,
    'low_stock_count', v_low_count
  );
end;
$$;

revoke all on function public.get_today_summary(uuid, text) from public;
grant execute on function public.get_today_summary(uuid, text) to authenticated;
