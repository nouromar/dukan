-- 0100_post_receive_client_id.sql
--
-- Offline VOID, part 4 of 4 (receive). Same change as 0097/0098/0099 applied to
-- post_receive: an optional client-supplied txn id so an offline receive has a
-- stable UUID that survives sync and can be voided offline.
--
--   * New TAIL param `p_txn_id uuid default null`. The MAIN txn insert lists
--     `id = coalesce(p_txn_id, pg_catalog.gen_random_uuid())`.
--   * The cash-paid SETTLEMENT LEG payment (direction 'O') stays server-minted
--     with its `<op>:payment` client_op_id — do NOT reuse the client txn id.
--   * Lines, weighted-average re-cost, last_cost / supplier cost cache,
--     payable, idempotency: reproduced verbatim from 0010.
--
-- Drop the old 9-arg signature first.

drop function if exists public.post_receive(
  uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text
);

create or replace function public.post_receive(
  p_shop_id uuid,
  p_party_id uuid,
  p_lines jsonb,
  p_paid_amount numeric default 0,
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
  v_unit_cost numeric;                   -- per base unit (for stock_movement)
  v_entered_unit_cost numeric;           -- per packaging (input)
  v_unit_amount numeric;                 -- per packaging (line)
  v_line_total numeric;
  v_total numeric := 0;
  v_paid numeric := coalesce(p_paid_amount, 0);
  v_unpaid numeric;
  v_occurred_at timestamptz := coalesce(p_occurred_at, pg_catalog.now());
  v_old_stock numeric;
  v_old_avg_cost numeric;
  v_new_stock numeric;
  v_new_avg_cost numeric;
  v_payment_method_id uuid;
  v_item_name text;
begin
  perform public._require_ready_shop(p_shop_id);
  perform public._assert_document_in_shop(p_shop_id, p_document_id);
  perform public._assert_party_kind(p_shop_id, p_party_id, 'supplier');

  if p_client_op_id is not null then
    select id into v_existing_id
    from public.txn
    where shop_id = p_shop_id and client_op_id = p_client_op_id;

    if v_existing_id is not null then
      return v_existing_id;
    end if;
  end if;

  if v_paid < 0 then
    raise exception 'Paid amount cannot be negative';
  end if;

  if p_lines is null
    or pg_catalog.jsonb_typeof(p_lines) <> 'array'
    or pg_catalog.jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one receive line is required';
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
    payment_method_id,
    document_id,
    client_op_id,
    notes,
    created_by
  )
  values (
    coalesce(p_txn_id, pg_catalog.gen_random_uuid()),
    p_shop_id,
    public._ref_id('transaction_type', 'receive'),
    public._ref_id('transaction_status', 'posted'),
    p_party_id,
    v_occurred_at,
    pg_catalog.now(),
    0,
    0,
    null,
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
    v_entered_unit_cost := nullif(v_line->>'unit_cost', '')::numeric;
    v_line_total := nullif(v_line->>'line_total', '')::numeric;

    if v_shop_item_unit_id is null or v_quantity is null then
      raise exception 'Receive line % is missing shop_item_unit_id or quantity', v_line_no;
    end if;

    if v_quantity <= 0 then
      raise exception 'Receive line % quantity must be greater than zero', v_line_no;
    end if;

    if (v_entered_unit_cost is null and v_line_total is null)
      or (v_entered_unit_cost is not null and v_line_total is not null) then
      raise exception 'Receive line % must provide either unit_cost or line_total', v_line_no;
    end if;

    if v_entered_unit_cost is not null and v_entered_unit_cost < 0 then
      raise exception 'Receive line % unit cost cannot be negative', v_line_no;
    end if;

    if v_line_total is not null and v_line_total < 0 then
      raise exception 'Receive line % total cannot be negative', v_line_no;
    end if;

    -- Resolve packaging → shop_item + structural snapshot.
    select siu.shop_item_id, siu.unit_code, siu.conversion_to_base
    into v_shop_item_id, v_unit_code, v_conversion
    from public.shop_item_unit siu
    where siu.shop_id = p_shop_id
      and siu.id = v_shop_item_unit_id
      and siu.is_active;

    if v_shop_item_id is null then
      raise exception 'Receive line % packaging does not belong to this shop or is inactive', v_line_no;
    end if;

    -- Resolve unit.id from unit_code for the FK on transaction_line.
    select id into v_unit_id from public.unit where code = v_unit_code;
    if v_unit_id is null then
      raise exception 'Receive line % unit % is not in the global unit table', v_line_no, v_unit_code;
    end if;

    -- Lock the shop_item row before reading current_stock / avg_cost.
    select current_stock, avg_cost
    into v_old_stock, v_old_avg_cost
    from public.shop_item si
    where si.shop_id = p_shop_id
      and si.id = v_shop_item_id
      and si.is_active
    for update;

    if v_old_stock is null then
      raise exception 'Receive line % shop_item is inactive or missing', v_line_no;
    end if;

    -- Resolve display name for the snapshot. Prefer shop-level display
    -- alias, then global. Empty string is acceptable when no alias yet.
    v_item_name := public._resolve_item_name_snapshot(p_shop_id, v_shop_item_id);

    v_base_quantity := v_quantity * v_conversion;

    -- Derive money fields. Per-base-unit cost is what stock_movement
    -- carries; per-packaging unit_amount is what transaction_line stores.
    if v_line_total is null then
      v_line_total := pg_catalog.round(v_quantity * v_entered_unit_cost, 2);
    end if;

    if v_line_total = 0 then
      v_unit_cost := 0;
    else
      v_unit_cost := pg_catalog.round(v_line_total / v_base_quantity, 4);
    end if;

    if v_entered_unit_cost is null then
      v_entered_unit_cost := pg_catalog.round(v_line_total / v_quantity, 4);
    end if;
    v_unit_amount := v_entered_unit_cost;

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
      line_total
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
      v_unit_amount,
      v_item_name,
      v_unit_code,
      v_conversion,
      v_line_total
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
      v_base_quantity,
      v_unit_cost,
      v_occurred_at
    );

    -- Weighted-average re-cost. Sales never change avg_cost; only
    -- receives + adjustments do.
    v_new_stock := v_old_stock + v_base_quantity;
    if v_old_stock <= 0 then
      v_new_avg_cost := v_unit_cost;
    else
      v_new_avg_cost := pg_catalog.round(((v_old_stock * v_old_avg_cost) + v_line_total) / v_new_stock, 4);
    end if;

    update public.shop_item
    set current_stock = v_new_stock,
        avg_cost = v_new_avg_cost
    where shop_id = p_shop_id and id = v_shop_item_id;

    -- last_cost lives on the packaging now (per-packaging, not per-item).
    update public.shop_item_unit
    set last_cost = v_unit_amount
    where shop_id = p_shop_id and id = v_shop_item_unit_id;

    -- Per-supplier per-packaging cost cache. Keyed on
    -- (shop_id, party_id, shop_item_unit_id); upsert on every receive line.
    insert into public.supplier_item_unit_cost (
      shop_id, party_id, shop_item_unit_id, last_unit_cost, last_received_at
    )
    values (
      p_shop_id, p_party_id, v_shop_item_unit_id, v_unit_amount, v_occurred_at
    )
    on conflict (shop_id, party_id, shop_item_unit_id)
    do update set
      last_unit_cost   = excluded.last_unit_cost,
      last_received_at = excluded.last_received_at;

    v_total := v_total + v_line_total;
  end loop;

  if v_paid > v_total then
    raise exception 'Paid amount cannot exceed receive total';
  end if;

  v_unpaid := v_total - v_paid;

  if v_paid > 0 then
    v_payment_method_id := public._payment_method_id(p_payment_method_code);
  end if;

  update public.txn
  set total_amount = v_total,
      paid_amount = v_paid,
      payment_method_id = case when v_paid > 0 then v_payment_method_id else null end
  where shop_id = p_shop_id and id = v_txn_id;

  update public.party
  set payable = payable + v_unpaid
  where shop_id = p_shop_id and id = p_party_id;

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
      'O',
      v_paid,
      v_payment_method_id,
      v_occurred_at,
      p_document_id,
      case when p_client_op_id is null then null else p_client_op_id || ':payment' end,
      p_notes,
      auth.uid()
    )
    returning id into v_payment_id;

    insert into public.payment_allocation (shop_id, payment_id, transaction_id, amount)
    values (p_shop_id, v_payment_id, v_txn_id, v_paid);
  end if;

  perform public._audit_log(
    p_shop_id      => p_shop_id,
    p_action_code  => 'receive.post',
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

revoke all on function public.post_receive(
  uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text, uuid
) from public;
grant execute on function public.post_receive(
  uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text, uuid
) to authenticated;
