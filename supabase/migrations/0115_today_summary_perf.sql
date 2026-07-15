-- 0115_today_summary_perf.sql
--
-- Speed up get_today_summary (0113) so it stays flat as a shop accumulates
-- history and scales to billions of rows platform-wide. Two levers:
--
--   1. Index txn.reverses_transaction_id. The void-exclusion probe
--      `not exists (select 1 from txn rev where rev.reverses_transaction_id = t.id)`
--      was a FULL txn seq-scan per today-row — O(today_rows x total_txns), the
--      one thing that explodes with history. An index makes it an O(log N)
--      probe. (payment already had payment_reverses_payment_idx; only txn was
--      missed.) Also index payment(shop_id, occurred_at) for the today money
--      scan — the existing payment index leads with party_id and can't serve a
--      (shop_id, direction, occurred_at) filter.
--
--   2. Collapse the 8 aggregation scans to 4 via conditional aggregation
--      (FILTER): one pass over today's txns (sale/receive/expense), one over
--      today's payments (in/out), one over parties (receivable/payable). Same
--      output JSON, same void + settlement-leg semantics, ~half the passes and
--      half the reversal-subquery work.
--
-- Output is byte-for-byte the same as 0113; §TS in the harness asserts it.
--
-- NOTE (production): on a large existing txn/payment table, apply the two
-- indexes with `create index concurrently` OUTSIDE a transaction to avoid a
-- write lock. In this transactional migration (fresh / pre-pilot) plain
-- `create index if not exists` is correct.
--
-- Scale ceiling / next step: the read stays cheap because "today" is a range
-- index scan and balances are denormalized projections (party.receivable,
-- shop_item.current_stock) — never a live sum over history. At true billions
-- the documented next move is time-partitioning txn/payment by occurred_at
-- (partition pruning keeps "today" tiny + lets old partitions be archived).

create index if not exists txn_reverses_transaction_id_idx
  on public.txn (reverses_transaction_id)
  where reverses_transaction_id is not null;

create index if not exists payment_shop_occurred_at_idx
  on public.payment (shop_id, occurred_at desc);

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

  -- One pass over today's transactions: sales / received / expenses, each
  -- void-excluded (reversal markers filtered, and originals that HAVE a
  -- reversal excluded via the now-indexed reverses_transaction_id probe).
  select
    coalesce(pg_catalog.sum(t.total_amount) filter (where tt.code = 'sale'), 0),
    (pg_catalog.count(*) filter (where tt.code = 'sale'))::int,
    coalesce(pg_catalog.sum(t.total_amount) filter (where tt.code = 'receive'), 0),
    (pg_catalog.count(*) filter (where tt.code = 'receive'))::int,
    coalesce(pg_catalog.sum(t.total_amount) filter (where tt.code = 'expense'), 0),
    (pg_catalog.count(*) filter (where tt.code = 'expense'))::int
  into v_sales_today, v_sales_count, v_recv_today, v_recv_count, v_exp_today, v_exp_count
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  where t.shop_id = p_shop_id
    and tt.code in ('sale', 'receive', 'expense')
    and t.occurred_at >= v_today_start
    and t.reverses_transaction_id is null
    and not exists (
      select 1 from public.txn rev
      where rev.reverses_transaction_id = t.id
    );

  -- One pass over today's payments: money in (customer payments, excluding
  -- settlement legs so cash sales aren't double-counted) / money out (supplier
  -- payments). Reversal markers + voided originals excluded.
  select
    coalesce(pg_catalog.sum(pay.amount)
             filter (where pay.direction = 'I' and not pay.is_settlement_leg), 0),
    (pg_catalog.count(*)
             filter (where pay.direction = 'I' and not pay.is_settlement_leg))::int,
    coalesce(pg_catalog.sum(pay.amount) filter (where pay.direction = 'O'), 0),
    (pg_catalog.count(*) filter (where pay.direction = 'O'))::int
  into v_in_today, v_in_count, v_out_today, v_out_count
  from public.payment pay
  where pay.shop_id = p_shop_id
    and pay.occurred_at >= v_today_start
    and pay.reverses_payment_id is null
    and not exists (
      select 1 from public.payment rev
      where rev.shop_id = p_shop_id and rev.reverses_payment_id = pay.id
    );

  -- One pass over this shop's parties: outstanding receivables + payables.
  -- Denormalized projections — bounded by party count, not transaction history.
  select
    coalesce(pg_catalog.sum(receivable) filter (where receivable > 0), 0),
    coalesce(pg_catalog.sum(payable)    filter (where payable > 0), 0)
  into v_receivables, v_payables
  from public.party
  where shop_id = p_shop_id and is_active;

  select pg_catalog.count(*)::int
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
