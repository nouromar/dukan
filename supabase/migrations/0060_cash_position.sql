-- 0060_cash_position.sql
--
-- A simple cash-on-hand approximation: sum of money that has flowed
-- THROUGH the cash drawer per the books. Not a true cash-on-hand
-- balance (no opening balance, no reconciliation events) — but a
-- useful net figure for "did cash come in or go out overall this
-- shop's life".
--
-- Cash inflows:
--   * Sale.paid_amount where payment_method='cash' (cashier collected cash)
--   * Payment.amount where direction='I' and method='cash'
-- Cash outflows:
--   * Expense.total_amount where payment_method='cash'
--   * Payment.amount where direction='O' and method='cash'
--
-- Voids: sale reversals are excluded via reverses_transaction_id IS NULL.
-- The reversal entry's negative paid_amount would otherwise double-count
-- the original. Same handling as elsewhere in reports.

create or replace view public.v_cash_position
with (security_invoker = true)
as
with cash_flows as (
  -- Sales paid in cash
  select t.shop_id,
         t.paid_amount  as cash_in,
         0::numeric     as cash_out
  from public.txn t
  join public.transaction_type tt
    on tt.id = t.type_id and tt.code = 'sale'
  join public.payment_method pm
    on pm.id = t.payment_method_id and pm.code = 'cash'
  where t.reverses_transaction_id is null

  union all

  -- Cash expenses
  select t.shop_id,
         0::numeric       as cash_in,
         t.total_amount   as cash_out
  from public.txn t
  join public.transaction_type tt
    on tt.id = t.type_id and tt.code = 'expense'
  join public.payment_method pm
    on pm.id = t.payment_method_id and pm.code = 'cash'
  where t.reverses_transaction_id is null

  union all

  -- Inbound cash payments (customer → us)
  select p.shop_id,
         p.amount       as cash_in,
         0::numeric     as cash_out
  from public.payment p
  join public.payment_method pm
    on pm.id = p.method_id and pm.code = 'cash'
  where p.direction = 'I'

  union all

  -- Outbound cash payments (us → supplier)
  select p.shop_id,
         0::numeric     as cash_in,
         p.amount       as cash_out
  from public.payment p
  join public.payment_method pm
    on pm.id = p.method_id and pm.code = 'cash'
  where p.direction = 'O'
)
select
  shop_id,
  coalesce(sum(cash_in),  0)::numeric(14, 2) as cash_in,
  coalesce(sum(cash_out), 0)::numeric(14, 2) as cash_out,
  coalesce(sum(cash_in) - sum(cash_out), 0)::numeric(14, 2)
    as cash_balance
from cash_flows
group by shop_id;

grant select on public.v_cash_position to authenticated;

comment on view public.v_cash_position is
  'Per-shop cash flow approximation: sum of cash inflows minus outflows since shop creation. No opening balance / reconciliation; security_invoker via underlying RLS.';
