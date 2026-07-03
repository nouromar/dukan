-- 0098_post_payment_client_id.sql
--
-- Offline VOID, part 2 of 4 (payment). Same change as 0097 (expense) applied to
-- post_payment: an optional client-supplied id so an offline payment has a
-- stable UUID that survives sync and can be voided offline. post_payment keys
-- on the `payment` table and returns a PAYMENT id, so the client-minted id is a
-- payment id (which is what void_payment takes, and what the local mirror stores
-- as its txn_id).
--
--   * New TAIL param `p_payment_id uuid default null` (after p_allocations).
--   * The payment insert lists `id = coalesce(p_payment_id, pg_catalog.gen_random_uuid())`.
--   * Everything else — the receivable/payable guards, explicit + FIFO
--     allocation, idempotency (client_op_id short-circuit + unique_violation
--     handler) — is reproduced verbatim from 0087.
--
-- Drop the old 10-arg signature first (adding a parameter can't be done with
-- create-or-replace and would leave an ambiguous overload).

drop function if exists public.post_payment(
  uuid, uuid, char, numeric, text, text, uuid, timestamptz, text, jsonb
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
  p_allocations          jsonb default null,
  p_payment_id           uuid default null
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
    id, shop_id, party_id, direction, amount, method_id, occurred_at,
    document_id, client_op_id, notes, created_by
  )
  values (
    coalesce(p_payment_id, pg_catalog.gen_random_uuid()),
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

revoke all on function public.post_payment(
  uuid, uuid, char, numeric, text, text, uuid, timestamptz, text, jsonb, uuid
) from public;
grant execute on function public.post_payment(
  uuid, uuid, char, numeric, text, text, uuid, timestamptz, text, jsonb, uuid
) to authenticated;
