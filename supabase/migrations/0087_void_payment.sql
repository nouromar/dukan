-- 0087_void_payment.sql
--
-- Void a posted payment, append-only, restoring the party balance and
-- re-inflating the invoices the payment had settled.
--
-- Model (validated design): a payment can't be negated at the allocation level
-- (`payment.amount > 0`), and the ledger is append-only. So void_payment inserts
-- a direction-FLIPPED marker payment (`reverses_payment_id` set, no allocations),
-- restores the cached party balance inline, and every "remaining = total − Σ
-- allocations" derivation excludes allocations whose payment was reversed — so
-- the settled invoices re-open. The flip makes v_cash_position (0060) auto-net
-- to zero with no change to that view (same trick void_sale's refund leg uses).
--
-- Correctness: post_payment decremented the balance by the FULL amount, so the
-- inline +amount restore exactly matches the re-derived ledger (excluded
-- allocations re-add the same amount). v_party_balance_truth stays balanced.
--
-- NOTE (display): the marker is an opposite-direction payment that will appear
-- in the payment LISTS until a follow-up (0088) hides markers + strikes through
-- reversed originals there. Balances/invoices are already correct; this is
-- cosmetic. The detail screen (get_payment) already reflects is_voided.

-- ---------------------------------------------------------------------------
-- 1. Schema: reversal link + settlement-leg discriminator.
-- ---------------------------------------------------------------------------

alter table public.payment
  add column if not exists reverses_payment_id uuid;

alter table public.payment
  add constraint payment_reverses_payment_fk
  foreign key (shop_id, reverses_payment_id)
  references public.payment(shop_id, id) on delete restrict;

-- One marker per reversed payment.
create unique index payment_reverses_payment_idx
  on public.payment (shop_id, reverses_payment_id)
  where reverses_payment_id is not null;

-- Embedded at-till legs (the cash a customer/​supplier pays WHILE a sale/receive
-- is rung up) must NOT be voidable on their own — they didn't move the party
-- balance the standalone way, so void via the sale/receive instead. post_sale /
-- post_receive stamp those legs with a `<op>:payment` client_op_id, so a STORED
-- generated column flags them with zero changes to those RPCs and auto-backfill.
alter table public.payment
  add column is_settlement_leg boolean
  generated always as (
    client_op_id is not null and client_op_id like '%:payment'
  ) stored;

-- ---------------------------------------------------------------------------
-- 2. post_payment — re-created from 0053 with the reversed-payment exclusion
--    added to BOTH allocation paths (so a re-payment after a void sees the
--    invoice open again).
-- ---------------------------------------------------------------------------

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
  v_target_type     text;
  v_remaining       numeric;
  v_alloc_amount    numeric;
  v_alloc_sum       numeric;
  v_alloc_count     integer;
  v_distinct_count  integer;
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
    select pg_catalog.count(*), pg_catalog.count(distinct value->>'transaction_id')
    into v_alloc_count, v_distinct_count
    from pg_catalog.jsonb_array_elements(p_allocations);
    if v_alloc_count <> v_distinct_count then
      raise exception 'Allocation: duplicate transaction_id in list';
    end if;

    select pg_catalog.sum((value->>'amount')::numeric)
    into v_alloc_sum
    from pg_catalog.jsonb_array_elements(p_allocations);
    if v_alloc_sum is null or v_alloc_sum <> p_amount then
      raise exception 'Allocation: sum of allocations (%) must equal payment amount (%)',
                      coalesce(v_alloc_sum, 0), p_amount;
    end if;

    for r in
      select
        (value->>'transaction_id')::uuid as txn_id,
        (value->>'amount')::numeric as amt
      from pg_catalog.jsonb_array_elements(p_allocations)
    loop
      if r.amt <= 0 then
        raise exception 'Allocation: amount must be positive (got %)', r.amt;
      end if;

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

      if exists (
        select 1 from public.txn rev
        where rev.shop_id = p_shop_id
          and rev.reverses_transaction_id = r.txn_id
      ) then
        raise exception 'Allocation: transaction % is voided', r.txn_id;
      end if;

      -- Open balance excludes allocations whose payment was reversed (0087).
      select coalesce(pg_catalog.sum(pa.amount), 0)
      into v_invoice_paid
      from public.payment_allocation pa
      where pa.shop_id = p_shop_id and pa.transaction_id = r.txn_id
        and not exists (
          select 1 from public.payment rvp
          where rvp.shop_id = pa.shop_id
            and rvp.reverses_payment_id = pa.payment_id
        );
      v_invoice_open := v_actual_total - v_invoice_paid;
      if r.amt > v_invoice_open then
        raise exception 'Allocation: % exceeds open balance of % on transaction %',
                        r.amt, v_invoice_open, r.txn_id;
      end if;

      insert into public.payment_allocation (shop_id, payment_id, transaction_id, amount)
      values (p_shop_id, v_payment_id, r.txn_id, r.amt);
    end loop;

  else
    v_remaining := p_amount;

    for r in
      select
        t.id,
        t.total_amount - coalesce(
          (select pg_catalog.sum(pa.amount) from public.payment_allocation pa
           where pa.shop_id = p_shop_id and pa.transaction_id = t.id
             and not exists (
               select 1 from public.payment rvp
               where rvp.shop_id = pa.shop_id
                 and rvp.reverses_payment_id = pa.payment_id
             )),
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

  if p_direction = 'I' then
    update public.party
    set receivable = receivable - p_amount
    where shop_id = p_shop_id and id = p_party_id;
  else
    update public.party
    set payable = payable - p_amount
    where shop_id = p_shop_id and id = p_party_id;
  end if;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'payment.post',
    p_entity_type  => 'payment',
    p_entity_id    => v_payment_id,
    p_after        => pg_catalog.jsonb_build_object(
      'party_id',      p_party_id,
      'direction',     p_direction,
      'amount',        p_amount,
      'explicit',      v_explicit,
      'client_op_id',  p_client_op_id
    ),
    p_client_op_id => p_client_op_id
  );

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

-- ---------------------------------------------------------------------------
-- 3. list_unpaid_invoices — re-created with the exclusion on its 3 subqueries.
-- ---------------------------------------------------------------------------

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
       where pa.shop_id = p_shop_id and pa.transaction_id = t.id
         and not exists (select 1 from public.payment rvp
           where rvp.shop_id = pa.shop_id and rvp.reverses_payment_id = pa.payment_id)),
      0
    ) as already_paid,
    t.total_amount - coalesce(
      (select pg_catalog.sum(pa.amount) from public.payment_allocation pa
       where pa.shop_id = p_shop_id and pa.transaction_id = t.id
         and not exists (select 1 from public.payment rvp
           where rvp.shop_id = pa.shop_id and rvp.reverses_payment_id = pa.payment_id)),
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
       where pa.shop_id = p_shop_id and pa.transaction_id = t.id
         and not exists (select 1 from public.payment rvp
           where rvp.shop_id = pa.shop_id and rvp.reverses_payment_id = pa.payment_id)),
      0
    ) > 0
  order by t.occurred_at asc, t.id asc;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. v_party_aging — re-created with the exclusion.
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
     where pa.shop_id = t.shop_id and pa.transaction_id = t.id
       and not exists (select 1 from public.payment rvp
         where rvp.shop_id = pa.shop_id and rvp.reverses_payment_id = pa.payment_id)),
    0
  ) as allocated_amount,
  t.total_amount - coalesce(
    (select pg_catalog.sum(pa.amount) from public.payment_allocation pa
     where pa.shop_id = t.shop_id and pa.transaction_id = t.id
       and not exists (select 1 from public.payment rvp
         where rvp.shop_id = pa.shop_id and rvp.reverses_payment_id = pa.payment_id)),
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
-- 5. v_party_balance_truth — re-created with the exclusion (the reconciliation
--    proof: cached == ledger after a void).
-- ---------------------------------------------------------------------------

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
       where pa.shop_id = t.shop_id and pa.transaction_id = t.id
         and not exists (select 1 from public.payment rvp
           where rvp.shop_id = pa.shop_id and rvp.reverses_payment_id = pa.payment_id)),
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

