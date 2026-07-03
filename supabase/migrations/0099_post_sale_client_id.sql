-- 0099_post_sale_client_id.sql
--
-- Offline VOID, part 3 of 4 (sale). Same change as 0097/0098 applied to
-- post_sale: an optional client-supplied txn id so an offline sale has a stable
-- UUID that survives sync and can be voided offline.
--
--   * New TAIL param `p_txn_id uuid default null`. The MAIN txn insert lists
--     `id = coalesce(p_txn_id, pg_catalog.gen_random_uuid())`.
--   * The cash-at-till SETTLEMENT LEG payment stays server-minted with its
--     `<op>:payment` client_op_id (drives is_settlement_leg + the list_payments
--     hide filter) — do NOT reuse the client txn id for it (it would collide
--     with the sale's own PK). Everything else (lines, COGS, stock, price
--     override, idempotency) is reproduced verbatim from 0010.
--
-- Drop the old 9-arg signature first.

drop function if exists public.post_sale(
  uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text
);

create or replace function public.post_sale(
  p_shop_id uuid,
  p_party_id uuid default null,
  p_lines jsonb default null,
  p_paid_amount numeric default null,
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
  v_payment_id uuid;
  v_line jsonb;
  v_line_no integer := 0;
  v_shop_item_unit_id uuid;
  v_shop_item_id uuid;
  v_unit_code text;
  v_unit_id uuid;
  v_conversion numeric;
  v_line_id uuid;
  v_quantity numeric;
  v_base_quantity numeric;
  v_unit_price numeric;
  v_existing_sale_price numeric;
  v_line_total numeric;
  v_total numeric := 0;
  v_paid numeric;
  v_unpaid numeric;
  v_occurred_at timestamptz := coalesce(p_occurred_at, pg_catalog.now());
  v_current_stock numeric;
  v_avg_cost numeric;
  v_new_stock numeric;
  v_cogs_total numeric;
  v_payment_method_id uuid;
  v_item_name text;
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

  if p_party_id is not null then
    perform public._assert_party_kind(p_shop_id, p_party_id, 'customer');
  end if;

  if p_lines is null
    or pg_catalog.jsonb_typeof(p_lines) <> 'array'
    or pg_catalog.jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one sale line is required';
  end if;

  insert into public.txn (
    id,
    shop_id,
    type_id,
    status_id,
    party_id,
    occurred_at,
    posted_at,
    total_amount,
    paid_amount,
    document_id,
    client_op_id,
    notes,
    created_by
  )
  values (
    coalesce(p_txn_id, pg_catalog.gen_random_uuid()),
    p_shop_id,
    public._ref_id('transaction_type', 'sale'),
    public._ref_id('transaction_status', 'posted'),
    p_party_id,
    v_occurred_at,
    pg_catalog.now(),
    0,
    0,
    p_document_id,
    p_client_op_id,
    p_notes,
    auth.uid()
  )
  returning id into v_txn_id;

  for v_line in select value from pg_catalog.jsonb_array_elements(p_lines) as t(value)
  loop
    v_line_no := v_line_no + 1;
    v_shop_item_unit_id := nullif(v_line->>'shop_item_unit_id', '')::uuid;
    v_quantity := nullif(v_line->>'quantity', '')::numeric;
    v_unit_price := nullif(v_line->>'unit_price', '')::numeric;

    if v_shop_item_unit_id is null or v_quantity is null then
      raise exception 'Sale line % is missing shop_item_unit_id or quantity', v_line_no;
    end if;

    if v_quantity <= 0 then
      raise exception 'Sale line % quantity must be greater than zero', v_line_no;
    end if;

    if v_unit_price is not null and v_unit_price < 0 then
      raise exception 'Sale line % unit price cannot be negative', v_line_no;
    end if;

    -- Resolve packaging → shop_item + sale_price + conversion.
    select siu.shop_item_id, siu.unit_code, siu.conversion_to_base, siu.sale_price
    into v_shop_item_id, v_unit_code, v_conversion, v_existing_sale_price
    from public.shop_item_unit siu
    where siu.shop_id = p_shop_id
      and siu.id = v_shop_item_unit_id
      and siu.is_active;

    if v_shop_item_id is null then
      raise exception 'Sale line % packaging does not belong to this shop or is inactive', v_line_no;
    end if;

    select id into v_unit_id from public.unit where code = v_unit_code;
    if v_unit_id is null then
      raise exception 'Sale line % unit % is not in the global unit table', v_line_no, v_unit_code;
    end if;

    if v_unit_price is null then
      v_unit_price := v_existing_sale_price;
    end if;

    if v_unit_price is null then
      raise exception 'Sale line % requires a unit price', v_line_no;
    end if;

    -- Lock the shop_item row before reading current_stock / avg_cost.
    select current_stock, avg_cost
    into v_current_stock, v_avg_cost
    from public.shop_item si
    where si.shop_id = p_shop_id
      and si.id = v_shop_item_id
      and si.is_active
    for update;

    if v_current_stock is null then
      raise exception 'Sale line % shop_item is inactive or missing', v_line_no;
    end if;

    v_item_name := public._resolve_item_name_snapshot(p_shop_id, v_shop_item_id);

    v_base_quantity := v_quantity * v_conversion;
    v_line_total := pg_catalog.round(v_quantity * v_unit_price, 2);
    -- COGS snapshots the per-base-unit avg_cost at posting time.
    -- Sales never re-cost; only receives + adjustments do.
    v_cogs_total := pg_catalog.round(v_base_quantity * v_avg_cost, 2);

    insert into public.transaction_line (
      shop_id,
      transaction_id,
      line_no,
      item_id,
      shop_item_unit_id,
      quantity,
      unit_id,
      base_quantity,
      unit_amount,
      item_name_snapshot,
      unit_code_snapshot,
      unit_conversion_to_base_snapshot,
      line_total,
      cogs_unit_cost,
      cogs_total
    )
    values (
      p_shop_id,
      v_txn_id,
      v_line_no,
      v_shop_item_id,
      v_shop_item_unit_id,
      v_quantity,
      v_unit_id,
      v_base_quantity,
      v_unit_price,
      v_item_name,
      v_unit_code,
      v_conversion,
      v_line_total,
      v_avg_cost,
      v_cogs_total
    )
    returning id into v_line_id;

    insert into public.stock_movement (
      shop_id,
      item_id,
      transaction_line_id,
      quantity_delta,
      unit_cost,
      occurred_at
    )
    values (
      p_shop_id,
      v_shop_item_id,
      v_line_id,
      -v_base_quantity,
      v_avg_cost,
      v_occurred_at
    );

    v_new_stock := v_current_stock - v_base_quantity;

    update public.shop_item
    set current_stock = v_new_stock
    where shop_id = p_shop_id and id = v_shop_item_id;

    -- Negative-stock policy (locked decision): allow, warn, don't block.
    if v_new_stock < 0 then
      raise notice 'Stock for shop_item % is now %', v_shop_item_id, v_new_stock;
    end if;

    -- Persist the cashier's price override on the packaging row when it
    -- truly diverges from the stored sale_price (or the packaging had
    -- no price yet). Don't blindly stamp on every sale.
    if v_existing_sale_price is null
       or v_existing_sale_price is distinct from v_unit_price then
      update public.shop_item_unit
      set sale_price = v_unit_price
      where shop_id = p_shop_id and id = v_shop_item_unit_id;
    end if;

    v_total := v_total + v_line_total;
  end loop;

  v_paid := coalesce(p_paid_amount, v_total);

  if v_paid < 0 then
    raise exception 'Paid amount cannot be negative';
  end if;

  if v_paid > v_total then
    raise exception 'Paid amount cannot exceed sale total';
  end if;

  v_unpaid := v_total - v_paid;

  if v_unpaid > 0 and p_party_id is null then
    raise exception 'Debt or partial sale requires a customer';
  end if;

  if v_paid > 0 then
    v_payment_method_id := public._payment_method_id(p_payment_method_code);
  end if;

  update public.txn
  set total_amount = v_total,
      paid_amount = v_paid,
      payment_method_id = case when v_paid > 0 then v_payment_method_id else null end
  where shop_id = p_shop_id and id = v_txn_id;

  if p_party_id is not null and v_unpaid > 0 then
    update public.party
    set receivable = receivable + v_unpaid
    where shop_id = p_shop_id and id = p_party_id;
  end if;

  if v_paid > 0 then
    insert into public.payment (
      shop_id,
      party_id,
      direction,
      amount,
      method_id,
      occurred_at,
      document_id,
      client_op_id,
      notes,
      created_by
    )
    values (
      p_shop_id,
      p_party_id,
      'I',
      v_paid,
      v_payment_method_id,
      v_occurred_at,
      p_document_id,
      case when p_client_op_id is null then null else p_client_op_id || ':payment' end,
      p_notes,
      auth.uid()
    )
    returning id into v_payment_id;

    if p_party_id is not null then
      insert into public.payment_allocation (shop_id, payment_id, transaction_id, amount)
      values (p_shop_id, v_payment_id, v_txn_id, v_paid);
    end if;
  end if;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'sale.post',
    p_entity_type  => 'txn',
    p_entity_id    => v_txn_id,
    p_after        => pg_catalog.jsonb_build_object(
      'total_amount',  v_total,
      'paid_amount',   v_paid,
      'party_id',      p_party_id,
      'client_op_id',  p_client_op_id
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

revoke all on function public.post_sale(
  uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text, uuid
) from public;
grant execute on function public.post_sale(
  uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text, uuid
) to authenticated;
