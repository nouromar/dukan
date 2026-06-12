-- ---------------------------------------------------------------------------
-- Per-invoice payment allocation (#234).
-- ---------------------------------------------------------------------------
--
-- Closes the gap documented in docs/payment-allocation.md § 3:
-- standalone post_payment previously wrote ZERO payment_allocation rows,
-- so the aging report had no per-invoice ledger for them. This migration
-- makes every standalone payment write rows — server-side FIFO by
-- default, or an explicit cashier-supplied list when overriding.
--
-- 1. post_payment — rewritten with optional p_allocations jsonb param.
-- 2. list_unpaid_invoices — read RPC powering the editor + the Party
--    detail "Open invoices" section.
-- 3. list_payment_allocations — read RPC for the payment-history
--    drilldown.
-- 4. v_party_aging — view consumed by the shop admin portal's aging
--    report (per docs/payment-allocation.md § 7.3).
--
-- Invariant: outstanding(txn) = total_amount - sum(payment_allocation.amount).
-- Embedded payment legs already write one allocation row per posted
-- sale/receive (migrations 0010 lines 562 + 891), so this invariant
-- holds before and after this migration.


-- ---------------------------------------------------------------------------
-- post_payment — FIFO by default, explicit list when p_allocations supplied
-- ---------------------------------------------------------------------------

drop function if exists public.post_payment(
  uuid, uuid, char, numeric, text, text, uuid, timestamptz, text
);

create or replace function public.post_payment(
  p_shop_id              uuid,
  p_party_id             uuid,
  p_direction            char,
  p_amount               numeric,
  p_payment_method_code  text,
  p_client_op_id         text default null,
  p_document_id          uuid default null,
  p_occurred_at          timestamptz default null,
  p_notes                text default null,
  p_allocations          jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_id     uuid;
  v_payment_id      uuid;
  v_method_id       uuid;
  v_party_type      text;
  v_receivable      numeric;
  v_payable         numeric;
  v_occurred_at     timestamptz := coalesce(p_occurred_at, pg_catalog.now());
  v_target_type     text;       -- 'sale' for I, 'receive' for O
  v_remaining       numeric;
  v_alloc_amount    numeric;
  v_alloc_sum       numeric;
  v_alloc_count     integer;
  v_distinct_count  integer;
  v_invoice_id      uuid;
  v_invoice_total   numeric;
  v_invoice_paid    numeric;
  v_invoice_open    numeric;
  v_actual_total    numeric;
  v_actual_type     text;
  v_actual_party    uuid;
  v_is_reversal     boolean;
  v_explicit        boolean := p_allocations is not null
                               and pg_catalog.jsonb_typeof(p_allocations) = 'array'
                               and pg_catalog.jsonb_array_length(p_allocations) > 0;
  r record;
begin
  perform public._require_ready_shop(p_shop_id);
  perform public._assert_document_in_shop(p_shop_id, p_document_id);

  if p_client_op_id is not null then
    select id into v_existing_id
    from public.payment
    where shop_id = p_shop_id and client_op_id = p_client_op_id;

    if v_existing_id is not null then
      return v_existing_id;
    end if;
  end if;

  if p_direction not in ('I', 'O') then
    raise exception 'Payment direction must be I or O';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  v_target_type := case when p_direction = 'I' then 'sale' else 'receive' end;

  select pt.code, p.receivable, p.payable
  into v_party_type, v_receivable, v_payable
  from public.party p
  join public.party_type pt on pt.id = p.type_id
  where p.shop_id = p_shop_id
    and p.id = p_party_id
    and p.is_active
  for update of p;

  if v_party_type is null then
    raise exception 'Party does not belong to this shop or is inactive';
  end if;

  if p_direction = 'I' then
    if v_party_type not in ('customer', 'both') then
      raise exception 'Inbound payment requires a customer party';
    end if;
    if p_amount > v_receivable then
      raise exception 'Payment exceeds customer receivable balance';
    end if;
  else
    if v_party_type not in ('supplier', 'both') then
      raise exception 'Outbound payment requires a supplier party';
    end if;
    if p_amount > v_payable then
      raise exception 'Payment exceeds supplier payable balance';
    end if;
  end if;

  v_method_id := public._payment_method_id(p_payment_method_code);

  -- Insert the payment row up front so the allocation rows can FK to it.
  insert into public.payment (
    shop_id, party_id, direction, amount, method_id, occurred_at,
    document_id, client_op_id, notes, created_by
  )
  values (
    p_shop_id, p_party_id, p_direction, p_amount, v_method_id, v_occurred_at,
    p_document_id, p_client_op_id, p_notes, auth.uid()
  )
  returning id into v_payment_id;

  if v_explicit then
    -- ---------------------------------------------------------------
    -- Explicit allocation path. Validate per docs/payment-allocation.md § 6.3.
    -- ---------------------------------------------------------------

    -- Rule 5: no duplicate transaction_id in the array.
    select pg_catalog.count(*), pg_catalog.count(distinct value->>'transaction_id')
    into v_alloc_count, v_distinct_count
    from pg_catalog.jsonb_array_elements(p_allocations);
    if v_alloc_count <> v_distinct_count then
      raise exception 'Allocation: duplicate transaction_id in list';
    end if;

    -- Rule 6: every amount > 0; Rule 4: sum equals p_amount.
    select pg_catalog.sum((value->>'amount')::numeric)
    into v_alloc_sum
    from pg_catalog.jsonb_array_elements(p_allocations);
    if v_alloc_sum is null or v_alloc_sum <> p_amount then
      raise exception 'Allocation: sum of allocations (%) must equal payment amount (%)',
                      coalesce(v_alloc_sum, 0), p_amount;
    end if;

    -- Iterate and validate each row, then write it.
    for r in
      select
        (value->>'transaction_id')::uuid as txn_id,
        (value->>'amount')::numeric as amt
      from pg_catalog.jsonb_array_elements(p_allocations)
    loop
      if r.amt <= 0 then
        raise exception 'Allocation: amount must be positive (got %)', r.amt;
      end if;

      -- Rule 1: txn belongs to this shop AND this party.
      -- Rule 2: posted, non-reversal sale (for I) or receive (for O).
      select t.total_amount, tt.code, t.party_id,
             (t.reverses_transaction_id is not null)
      into v_actual_total, v_actual_type, v_actual_party, v_is_reversal
      from public.txn t
      join public.transaction_type tt on tt.id = t.type_id
      join public.transaction_status ts on ts.id = t.status_id
      where t.shop_id = p_shop_id
        and t.id = r.txn_id
        and ts.code = 'posted'
      for update of t;

      if v_actual_total is null then
        raise exception 'Allocation: transaction % not posted or not in this shop', r.txn_id;
      end if;
      if v_is_reversal then
        raise exception 'Allocation: cannot allocate against reversal transaction %', r.txn_id;
      end if;
      if v_actual_party is null or v_actual_party <> p_party_id then
        raise exception 'Allocation: transaction % does not belong to party %', r.txn_id, p_party_id;
      end if;
      if v_actual_type <> v_target_type then
        raise exception 'Allocation: % direction expects % invoices; got %',
                        p_direction, v_target_type, v_actual_type;
      end if;

      -- Reject if the underlying invoice has been voided by a reversal.
      if exists (
        select 1 from public.txn rev
        where rev.shop_id = p_shop_id
          and rev.reverses_transaction_id = r.txn_id
      ) then
        raise exception 'Allocation: transaction % is voided', r.txn_id;
      end if;

      -- Rule 3: allocation cannot exceed this invoice's remaining open amount.
      select coalesce(pg_catalog.sum(pa.amount), 0)
      into v_invoice_paid
      from public.payment_allocation pa
      where pa.shop_id = p_shop_id and pa.transaction_id = r.txn_id;
      v_invoice_open := v_actual_total - v_invoice_paid;
      if r.amt > v_invoice_open then
        raise exception 'Allocation: % exceeds open balance of % on transaction %',
                        r.amt, v_invoice_open, r.txn_id;
      end if;

      insert into public.payment_allocation (shop_id, payment_id, transaction_id, amount)
      values (p_shop_id, v_payment_id, r.txn_id, r.amt);
    end loop;

  else
    -- ---------------------------------------------------------------
    -- Default path — server-side FIFO over open invoices, oldest first.
    -- ---------------------------------------------------------------
    v_remaining := p_amount;

    for r in
      select
        t.id,
        t.total_amount - coalesce(
          (select pg_catalog.sum(pa.amount) from public.payment_allocation pa
           where pa.shop_id = p_shop_id and pa.transaction_id = t.id),
          0
        ) as unpaid
      from public.txn t
      join public.transaction_type tt on tt.id = t.type_id
      join public.transaction_status ts on ts.id = t.status_id
      where t.shop_id = p_shop_id
        and t.party_id = p_party_id
        and ts.code = 'posted'
        and tt.code = v_target_type
        and t.reverses_transaction_id is null
        and not exists (
          select 1 from public.txn rev
          where rev.shop_id = p_shop_id
            and rev.reverses_transaction_id = t.id
        )
      order by t.occurred_at asc, t.id asc
      for update of t
    loop
      exit when v_remaining <= 0;
      if r.unpaid <= 0 then
        continue;
      end if;
      v_alloc_amount := least(r.unpaid, v_remaining);
      insert into public.payment_allocation (shop_id, payment_id, transaction_id, amount)
      values (p_shop_id, v_payment_id, r.id, v_alloc_amount);
      v_remaining := v_remaining - v_alloc_amount;
    end loop;

    if v_remaining > 0 then
      raise exception
        'Allocation residual: % left over on payment for party % — '
        'party balance and per-invoice ledger have drifted',
        v_remaining, p_party_id;
    end if;
  end if;

  -- Party balance always decremented by the full payment amount,
  -- regardless of which allocation path ran.
  if p_direction = 'I' then
    update public.party
    set receivable = receivable - p_amount
    where shop_id = p_shop_id and id = p_party_id;
  else
    update public.party
    set payable = payable - p_amount
    where shop_id = p_shop_id and id = p_party_id;
  end if;

  return v_payment_id;
exception
  when unique_violation then
    if p_client_op_id is not null then
      select id into v_existing_id
      from public.payment
      where shop_id = p_shop_id and client_op_id = p_client_op_id;

      if v_existing_id is not null then
        return v_existing_id;
      end if;
    end if;
    raise;
end;
$$;

revoke all on function public.post_payment(
  uuid, uuid, char, numeric, text, text, uuid, timestamptz, text, jsonb
) from public;
grant execute on function public.post_payment(
  uuid, uuid, char, numeric, text, text, uuid, timestamptz, text, jsonb
) to authenticated;


-- ---------------------------------------------------------------------------
-- list_unpaid_invoices — read RPC for the allocation editor + party detail
-- ---------------------------------------------------------------------------
--
-- Returns the party's open invoices for the matching direction, oldest
-- first. `remaining` is total_amount minus the sum of all
-- payment_allocation rows already posted against the invoice
-- (which include the embedded cash-at-till leg). Voided invoices are
-- excluded.

create or replace function public.list_unpaid_invoices(
  p_shop_id  uuid,
  p_party_id uuid,
  p_direction char
)
returns table (
  transaction_id   uuid,
  occurred_at      timestamptz,
  original_amount  numeric,
  already_paid     numeric,
  remaining        numeric,
  document_id      uuid
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_target_type text;
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to read open invoices for this shop';
  end if;

  if p_direction not in ('I', 'O') then
    raise exception 'Direction must be I or O';
  end if;

  v_target_type := case when p_direction = 'I' then 'sale' else 'receive' end;

  return query
  select
    t.id as transaction_id,
    t.occurred_at,
    t.total_amount as original_amount,
    coalesce(
      (select pg_catalog.sum(pa.amount) from public.payment_allocation pa
       where pa.shop_id = p_shop_id and pa.transaction_id = t.id),
      0
    ) as already_paid,
    t.total_amount - coalesce(
      (select pg_catalog.sum(pa.amount) from public.payment_allocation pa
       where pa.shop_id = p_shop_id and pa.transaction_id = t.id),
      0
    ) as remaining,
    t.document_id
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  join public.transaction_status ts on ts.id = t.status_id
  where t.shop_id = p_shop_id
    and t.party_id = p_party_id
    and ts.code = 'posted'
    and tt.code = v_target_type
    and t.reverses_transaction_id is null
    and not exists (
      select 1 from public.txn rev
      where rev.shop_id = p_shop_id
        and rev.reverses_transaction_id = t.id
    )
    and t.total_amount - coalesce(
      (select pg_catalog.sum(pa.amount) from public.payment_allocation pa
       where pa.shop_id = p_shop_id and pa.transaction_id = t.id),
      0
    ) > 0
  order by t.occurred_at asc, t.id asc;
end;
$$;

revoke all on function public.list_unpaid_invoices(uuid, uuid, char) from public;
grant execute on function public.list_unpaid_invoices(uuid, uuid, char) to authenticated;


-- ---------------------------------------------------------------------------
-- list_payment_allocations — per-invoice breakdown of a posted payment
-- ---------------------------------------------------------------------------
--
-- Used by the Payment history detail screen and the shop admin portal's
-- payment drilldown.

create or replace function public.list_payment_allocations(
  p_shop_id    uuid,
  p_payment_id uuid
)
returns table (
  transaction_id  uuid,
  amount          numeric,
  occurred_at     timestamptz,
  txn_type        text
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to read payment allocations for this shop';
  end if;

  return query
  select
    pa.transaction_id,
    pa.amount,
    t.occurred_at,
    tt.code as txn_type
  from public.payment_allocation pa
  join public.txn t on t.shop_id = pa.shop_id and t.id = pa.transaction_id
  join public.transaction_type tt on tt.id = t.type_id
  where pa.shop_id = p_shop_id
    and pa.payment_id = p_payment_id
  order by t.occurred_at asc, t.id asc;
end;
$$;

revoke all on function public.list_payment_allocations(uuid, uuid) from public;
grant execute on function public.list_payment_allocations(uuid, uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- v_party_aging — one row per (party, unpaid invoice). Shop admin portal
-- groups by aging bucket (0-30 / 31-60 / 61-90 / >90 days) at render time.
-- ---------------------------------------------------------------------------

create or replace view public.v_party_aging
with (security_invoker = true)
as
select
  t.shop_id,
  t.party_id,
  t.id as transaction_id,
  tt.code as transaction_type,
  t.occurred_at,
  s.timezone,
  ((pg_catalog.now() at time zone s.timezone)::date
   - (t.occurred_at at time zone s.timezone)::date) as days_open,
  t.total_amount,
  coalesce(
    (select pg_catalog.sum(pa.amount) from public.payment_allocation pa
     where pa.shop_id = t.shop_id and pa.transaction_id = t.id),
    0
  ) as allocated_amount,
  t.total_amount - coalesce(
    (select pg_catalog.sum(pa.amount) from public.payment_allocation pa
     where pa.shop_id = t.shop_id and pa.transaction_id = t.id),
    0
  ) as outstanding
from public.txn t
join public.transaction_type tt on tt.id = t.type_id
join public.transaction_status ts on ts.id = t.status_id
join public.shop s on s.id = t.shop_id
where ts.code = 'posted'
  and tt.code in ('sale', 'receive')
  and t.reverses_transaction_id is null
  and t.party_id is not null
  and not exists (
    select 1 from public.txn rev
    where rev.shop_id = t.shop_id
      and rev.reverses_transaction_id = t.id
  );

grant select on public.v_party_aging to authenticated;


-- ---------------------------------------------------------------------------
-- v_party_balance_truth — replace the 0013 definition.
-- ---------------------------------------------------------------------------
--
-- The 0013 view computed ledger balance as:
--   sum(total - paid_amount) on posted sales/receives
--   minus sum of "standalone" payments (those WITHOUT allocation rows).
--
-- That made sense when post_payment wrote zero allocation rows. After
-- this migration, every standalone payment also writes allocations,
-- so the "standalone" CTE returns zero and the view double-counts the
-- pay-down (variance ≈ -payment.amount per party).
--
-- New formula uses the single invariant: outstanding(t) = total_amount
-- minus sum of all payment_allocation rows against t.

drop view if exists public.v_party_balance_truth;

create view public.v_party_balance_truth
with (security_invoker = true)
as
with txn_outstanding as (
  select
    t.shop_id,
    t.party_id,
    tt.code as txn_type,
    t.total_amount - coalesce(
      (select pg_catalog.sum(pa.amount) from public.payment_allocation pa
       where pa.shop_id = t.shop_id and pa.transaction_id = t.id),
      0
    ) as outstanding
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  join public.transaction_status ts on ts.id = t.status_id
  where t.party_id is not null
    and ts.code = 'posted'
    and tt.code in ('sale', 'receive')
    and t.reverses_transaction_id is null
    and not exists (
      select 1 from public.txn rev
      where rev.shop_id = t.shop_id
        and rev.reverses_transaction_id = t.id
    )
),
party_outstanding as (
  select
    shop_id,
    party_id,
    pg_catalog.sum(case when txn_type = 'sale' then outstanding else 0 end)
      as ledger_receivable_raw,
    pg_catalog.sum(case when txn_type = 'receive' then outstanding else 0 end)
      as ledger_payable_raw
  from txn_outstanding
  group by shop_id, party_id
)
select
  p.shop_id,
  p.id as party_id,
  p.name as party_name,
  pt.code as party_type_code,
  p.receivable as cached_receivable,
  coalesce(po.ledger_receivable_raw, 0)::numeric(14, 2) as ledger_receivable,
  (p.receivable - coalesce(po.ledger_receivable_raw, 0))::numeric(14, 2)
    as receivable_variance,
  p.payable as cached_payable,
  coalesce(po.ledger_payable_raw, 0)::numeric(14, 2) as ledger_payable,
  (p.payable - coalesce(po.ledger_payable_raw, 0))::numeric(14, 2)
    as payable_variance
from public.party p
join public.party_type pt on pt.id = p.type_id
left join party_outstanding po
  on po.shop_id = p.shop_id
  and po.party_id = p.id;

grant select on public.v_party_balance_truth to authenticated;
