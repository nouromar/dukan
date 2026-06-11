-- Reports + reconciliation views.
--
-- v2 schema notes:
--   - `item` (per-shop) was renamed to `shop_item`. Display name no
--     longer lives on the row — it's resolved via the alias chain
--     (shop_item_alias > item_alias), so views call
--     `shop_item_display_name(shop_item_id, locale)`.
--   - `shop_item` lost name / sale_price / last_cost / default_*_unit_id /
--     barcode columns. Pricing is per-packaging on `shop_item_unit`;
--     barcodes live in `item_barcode` / `shop_item_barcode`.
--   - `transaction_line.catalog_revision_id` was dropped with revisions.
--
-- All views use `security_invoker = true` so RLS on the underlying
-- tables continues to gate visibility.

-- ---------------------------------------------------------------------------
-- shop_item_display_name(shop_item_id, locale)
-- ---------------------------------------------------------------------------
--
-- Walks the alias chain to resolve the display name:
--   1. shop_item_alias  is_display, locale match
--   2. shop_item_alias  is_display, any language
--   3. item_alias       is_display, locale match (via shop_item.item_id)
--   4. item_alias       is_display, any language
--   5. fallback: shop_item.id::text (rare; means no aliases yet)
--
-- Marked immutable + parallel safe so it composes inside views.

create or replace function public.shop_item_display_name(
  p_shop_item_id uuid,
  p_locale text default 'en'
)
returns text
language sql
stable
parallel safe
set search_path = ''
as $$
  select coalesce(
    (
      select sia.alias_text
      from public.shop_item_alias sia
      where sia.shop_item_id = p_shop_item_id
        and sia.is_display
        and sia.is_active
        and sia.language_code = p_locale
      limit 1
    ),
    (
      select sia.alias_text
      from public.shop_item_alias sia
      where sia.shop_item_id = p_shop_item_id
        and sia.is_display
        and sia.is_active
      order by sia.language_code nulls last
      limit 1
    ),
    (
      select ia.alias_text
      from public.shop_item si
      join public.item_alias ia on ia.item_id = si.item_id
      where si.id = p_shop_item_id
        and ia.is_display
        and ia.is_active
        and ia.language_code = p_locale
      limit 1
    ),
    (
      select ia.alias_text
      from public.shop_item si
      join public.item_alias ia on ia.item_id = si.item_id
      where si.id = p_shop_item_id
        and ia.is_display
        and ia.is_active
      order by ia.language_code nulls last
      limit 1
    ),
    p_shop_item_id::text
  );
$$;