-- ---------------------------------------------------------------------------
-- 6. _build_unpaid_invoices_payload — re-created with the exclusion on
--    already_paid, plus the marker's created_at folded into latest_change_at
--    so a re-inflated invoice re-syncs to the mobile mirror after a void.
-- ---------------------------------------------------------------------------

create or replace function public._build_unpaid_invoices_payload(
  p_shop_id uuid,
  p_since   timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  with txn_payable as (
    select
      t.id                              as txn_id,
      t.shop_id,
      t.party_id,
      case when tt.code = 'sale' then 'I' else 'O' end as direction,
      t.occurred_at,
      t.created_at,
      t.total_amount                    as original_amount,
      t.document_id,
      coalesce(
        (
          select sum(pa.amount)
          from public.payment_allocation pa
          where pa.shop_id = t.shop_id
            and pa.transaction_id = t.id
            and not exists (select 1 from public.payment rvp
              where rvp.shop_id = pa.shop_id and rvp.reverses_payment_id = pa.payment_id)
        ),
        0
      )                                 as already_paid,
      greatest(
        t.created_at,
        coalesce(
          (select max(pa.created_at)
           from public.payment_allocation pa
           where pa.shop_id = t.shop_id and pa.transaction_id = t.id),
          t.created_at
        ),
        coalesce(
          (select max(rvp.created_at)
           from public.payment rvp
           join public.payment_allocation pa3
             on pa3.shop_id = rvp.shop_id and pa3.payment_id = rvp.reverses_payment_id
           where rvp.shop_id = t.shop_id and pa3.transaction_id = t.id),
          t.created_at
        )
      )                                 as latest_change_at
    from public.txn t
    join public.transaction_type tt on tt.id = t.type_id
    join public.transaction_status ts on ts.id = t.status_id
    where t.shop_id   = p_shop_id
      and ts.code     = 'posted'
      and tt.code in ('sale', 'receive')
      and t.party_id is not null
      and t.reverses_transaction_id is null
      and not exists (
        select 1 from public.txn rev
        where rev.shop_id = t.shop_id
          and rev.reverses_transaction_id = t.id
      )
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.occurred_at_ms asc), '[]'::jsonb)
    into v_rows
  from (
    select
      shop_id,
      party_id,
      direction,
      txn_id,
      extract(epoch from occurred_at) * 1000 as occurred_at_ms,
      original_amount,
      already_paid,
      (original_amount - already_paid) as remaining,
      document_id,
      extract(epoch from latest_change_at) * 1000 as server_updated_at_ms
    from txn_payable
    where p_since is null or latest_change_at > p_since
  ) r;

  return jsonb_build_object('unpaid_invoices', v_rows);
