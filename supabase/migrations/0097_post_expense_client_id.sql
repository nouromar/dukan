-- 0097_post_expense_client_id.sql
--
-- Offline VOID, part 1 of 4 (expense). Today post_expense mints the txn id
-- server-side (table default extensions.gen_random_uuid()), so an offline
-- expense's local mirror row uses the client_op_id STRING as a placeholder id.
-- Voiding it before sync sent that non-UUID to void_expense (22P02).
--
-- Give the client the option to supply the txn id up front (a v4 UUID it also
-- writes to its local mirror), exactly like the tier-2 create RPCs (0093-0095):
-- a stable id that survives sync, so an offline expense can be voided offline
-- (the queue drains post_expense then void_expense, both referencing it).
--
--   * New TAIL param `p_txn_id uuid default null`. Backward-compatible: null =
--     today's behaviour (server mints the id).
--   * The txn insert now lists `id = coalesce(p_txn_id, pg_catalog.gen_random_uuid())`.
--     pg_catalog (not extensions) so it stays safe under the migration-test role.
--   * Idempotency is UNCHANGED — the up-front client_op_id short-circuit and the
--     unique_violation handler already dedupe replays (and now also catch a raw
--     id collision, re-selecting the winner by client_op_id).
--
-- Must drop the old 8-arg signature first: adding a parameter changes the
-- function signature (create-or-replace can't), and leaving the old overload
-- would make the call ambiguous.

drop function if exists public.post_expense(
  uuid, uuid, numeric, text, uuid, text, timestamptz, text
);

create or replace function public.post_expense(
  p_shop_id uuid,
  p_expense_category_id uuid,
  p_amount numeric,
  p_payment_method_code text default null,
  p_document_id uuid default null,
  p_client_op_id text default null,
  p_occurred_at timestamptz default null,
  p_notes text default null,
  p_txn_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_id uuid;
  v_txn_id uuid;
  v_payment_method_id uuid;
  v_occurred_at timestamptz := coalesce(p_occurred_at, pg_catalog.now());
begin
  perform public._require_ready_shop(p_shop_id);
  perform public._assert_document_in_shop(p_shop_id, p_document_id);

  if p_client_op_id is not null then
    select id into v_existing_id
    from public.txn
    where shop_id = p_shop_id and client_op_id = p_client_op_id;

    if v_existing_id is not null then
      return v_existing_id;
    end if;
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Expense amount must be greater than zero';
  end if;

  if not exists (
    select 1
    from public.expense_category
    where shop_id = p_shop_id and id = p_expense_category_id and is_active
  ) then
    raise exception 'Expense category does not belong to this shop or is inactive';
  end if;

  if p_payment_method_code is not null then
    v_payment_method_id := public._ref_id('payment_method', p_payment_method_code);
  end if;

  insert into public.txn (
    id,
    shop_id,
    type_id,
    status_id,
    occurred_at,
    posted_at,
    total_amount,
    paid_amount,
    payment_method_id,
    document_id,
    client_op_id,
    notes,
    created_by
  )
  values (
    coalesce(p_txn_id, pg_catalog.gen_random_uuid()),
    p_shop_id,
    public._ref_id('transaction_type', 'expense'),
    public._ref_id('transaction_status', 'posted'),
    v_occurred_at,
    pg_catalog.now(),
    p_amount,
    p_amount,
    v_payment_method_id,
    p_document_id,
    p_client_op_id,
    p_notes,
    auth.uid()
  )
  returning id into v_txn_id;

  insert into public.transaction_line (
    shop_id,
    transaction_id,
    line_no,
    expense_category_id,
    unit_amount,
    line_total
  )
  values (
    p_shop_id,
    v_txn_id,
    1,
    p_expense_category_id,
    p_amount,
    p_amount
  );

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'expense.post',
    p_entity_type  => 'txn',
    p_entity_id    => v_txn_id,
    p_after        => pg_catalog.jsonb_build_object(
      'amount',               p_amount,
      'expense_category_id',  p_expense_category_id,
      'client_op_id',         p_client_op_id
    ),
    p_client_op_id => p_client_op_id
  );

  return v_txn_id;
exception
  when unique_violation then
    if p_client_op_id is not null then
      select id into v_existing_id
      from public.txn
      where shop_id = p_shop_id and client_op_id = p_client_op_id;

      if v_existing_id is not null then
        return v_existing_id;
      end if;
    end if;
    raise;
end;
$$;

revoke all on function public.post_expense(
  uuid, uuid, numeric, text, uuid, text, timestamptz, text, uuid
) from public;
grant execute on function public.post_expense(
  uuid, uuid, numeric, text, uuid, text, timestamptz, text, uuid
) to authenticated;