grant execute on function public.shop_item_display_name(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- v_item_stock_truth
-- ---------------------------------------------------------------------------
--
-- Reconciliation: cached shop_item.current_stock vs sum of
-- stock_movement.quantity_delta. Variance should always be 0.

create view public.v_item_stock_truth
with (security_invoker = true)
as
select
  si.shop_id,
  si.id as item_id,
  public.shop_item_display_name(si.id, 'en') as item_name,
  si.current_stock as cached_stock,
  coalesce(sum(sm.quantity_delta), 0)::numeric(14, 3) as ledger_stock,
  (si.current_stock - coalesce(sum(sm.quantity_delta), 0))::numeric(14, 3) as stock_variance,
  count(sm.id) as movement_count
from public.shop_item si
left join public.stock_movement sm
  on sm.shop_id = si.shop_id
  and sm.item_id = si.id
group by si.shop_id, si.id, si.current_stock;

-- ---------------------------------------------------------------------------
-- v_party_balance_truth
-- ---------------------------------------------------------------------------

create view public.v_party_balance_truth
with (security_invoker = true)
as
with transaction_balance as (
  select
    t.shop_id,
    t.party_id,
    sum(case when tt.code = 'sale' then t.total_amount - t.paid_amount else 0 end) as receivable_from_transactions,
    sum(case when tt.code = 'receive' then t.total_amount - t.paid_amount else 0 end) as payable_from_transactions
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  join public.transaction_status ts on ts.id = t.status_id
  where t.party_id is not null
    and ts.code = 'posted'
    and tt.code in ('sale', 'receive')
  group by t.shop_id, t.party_id
),
standalone_payments as (
  select
    p.shop_id,
    p.party_id,
    sum(case when p.direction = 'I' then p.amount else 0 end) as inbound_payments,
    sum(case when p.direction = 'O' then p.amount else 0 end) as outbound_payments
  from public.payment p
  where p.party_id is not null
    and not exists (
      select 1
      from public.payment_allocation pa
      where pa.shop_id = p.shop_id
        and pa.payment_id = p.id
    )
  group by p.shop_id, p.party_id
)
select
  p.shop_id,
  p.id as party_id,
  p.name as party_name,
  pt.code as party_type_code,
  p.receivable as cached_receivable,
  (
    coalesce(tb.receivable_from_transactions, 0)
    - coalesce(sp.inbound_payments, 0)
  )::numeric(14, 2) as ledger_receivable,
  (
    p.receivable
    - (
      coalesce(tb.receivable_from_transactions, 0)
      - coalesce(sp.inbound_payments, 0)
    )
  )::numeric(14, 2) as receivable_variance,
  p.payable as cached_payable,
  (
    coalesce(tb.payable_from_transactions, 0)
    - coalesce(sp.outbound_payments, 0)
  )::numeric(14, 2) as ledger_payable,
  (
    p.payable
    - (
      coalesce(tb.payable_from_transactions, 0)
      - coalesce(sp.outbound_payments, 0)
    )
  )::numeric(14, 2) as payable_variance
from public.party p
join public.party_type pt on pt.id = p.type_id
left join transaction_balance tb
  on tb.shop_id = p.shop_id
  and tb.party_id = p.id
left join standalone_payments sp
  on sp.shop_id = p.shop_id
  and sp.party_id = p.id;

-- ---------------------------------------------------------------------------
-- v_sales_report
-- ---------------------------------------------------------------------------

create view public.v_sales_report
with (security_invoker = true)
as
select
  t.shop_id,
  t.id as transaction_id,
  t.occurred_at,
  (t.occurred_at at time zone s.timezone)::date as local_date,
  date_trunc('month', t.occurred_at at time zone s.timezone)::date as local_month,
  t.party_id as customer_id,
  p.name as customer_name,
  t.total_amount as revenue,
  t.paid_amount,
  (t.total_amount - t.paid_amount)::numeric(14, 2) as unpaid_amount,
  coalesce(sum(tl.cogs_total), 0)::numeric(14, 2) as cogs_total,
  (t.total_amount - coalesce(sum(tl.cogs_total), 0))::numeric(14, 2) as gross_profit,
  count(tl.id) as line_count,
  t.payment_method_id,
  pm.code as payment_method_code,
  t.document_id,
  t.client_op_id,
  t.notes,
  t.created_by,
  t.created_at
from public.txn t
join public.shop s on s.id = t.shop_id
join public.transaction_type tt on tt.id = t.type_id
join public.transaction_status ts on ts.id = t.status_id
left join public.party p
  on p.shop_id = t.shop_id
  and p.id = t.party_id
left join public.payment_method pm on pm.id = t.payment_method_id
left join public.transaction_line tl
  on tl.shop_id = t.shop_id
  and tl.transaction_id = t.id
where tt.code = 'sale'
  and ts.code = 'posted'
group by
  t.shop_id,
  t.id,
  t.occurred_at,
  s.timezone,
  t.party_id,
  p.name,
  t.total_amount,
  t.paid_amount,
  t.payment_method_id,
  pm.code,
  t.document_id,
  t.client_op_id,
  t.notes,
  t.created_by,
  t.created_at;

-- ---------------------------------------------------------------------------
-- v_receive_report
-- ---------------------------------------------------------------------------

create view public.v_receive_report
with (security_invoker = true)
as
select
  t.shop_id,
  t.id as transaction_id,
  t.occurred_at,
  (t.occurred_at at time zone s.timezone)::date as local_date,
  date_trunc('month', t.occurred_at at time zone s.timezone)::date as local_month,
  t.party_id as supplier_id,
  p.name as supplier_name,
  t.total_amount,
  t.paid_amount,
  (t.total_amount - t.paid_amount)::numeric(14, 2) as unpaid_amount,
  count(tl.id) as line_count,
  t.payment_method_id,
  pm.code as payment_method_code,
  t.document_id,
  t.client_op_id,
  t.notes,
  t.created_by,
  t.created_at
from public.txn t
join public.shop s on s.id = t.shop_id
join public.transaction_type tt on tt.id = t.type_id
join public.transaction_status ts on ts.id = t.status_id
left join public.party p
  on p.shop_id = t.shop_id
  and p.id = t.party_id
left join public.payment_method pm on pm.id = t.payment_method_id
left join public.transaction_line tl
  on tl.shop_id = t.shop_id
  and tl.transaction_id = t.id
where tt.code = 'receive'
  and ts.code = 'posted'
group by
  t.shop_id,
  t.id,
  t.occurred_at,
  s.timezone,
  t.party_id,
  p.name,
  t.total_amount,
  t.paid_amount,
  t.payment_method_id,
  pm.code,
  t.document_id,
  t.client_op_id,
  t.notes,
  t.created_by,
  t.created_at;

-- ---------------------------------------------------------------------------
-- v_expense_report
-- ---------------------------------------------------------------------------

create view public.v_expense_report
with (security_invoker = true)
as
select
  t.shop_id,
  t.id as transaction_id,
  tl.id as transaction_line_id,
  t.occurred_at,
  (t.occurred_at at time zone s.timezone)::date as local_date,
  date_trunc('month', t.occurred_at at time zone s.timezone)::date as local_month,
  tl.expense_category_id,
  ec.code as expense_category_code,
  ec.name as expense_category_name,
  tl.line_total as amount,
  t.payment_method_id,
  pm.code as payment_method_code,
  t.document_id,
  t.client_op_id,
  t.notes,
  t.created_by,
  t.created_at
from public.txn t
join public.shop s on s.id = t.shop_id
join public.transaction_type tt on tt.id = t.type_id
join public.transaction_status ts on ts.id = t.status_id
join public.transaction_line tl
  on tl.shop_id = t.shop_id
  and tl.transaction_id = t.id
join public.expense_category ec
  on ec.shop_id = tl.shop_id
  and ec.id = tl.expense_category_id
left join public.payment_method pm on pm.id = t.payment_method_id
where tt.code = 'expense'
  and ts.code = 'posted';

-- ---------------------------------------------------------------------------
-- v_payment_report
-- ---------------------------------------------------------------------------

create view public.v_payment_report
with (security_invoker = true)
as
select
  p.shop_id,
  p.id as payment_id,
  p.party_id,
  party.name as party_name,
  p.direction,
  p.amount,
  p.method_id,
  pm.code as payment_method_code,
  p.occurred_at,
  (p.occurred_at at time zone s.timezone)::date as local_date,
  date_trunc('month', p.occurred_at at time zone s.timezone)::date as local_month,
  p.document_id,
  p.client_op_id,
  p.notes,
  p.created_by,
  p.created_at
from public.payment p
join public.shop s on s.id = p.shop_id
join public.payment_method pm on pm.id = p.method_id
left join public.party party
  on party.shop_id = p.shop_id
  and party.id = p.party_id;

-- ---------------------------------------------------------------------------
-- v_daily_profit / v_monthly_profit / v_monthly_sales / v_monthly_expenses
-- ---------------------------------------------------------------------------

create view public.v_daily_profit
with (security_invoker = true)
as
with sales as (
  select
    shop_id,
    local_date,
    sum(revenue) as revenue,
    sum(cogs_total) as cogs_total,
    sum(gross_profit) as gross_profit,
    count(*) as sale_count
  from public.v_sales_report
  group by shop_id, local_date
),
expenses as (
  select
    shop_id,
    local_date,
    sum(amount) as expense_total,
    count(*) as expense_count
  from public.v_expense_report
  group by shop_id, local_date
)
select
  coalesce(s.shop_id, e.shop_id) as shop_id,
  coalesce(s.local_date, e.local_date) as local_date,
  coalesce(s.revenue, 0)::numeric(14, 2) as revenue,
  coalesce(s.cogs_total, 0)::numeric(14, 2) as cogs_total,
  coalesce(s.gross_profit, 0)::numeric(14, 2) as gross_profit,
  coalesce(e.expense_total, 0)::numeric(14, 2) as expense_total,
  (coalesce(s.gross_profit, 0) - coalesce(e.expense_total, 0))::numeric(14, 2) as net_profit,
  coalesce(s.sale_count, 0) as sale_count,
  coalesce(e.expense_count, 0) as expense_count
from sales s
full join expenses e
  on e.shop_id = s.shop_id
  and e.local_date = s.local_date;

create view public.v_monthly_profit
with (security_invoker = true)
as
select
  shop_id,
  date_trunc('month', local_date::timestamp)::date as local_month,
  sum(revenue)::numeric(14, 2) as revenue,
  sum(cogs_total)::numeric(14, 2) as cogs_total,
  sum(gross_profit)::numeric(14, 2) as gross_profit,
  sum(expense_total)::numeric(14, 2) as expense_total,
  sum(net_profit)::numeric(14, 2) as net_profit,
  sum(sale_count) as sale_count,
  sum(expense_count) as expense_count
from public.v_daily_profit
group by shop_id, date_trunc('month', local_date::timestamp)::date;

create view public.v_monthly_sales
with (security_invoker = true)
as
select
  shop_id,
  local_month,
  count(*) as sale_count,
  sum(revenue)::numeric(14, 2) as revenue,
  sum(paid_amount)::numeric(14, 2) as paid_amount,
  sum(unpaid_amount)::numeric(14, 2) as unpaid_amount,
  sum(cogs_total)::numeric(14, 2) as cogs_total,
  sum(gross_profit)::numeric(14, 2) as gross_profit
from public.v_sales_report
group by shop_id, local_month;

create view public.v_monthly_expenses
with (security_invoker = true)
as
select
  shop_id,
  local_month,
  expense_category_id,
  expense_category_code,
  expense_category_name,
  count(*) as expense_count,
  sum(amount)::numeric(14, 2) as expense_total
from public.v_expense_report
group by shop_id, local_month, expense_category_id, expense_category_code, expense_category_name;

grant select on
  public.v_item_stock_truth,
  public.v_party_balance_truth,
  public.v_sales_report,
  public.v_receive_report,
  public.v_expense_report,
  public.v_payment_report,
  public.v_daily_profit,
  public.v_monthly_profit,
  public.v_monthly_sales,
  public.v_monthly_expenses
to authenticated;