end;
$$;

revoke all on function public._build_unpaid_invoices_payload(uuid, timestamptz) from public;

-- ---------------------------------------------------------------------------
-- 7. get_payment — re-created (replaces 0083) with the flags the app needs to
--    pre-gate the VOID button: created_at, is_voided, is_refund,
--    is_settlement_leg. Only non-marker payments are returned. Return type
--    changes vs 0083, so drop first.
-- ---------------------------------------------------------------------------

drop function if exists public.get_payment(uuid, uuid);

create or replace function public.get_payment(
  p_shop_id    uuid,
  p_payment_id uuid
)
returns table (
  payment_id          uuid,
  occurred_at         timestamptz,
  created_at          timestamptz,
  party_id            uuid,
  party_name          text,
  direction           char(1),
  amount              numeric,
  payment_method_code text,
  notes               text,
  is_voided           boolean,
  is_refund           boolean,
  is_settlement_leg   boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not public.auth_can_access_shop(p_shop_id) then
    raise exception 'Not allowed to view payments for this shop';
  end if;

  return query
  select
    pay.id          as payment_id,
    pay.occurred_at,
    pay.created_at,
    pay.party_id,
    p.name          as party_name,
    pay.direction,
    pay.amount,
    pm.code         as payment_method_code,
    pay.notes,
    exists (
      select 1 from public.payment m
      where m.shop_id = p_shop_id and m.reverses_payment_id = pay.id
    ) as is_voided,
    (pay.refund_of_transaction_id is not null) as is_refund,
    pay.is_settlement_leg
  from public.payment pay
  left join public.party p on p.id = pay.party_id
  join public.payment_method pm on pm.id = pay.method_id
  where pay.shop_id = p_shop_id
    and pay.id = p_payment_id
    and pay.reverses_payment_id is null;
end;
$$;

revoke all on function public.get_payment(uuid, uuid) from public;
grant execute on function public.get_payment(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. void_payment — the reversal RPC.
-- ---------------------------------------------------------------------------

create or replace function public.void_payment(
  p_shop_id      uuid,
  p_payment_id   uuid,
  p_client_op_id text default null,
  p_reason       text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_replay uuid;
  v_existing_marker uuid;
  v_party_id        uuid;
  v_direction       char(1);
  v_amount          numeric;
  v_method_id       uuid;
  v_created_at      timestamptz;
  v_refund_of       uuid;
  v_settlement_leg  boolean;
  v_reverses        uuid;
  v_marker_id       uuid;
  v_now             timestamptz := pg_catalog.now();
  v_window_days     int;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only the shop owner can void a payment';
  end if;

  v_window_days := public._void_window_days(
    p_shop_id, 'void_window_days_payment', 7);

  -- Idempotent replay: a marker already carrying this op id.
  if p_client_op_id is not null then
    select id into v_existing_replay
    from public.payment
    where shop_id = p_shop_id and client_op_id = p_client_op_id
      and reverses_payment_id is not null;
    if v_existing_replay is not null then
      return v_existing_replay;
    end if;
  end if;

  -- Load + lock the original. `reverses_payment_id is null` rejects "it is
  -- itself a marker".
  select party_id, direction, amount, method_id, created_at,
         refund_of_transaction_id, is_settlement_leg
  into v_party_id, v_direction, v_amount, v_method_id, v_created_at,
       v_refund_of, v_settlement_leg
  from public.payment
  where shop_id = p_shop_id and id = p_payment_id
    and reverses_payment_id is null
  for update;

  if v_direction is null then
    raise exception 'Payment not found (or it is itself a reversal)';
  end if;
  if v_refund_of is not null then
    raise exception 'Cannot void a refund payment; it is part of a sale void';
  end if;
  if v_settlement_leg then
    raise exception
      'This payment was taken at the till; void the sale or receive instead';
  end if;
  if v_created_at < v_now - make_interval(days => v_window_days) then
    raise exception 'Payment is outside the %-day void window', v_window_days;
  end if;

  -- Already voided?
  select id into v_existing_marker
  from public.payment
  where shop_id = p_shop_id and reverses_payment_id = p_payment_id;
  if v_existing_marker is not null then
    raise exception 'Payment was already voided';
  end if;

  -- Lock the party so the balance restore is serialized.
  perform 1 from public.party
  where shop_id = p_shop_id and id = v_party_id
  for update;

  -- Flipped marker: opposite direction, same amount/method, no allocations.
  insert into public.payment (
    shop_id, party_id, direction, amount, method_id, occurred_at,
    reverses_payment_id, client_op_id, notes, created_by
  )
  values (
    p_shop_id, v_party_id,
    case when v_direction = 'I' then 'O' else 'I' end,
    v_amount, v_method_id, v_now,
    p_payment_id, p_client_op_id,
    'Reversal of payment ' || p_payment_id::text,
    auth.uid()
  )
  returning id into v_marker_id;

  -- Restore the cached balance (only ever increases — check(>=0) safe).
  if v_direction = 'I' then
    update public.party set receivable = receivable + v_amount
    where shop_id = p_shop_id and id = v_party_id;
  else
    update public.party set payable = payable + v_amount
    where shop_id = p_shop_id and id = v_party_id;
  end if;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'payment.void',
    p_entity_type  => 'payment',
    p_entity_id    => p_payment_id,
    p_before       => pg_catalog.jsonb_build_object(
      'party_id',  v_party_id,
      'direction', v_direction,
      'amount',    v_amount
    ),
    p_after        => pg_catalog.jsonb_build_object(
      'marker_payment_id', v_marker_id
    ),
    p_reason       => coalesce(
      nullif(pg_catalog.btrim(p_reason), ''),
      'Owner-initiated void within the payment correction window'
    ),
    p_client_op_id => p_client_op_id
  );

  return v_marker_id;
exception
  when unique_violation then
    if p_client_op_id is not null then
      select id into v_existing_replay
      from public.payment
      where shop_id = p_shop_id and client_op_id = p_client_op_id
        and reverses_payment_id is not null;
      if v_existing_replay is not null then
        return v_existing_replay;
      end if;
    end if;
    raise;
end;
$$;

revoke all on function public.void_payment(uuid, uuid, text, text) from public;
grant execute on function public.void_payment(uuid, uuid, text, text) to authenticated;
