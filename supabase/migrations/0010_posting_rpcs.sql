-- Posting RPCs (v2 schema).
--
-- These are the ONLY sanctioned writers for transaction / payment /
-- stock_movement and for the cached projections:
--     shop_item.current_stock
--     shop_item.avg_cost
--     shop_item_unit.last_cost
--     shop_item_unit.sale_price        (cashier price override only)
--     supplier_item_unit_cost          (upsert per receive line)
--
-- All RPCs are SECURITY DEFINER and gated by auth_can_post_shop().
-- Idempotent on client_op_id (unique partial indexes live in 0009).
-- Negative stock is ALLOWED (locked decision in data-model-v2 §3): the
-- RPC raises a NOTICE and lets the client surface a toast.
--
-- Line payload shape (v2):
--   Sale:    { shop_item_unit_id, quantity, unit_price }
--   Receive: { shop_item_unit_id, quantity, line_total | unit_cost }
-- The server resolves shop_item_id, base_unit_code, conversion_to_base
-- from shop_item_unit; clients never pass them.

create or replace function public.auth_can_post_shop(p_shop_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select
    public.auth_has_shop_role(p_shop_id, 'owner')
    or public.auth_has_shop_role(p_shop_id, 'cashier');
$$;

create or replace function public._ref_id(p_table text, p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  case p_table
    when 'transaction_type' then
      select id into v_id from public.transaction_type where code = p_code and is_active;
    when 'transaction_status' then
      select id into v_id from public.transaction_status where code = p_code and is_active;
    when 'payment_method' then
      select id into v_id from public.payment_method where code = p_code and is_active;
    when 'adjustment_reason' then
      select id into v_id from public.adjustment_reason where code = p_code and is_active;
    else
      raise exception 'Unsupported reference table: %', p_table;
  end case;

  if v_id is null then
    raise exception 'Reference %:% is not available', p_table, p_code;
  end if;

  return v_id;
end;
$$;

create or replace function public._require_ready_shop(p_shop_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_setup_status text;
begin
  if not public.auth_can_post_shop(p_shop_id) then
    raise exception 'Not allowed to post for this shop';
  end if;

  select setup_status into v_setup_status
  from public.shop
  where id = p_shop_id;

  if v_setup_status is null then
    raise exception 'Shop does not exist';
  end if;

  if v_setup_status <> 'ready' then
    raise exception 'Shop setup must be ready before posting';
  end if;
end;
$$;

create or replace function public._assert_document_in_shop(
  p_shop_id uuid,
  p_document_id uuid
)
returns void
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
  if p_document_id is not null and not exists (
    select 1 from public.document where shop_id = p_shop_id and id = p_document_id
  ) then
    raise exception 'Document does not belong to this shop';
  end if;
end;
$$;

create or replace function public._assert_party_kind(
  p_shop_id uuid,
  p_party_id uuid,
  p_expected_kind text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type_code text;
begin
  select pt.code into v_type_code
  from public.party p
  join public.party_type pt on pt.id = p.type_id
  where p.shop_id = p_shop_id
    and p.id = p_party_id
    and p.is_active
  for update of p;

  if v_type_code is null then
    raise exception 'Party does not belong to this shop or is inactive';
  end if;

  if p_expected_kind = 'supplier' and v_type_code not in ('supplier', 'both') then
    raise exception 'Party must be a supplier';
  end if;

  if p_expected_kind = 'customer' and v_type_code not in ('customer', 'both') then
    raise exception 'Party must be a customer';
  end if;
end;
$$;

create or replace function public._payment_method_id(p_payment_method_code text)
returns uuid
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
  if p_payment_method_code is null or length(btrim(p_payment_method_code)) = 0 then
    raise exception 'Payment method is required when an amount is paid';
  end if;

  return public._ref_id('payment_method', p_payment_method_code);
end;
$$;

create or replace function public._resolve_item_name_snapshot(
  p_shop_id uuid,
  p_shop_item_id uuid
)
returns text
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_name text;
  v_global_item_id uuid;
begin
  -- 1) Shop-level display alias.
  select alias_text into v_name
  from public.shop_item_alias
  where shop_id = p_shop_id
    and shop_item_id = p_shop_item_id
    and is_display
    and is_active
  order by language_code nulls last
  limit 1;
  if v_name is not null then
    return v_name;
  end if;

  -- 2) Global display alias via shop_item.item_id (when activated).
  select item_id into v_global_item_id
  from public.shop_item
  where shop_id = p_shop_id and id = p_shop_item_id;

  if v_global_item_id is not null then
    select alias_text into v_name
    from public.item_alias
    where item_id = v_global_item_id
      and is_display
      and is_active
    order by language_code nulls last
    limit 1;
    if v_name is not null then
      return v_name;
    end if;
  end if;

  -- 3) Any active shop alias.
  select alias_text into v_name
  from public.shop_item_alias
  where shop_id = p_shop_id
    and shop_item_id = p_shop_item_id
    and is_active
  order by weight desc, created_at asc
  limit 1;
  if v_name is not null then
    return v_name;
  end if;

  -- 4) Any active global alias.
  if v_global_item_id is not null then
    select alias_text into v_name
    from public.item_alias
    where item_id = v_global_item_id
      and is_active
    order by weight desc, created_at asc
    limit 1;
    if v_name is not null then
      return v_name;
    end if;
  end if;

  -- Fallback: a CHECK on transaction_line requires NOT NULL on the
  -- item_name_snapshot column, so return a non-null placeholder.
  return '(unnamed)';
end;
$$;

-- ---------------------------------------------------------------------------
-- post_receive
-- ---------------------------------------------------------------------------
-- Contract:
--   Line payload: { shop_item_unit_id, quantity, line_total | unit_cost }.
--   Server resolves shop_item + base_unit + conversion from shop_item_unit.
--   Writes: txn, transaction_line, stock_movement, optional payment +
--   payment_allocation. Updates shop_item.current_stock + avg_cost,
--   shop_item_unit.last_cost, supplier_item_unit_cost.

create or replace function public.post_receive(
  p_shop_id uuid,
  p_party_id uuid,
  p_lines jsonb,
  p_paid_amount numeric default 0,
  p_payment_method_code text default null,
  p_document_id uuid default null,
  p_client_op_id text default null,
  p_occurred_at timestamptz default null,
  p_notes text default null
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

-- ---------------------------------------------------------------------------
-- post_sale
-- ---------------------------------------------------------------------------
-- Contract:
--   Line payload: { shop_item_unit_id, quantity, unit_price }.
--   Server resolves shop_item from packaging, snapshots cogs_unit_cost
--   from shop_item.avg_cost, decrements current_stock. If unit_price
--   differs from shop_item_unit.sale_price, persists the override.
--   Negative stock allowed: RAISE NOTICE, do not block.

create or replace function public.post_sale(
  p_shop_id uuid,
  p_party_id uuid default null,
  p_lines jsonb default null,
  p_paid_amount numeric default null,
  p_payment_method_code text default null,
  p_document_id uuid default null,
  p_client_op_id text default null,
  p_occurred_at timestamptz default null,
  p_notes text default null
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

-- ---------------------------------------------------------------------------
-- post_expense
-- ---------------------------------------------------------------------------
-- Contract: single-line money-out transaction with no item / packaging
-- legs. transaction_line carries expense_category_id only (CHECK in 0009
-- enforces item_id + shop_item_unit_id are null on this shape).

create or replace function public.post_expense(
  p_shop_id uuid,
  p_expense_category_id uuid,
  p_amount numeric,
  p_payment_method_code text default null,
  p_document_id uuid default null,
  p_client_op_id text default null,
  p_occurred_at timestamptz default null,
  p_notes text default null
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

-- ---------------------------------------------------------------------------
-- post_payment
-- ---------------------------------------------------------------------------
-- Contract: standalone party payment, in either direction. Decrements
-- receivable (inbound) or payable (outbound). Idempotent on client_op_id.

create or replace function public.post_payment(
  p_shop_id uuid,
  p_party_id uuid,
  p_direction char,
  p_amount numeric,
  p_payment_method_code text,
  p_client_op_id text default null,
  p_document_id uuid default null,
  p_occurred_at timestamptz default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_id uuid;
  v_payment_id uuid;
  v_method_id uuid;
  v_party_type text;
  v_receivable numeric;
  v_payable numeric;
  v_occurred_at timestamptz := coalesce(p_occurred_at, pg_catalog.now());
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
    p_direction,
    p_amount,
    v_method_id,
    v_occurred_at,
    p_document_id,
    p_client_op_id,
    p_notes,
    auth.uid()
  )
  returning id into v_payment_id;

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

-- ---------------------------------------------------------------------------
-- post_inventory_adjustment
-- ---------------------------------------------------------------------------
-- Contract: owner-only stock correction. Lines key on shop_item_id (the
-- adjustment level is the item, not a specific packaging). Writes
-- inventory_adjustment + inventory_adjustment_line + stock_movement and
-- updates shop_item.current_stock + avg_cost.

create or replace function public.post_inventory_adjustment(
  p_shop_id uuid,
  p_reason_code text,
  p_lines jsonb,
  p_document_id uuid default null,
  p_client_op_id text default null,
  p_occurred_at timestamptz default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_id uuid;
  v_adjustment_id uuid;
  v_adjustment_line_id uuid;
  v_line jsonb;
  v_line_no integer := 0;
  v_shop_item_id uuid;
  v_quantity_delta numeric;
  v_unit_cost numeric;
  v_old_stock numeric;
  v_old_avg_cost numeric;
  v_new_stock numeric;
  v_new_avg_cost numeric;
  v_reason_id uuid;
  v_reason_is_increase boolean;
  v_status_id uuid;
  v_setup_status text;
  v_occurred_at timestamptz := coalesce(p_occurred_at, pg_catalog.now());
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only a shop owner can post inventory adjustments';
  end if;

  perform public._assert_document_in_shop(p_shop_id, p_document_id);

  select setup_status into v_setup_status
  from public.shop
  where id = p_shop_id
  for update;

  if v_setup_status is null then
    raise exception 'Shop does not exist';
  end if;

  if p_reason_code = 'opening' then
    if v_setup_status not in ('template_applied', 'opening_stock_done') then
      raise exception 'Opening stock can only be posted during setup';
    end if;
  elsif v_setup_status <> 'ready' then
    raise exception 'Shop setup must be ready before posting adjustments';
  end if;

  if p_client_op_id is not null then
    select id into v_existing_id
    from public.inventory_adjustment
    where shop_id = p_shop_id and client_op_id = p_client_op_id;

    if v_existing_id is not null then
      return v_existing_id;
    end if;
  end if;

  select id, is_increase
  into v_reason_id, v_reason_is_increase
  from public.adjustment_reason
  where code = p_reason_code and is_active;

  if v_reason_id is null then
    raise exception 'Adjustment reason is not available';
  end if;

  if p_lines is null
    or pg_catalog.jsonb_typeof(p_lines) <> 'array'
    or pg_catalog.jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one adjustment line is required';
  end if;

  v_status_id := public._ref_id('transaction_status', 'posted');

  insert into public.inventory_adjustment (
    shop_id,
    reason_id,
    status_id,
    occurred_at,
    posted_at,
    document_id,
    client_op_id,
    notes,
    approved_by,
    created_by
  )
  values (
    p_shop_id,
    v_reason_id,
    v_status_id,
    v_occurred_at,
    pg_catalog.now(),
    p_document_id,
    p_client_op_id,
    p_notes,
    auth.uid(),
    auth.uid()
  )
  returning id into v_adjustment_id;

  for v_line in select value from pg_catalog.jsonb_array_elements(p_lines) as t(value)
  loop
    v_line_no := v_line_no + 1;
    -- Accept either `shop_item_id` (v2 idiomatic) or legacy `item_id`.
    v_shop_item_id := coalesce(
      nullif(v_line->>'shop_item_id', '')::uuid,
      nullif(v_line->>'item_id', '')::uuid
    );
    v_quantity_delta := nullif(v_line->>'quantity_delta', '')::numeric;
    v_unit_cost := nullif(v_line->>'unit_cost', '')::numeric;

    if v_shop_item_id is null or v_quantity_delta is null then
      raise exception 'Adjustment line % is missing shop_item_id or quantity_delta', v_line_no;
    end if;

    if v_quantity_delta = 0 then
      raise exception 'Adjustment line % quantity_delta cannot be zero', v_line_no;
    end if;

    if v_reason_is_increase is true and v_quantity_delta <= 0 then
      raise exception 'Adjustment line % must increase stock for this reason', v_line_no;
    end if;

    if v_reason_is_increase is false and v_quantity_delta >= 0 then
      raise exception 'Adjustment line % must decrease stock for this reason', v_line_no;
    end if;

    if v_unit_cost is not null and v_unit_cost < 0 then
      raise exception 'Adjustment line % unit_cost cannot be negative', v_line_no;
    end if;

    select current_stock, avg_cost
    into v_old_stock, v_old_avg_cost
    from public.shop_item
    where shop_id = p_shop_id
      and id = v_shop_item_id
      and is_active
    for update;

    if v_old_stock is null then
      raise exception 'Adjustment line % shop_item is inactive or missing', v_line_no;
    end if;

    if v_quantity_delta < 0 then
      v_unit_cost := coalesce(v_unit_cost, v_old_avg_cost);
    else
      if v_unit_cost is null then
        raise exception 'Adjustment line % requires unit_cost for stock increases', v_line_no;
      end if;
    end if;

    insert into public.inventory_adjustment_line (
      shop_id,
      adjustment_id,
      item_id,
      quantity_delta,
      unit_cost
    )
    values (
      p_shop_id,
      v_adjustment_id,
      v_shop_item_id,
      v_quantity_delta,
      v_unit_cost
    )
    returning id into v_adjustment_line_id;

    insert into public.stock_movement (
      shop_id,
      item_id,
      inventory_adjustment_line_id,
      quantity_delta,
      unit_cost,
      occurred_at
    )
    values (
      p_shop_id,
      v_shop_item_id,
      v_adjustment_line_id,
      v_quantity_delta,
      v_unit_cost,
      v_occurred_at
    );

    v_new_stock := v_old_stock + v_quantity_delta;
    v_new_avg_cost := v_old_avg_cost;

    if v_quantity_delta > 0 then
      if v_old_stock <= 0 then
        v_new_avg_cost := v_unit_cost;
      else
        v_new_avg_cost := pg_catalog.round(((v_old_stock * v_old_avg_cost) + (v_quantity_delta * v_unit_cost)) / v_new_stock, 4);
      end if;
    end if;

    update public.shop_item
    set current_stock = v_new_stock,
        avg_cost = v_new_avg_cost
    where shop_id = p_shop_id and id = v_shop_item_id;
  end loop;

  if p_reason_code = 'opening' then
    update public.shop
    set setup_status = 'opening_stock_done'
    where id = p_shop_id
      and setup_status = 'template_applied';
  end if;

  return v_adjustment_id;
exception
  when unique_violation then
    if p_client_op_id is not null then
      select id into v_existing_id
      from public.inventory_adjustment
      where shop_id = p_shop_id and client_op_id = p_client_op_id;

      if v_existing_id is not null then
        return v_existing_id;
      end if;
    end if;
    raise;
end;
$$;

-- ---------------------------------------------------------------------------
-- complete_shop_setup
-- ---------------------------------------------------------------------------

create or replace function public.complete_shop_setup(p_shop_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_setup_status text;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only a shop owner can complete setup';
  end if;

  select setup_status into v_setup_status
  from public.shop
  where id = p_shop_id
  for update;

  if v_setup_status is null then
    raise exception 'Shop does not exist';
  end if;

  if v_setup_status not in ('template_applied', 'opening_stock_done') then
    raise exception 'Shop setup cannot be completed from status %', v_setup_status;
  end if;

  update public.shop
  set setup_status = 'ready',
      setup_completed_at = pg_catalog.now()
  where id = p_shop_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- dismiss_shop_onboarding
-- ---------------------------------------------------------------------------
-- Sets shop.onboarding_dismissed_at on the first dismiss; idempotent
-- (subsequent calls leave the original timestamp). The optional
-- item-onboarding step (data-model-v2 §11.10 T#154) appears once and
-- never again after this RPC succeeds. Setup-manager-only.

create or replace function public.dismiss_shop_onboarding(p_shop_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.auth_can_manage_shop_setup(p_shop_id) then
    raise exception 'Not allowed to dismiss onboarding for this shop';
  end if;

  update public.shop
  set onboarding_dismissed_at = coalesce(onboarding_dismissed_at, pg_catalog.now())
  where id = p_shop_id;
end;
$$;

revoke all on function public.dismiss_shop_onboarding(uuid) from public;
grant execute on function public.dismiss_shop_onboarding(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- void_sale
-- ---------------------------------------------------------------------------
-- Contract: owner-only, 7-day window. Writes a reversing txn with
-- mirrored lines that copy shop_item_unit_id + original cogs snapshot.
-- Restores stock and reverses receivable. Optional refund records an
-- outbound payment linked via payment.refund_of_transaction_id.
-- Idempotent on client_op_id.

create or replace function public.void_sale(
  p_shop_id uuid,
  p_txn_id uuid,
  p_client_op_id text default null,
  p_refund_amount numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_replay uuid;
  v_existing_reversal_id uuid;
  v_original_type_code text;
  v_original_posted_at timestamptz;
  v_original_party_id uuid;
  v_original_party_type text;
  v_original_total numeric;
  v_original_paid numeric;
  v_original_payment_method_id uuid;
  v_unpaid numeric;
  v_party_receivable numeric;
  v_reversal_txn_id uuid;
  v_sale_type_id uuid;
  v_posted_status_id uuid;
  v_now timestamptz := pg_catalog.now();
  v_void_window interval := interval '7 days';
  r record;
  v_new_line_id uuid;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only the shop owner can void a sale';
  end if;

  if p_client_op_id is not null then
    select id into v_existing_replay
    from public.txn
    where shop_id = p_shop_id and client_op_id = p_client_op_id;
    if v_existing_replay is not null then
      return v_existing_replay;
    end if;
  end if;

  select tt.code, t.posted_at, t.party_id, t.total_amount,
         t.paid_amount, t.payment_method_id
  into v_original_type_code, v_original_posted_at,
       v_original_party_id, v_original_total, v_original_paid,
       v_original_payment_method_id
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  where t.shop_id = p_shop_id
    and t.id = p_txn_id
    and t.reverses_transaction_id is null
  for update of t;

  if v_original_type_code is null then
    raise exception 'Sale not found (or it is itself a reversal)';
  end if;
  if v_original_type_code <> 'sale' then
    raise exception 'void_sale only voids sale transactions';
  end if;
  if v_original_posted_at is null then
    raise exception 'Sale has no posted_at — cannot void';
  end if;
  if v_original_posted_at < v_now - v_void_window then
    raise exception 'Sale is outside the % void window', v_void_window;
  end if;

  select id into v_existing_reversal_id
  from public.txn
  where shop_id = p_shop_id and reverses_transaction_id = p_txn_id;
  if v_existing_reversal_id is not null then
    raise exception 'Sale was already voided';
  end if;

  -- Validate refund before any state change.
  if p_refund_amount is not null then
    if p_refund_amount <= 0 then
      raise exception 'Refund amount must be greater than zero';
    end if;
    if v_original_party_id is null then
      raise exception 'Refund requires a customer party on the sale';
    end if;
    if p_refund_amount > v_original_paid then
      raise exception
        'Refund (%) cannot exceed cash paid at the till (%)',
        p_refund_amount, v_original_paid;
    end if;
    select pt.code into v_original_party_type
    from public.party p
    join public.party_type pt on pt.id = p.type_id
    where p.shop_id = p_shop_id and p.id = v_original_party_id;
    if v_original_party_type not in ('customer', 'both') then
      raise exception 'Refund target party is not a customer';
    end if;
  end if;

  -- Partial-paid receivable guard.
  v_unpaid := v_original_total - v_original_paid;
  if v_unpaid > 0 and v_original_party_id is not null then
    select receivable into v_party_receivable
    from public.party
    where shop_id = p_shop_id and id = v_original_party_id
    for update;
    if v_party_receivable < v_unpaid then
      raise exception
        'Customer has paid down some of this sale; void blocked. '
        'Record a refund payment instead.';
    end if;
  end if;

  v_sale_type_id := public._ref_id('transaction_type', 'sale');
  v_posted_status_id := public._ref_id('transaction_status', 'posted');

  insert into public.txn (
    shop_id, type_id, status_id, party_id, occurred_at, posted_at,
    total_amount, paid_amount, payment_method_id,
    reverses_transaction_id, client_op_id, notes, created_by
  )
  values (
    p_shop_id, v_sale_type_id, v_posted_status_id, v_original_party_id,
    v_now, v_now,
    v_original_total, v_original_paid, v_original_payment_method_id,
    p_txn_id, p_client_op_id,
    'Reversal of ' || p_txn_id::text,
    auth.uid()
  )
  returning id into v_reversal_txn_id;

  -- Mirror each line. cogs snapshot carries over from the original so
  -- profit reports unwind the same value they originally booked.
  for r in
    select tl.id as original_line_id, tl.line_no, tl.item_id, tl.shop_item_unit_id,
           tl.quantity, tl.unit_id, tl.base_quantity, tl.unit_amount,
           tl.item_name_snapshot, tl.unit_code_snapshot,
           tl.unit_conversion_to_base_snapshot, tl.line_total,
           tl.cogs_unit_cost, tl.cogs_total
    from public.transaction_line tl
    where tl.shop_id = p_shop_id and tl.transaction_id = p_txn_id
    order by tl.line_no
  loop
    insert into public.transaction_line (
      shop_id, transaction_id, line_no, item_id, shop_item_unit_id,
      quantity, unit_id, base_quantity, unit_amount,
      item_name_snapshot, unit_code_snapshot,
      unit_conversion_to_base_snapshot, line_total,
      cogs_unit_cost, cogs_total
    )
    values (
      p_shop_id, v_reversal_txn_id, r.line_no, r.item_id, r.shop_item_unit_id,
      r.quantity, r.unit_id, r.base_quantity, r.unit_amount,
      r.item_name_snapshot, r.unit_code_snapshot,
      r.unit_conversion_to_base_snapshot, r.line_total,
      r.cogs_unit_cost, r.cogs_total
    )
    returning id into v_new_line_id;

    -- Original sale movement was -base_quantity at cogs_unit_cost; the
    -- reversal puts the stock back in at the same cost basis.
    insert into public.stock_movement (
      shop_id, item_id, transaction_line_id, quantity_delta,
      unit_cost, occurred_at
    )
    values (
      p_shop_id, r.item_id, v_new_line_id, r.base_quantity,
      r.cogs_unit_cost, v_now
    );

    update public.shop_item
    set current_stock = current_stock + r.base_quantity
    where shop_id = p_shop_id and id = r.item_id;
  end loop;

  if v_unpaid > 0 and v_original_party_id is not null then
    update public.party
    set receivable = receivable - v_unpaid
    where shop_id = p_shop_id and id = v_original_party_id;
  end if;

  if p_refund_amount is not null then
    insert into public.payment (
      shop_id, party_id, direction, amount, method_id,
      occurred_at, refund_of_transaction_id, notes, created_by
    )
    values (
      p_shop_id, v_original_party_id, 'O', p_refund_amount,
      v_original_payment_method_id, v_now, p_txn_id,
      'Refund of voided sale ' || p_txn_id::text,
      auth.uid()
    );
  end if;

  return v_reversal_txn_id;
exception
  when unique_violation then
    if p_client_op_id is not null then
      select id into v_existing_replay
      from public.txn
      where shop_id = p_shop_id and client_op_id = p_client_op_id;
      if v_existing_replay is not null then
        return v_existing_replay;
      end if;
    end if;
    raise;
end;
$$;

-- ---------------------------------------------------------------------------
-- void_receive
-- ---------------------------------------------------------------------------
-- Contract: owner-only, 24-hour window. Refuses if any later stock
-- movement happened on any item from this receive (the cashier reaches
-- for a manual correction instead). Reversal lines mirror packaging
-- (shop_item_unit_id) so receipt re-renders stay accurate.

create or replace function public.void_receive(
  p_shop_id uuid,
  p_txn_id uuid,
  p_client_op_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_replay uuid;
  v_existing_reversal_id uuid;
  v_original_type_code text;
  v_original_posted_at timestamptz;
  v_original_party_id uuid;
  v_original_total numeric;
  v_original_paid numeric;
  v_original_payment_method_id uuid;
  v_unpaid numeric;
  v_party_payable numeric;
  v_reversal_txn_id uuid;
  v_receive_type_id uuid;
  v_posted_status_id uuid;
  v_now timestamptz := pg_catalog.now();
  v_void_window interval := interval '24 hours';
  r record;
  v_new_line_id uuid;
  v_existing_movement_unit_cost numeric;
begin
  if not public.auth_has_shop_role(p_shop_id, 'owner') then
    raise exception 'Only the shop owner can void a receive';
  end if;

  if p_client_op_id is not null then
    select id into v_existing_replay
    from public.txn
    where shop_id = p_shop_id and client_op_id = p_client_op_id;
    if v_existing_replay is not null then
      return v_existing_replay;
    end if;
  end if;

  select tt.code, t.posted_at, t.party_id, t.total_amount,
         t.paid_amount, t.payment_method_id
  into v_original_type_code, v_original_posted_at,
       v_original_party_id, v_original_total, v_original_paid,
       v_original_payment_method_id
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  where t.shop_id = p_shop_id
    and t.id = p_txn_id
    and t.reverses_transaction_id is null
  for update of t;

  if v_original_type_code is null then
    raise exception 'Receive not found (or it is itself a reversal)';
  end if;
  if v_original_type_code <> 'receive' then
    raise exception 'void_receive only voids receive transactions';
  end if;
  if v_original_posted_at is null then
    raise exception 'Receive has no posted_at — cannot void';
  end if;
  if v_original_posted_at < v_now - v_void_window then
    raise exception
      'Receive is outside the same-shift void window (%). Use a return instead.',
      v_void_window;
  end if;

  select id into v_existing_reversal_id
  from public.txn
  where shop_id = p_shop_id and reverses_transaction_id = p_txn_id;
  if v_existing_reversal_id is not null then
    raise exception 'Receive was already voided';
  end if;

  -- Block if any of the received items has had stock activity since
  -- this receive posted (sales, adjustments, other receives). The
  -- receive's own movements are excluded via the line-id filter; >=
  -- because rapid back-to-back ops can share a timestamp.
  if exists (
    select 1
    from public.stock_movement later
    where later.shop_id = p_shop_id
      and later.item_id in (
        select tl.item_id
        from public.transaction_line tl
        where tl.shop_id = p_shop_id and tl.transaction_id = p_txn_id
      )
      and later.occurred_at >= v_original_posted_at
      and (
        later.transaction_line_id is null
        or later.transaction_line_id not in (
          select tl.id
          from public.transaction_line tl
          where tl.shop_id = p_shop_id and tl.transaction_id = p_txn_id
        )
      )
  ) then
    raise exception
      'One or more items from this receive have had stock activity since. '
      'Void blocked.';
  end if;

  v_unpaid := v_original_total - v_original_paid;
  if v_unpaid > 0 and v_original_party_id is not null then
    select payable into v_party_payable
    from public.party
    where shop_id = p_shop_id and id = v_original_party_id
    for update;
    if v_party_payable < v_unpaid then
      raise exception
        'Shop has paid down some of this bono; void blocked. '
        'Record a refund payment from the supplier instead.';
    end if;
  end if;

  v_receive_type_id := public._ref_id('transaction_type', 'receive');
  v_posted_status_id := public._ref_id('transaction_status', 'posted');

  insert into public.txn (
    shop_id, type_id, status_id, party_id, occurred_at, posted_at,
    total_amount, paid_amount, payment_method_id,
    reverses_transaction_id, client_op_id, notes, created_by
  )
  values (
    p_shop_id, v_receive_type_id, v_posted_status_id, v_original_party_id,
    v_now, v_now,
    v_original_total, v_original_paid, v_original_payment_method_id,
    p_txn_id, p_client_op_id,
    'Reversal of receive ' || p_txn_id::text,
    auth.uid()
  )
  returning id into v_reversal_txn_id;

  for r in
    select tl.id as original_line_id, tl.line_no, tl.item_id, tl.shop_item_unit_id,
           tl.quantity, tl.unit_id, tl.base_quantity, tl.unit_amount,
           tl.item_name_snapshot, tl.unit_code_snapshot,
           tl.unit_conversion_to_base_snapshot, tl.line_total
    from public.transaction_line tl
    where tl.shop_id = p_shop_id and tl.transaction_id = p_txn_id
    order by tl.line_no
  loop
    insert into public.transaction_line (
      shop_id, transaction_id, line_no, item_id, shop_item_unit_id,
      quantity, unit_id, base_quantity, unit_amount,
      item_name_snapshot, unit_code_snapshot,
      unit_conversion_to_base_snapshot, line_total
    )
    values (
      p_shop_id, v_reversal_txn_id, r.line_no, r.item_id, r.shop_item_unit_id,
      r.quantity, r.unit_id, r.base_quantity, r.unit_amount,
      r.item_name_snapshot, r.unit_code_snapshot,
      r.unit_conversion_to_base_snapshot, r.line_total
    )
    returning id into v_new_line_id;

    select unit_cost into v_existing_movement_unit_cost
    from public.stock_movement
    where shop_id = p_shop_id and transaction_line_id = r.original_line_id
    limit 1;

    insert into public.stock_movement (
      shop_id, item_id, transaction_line_id, quantity_delta,
      unit_cost, occurred_at
    )
    values (
      p_shop_id, r.item_id, v_new_line_id, -r.base_quantity,
      v_existing_movement_unit_cost, v_now
    );

    update public.shop_item
    set current_stock = current_stock - r.base_quantity
    where shop_id = p_shop_id and id = r.item_id;
  end loop;

  if v_unpaid > 0 and v_original_party_id is not null then
    update public.party
    set payable = payable - v_unpaid
    where shop_id = p_shop_id and id = v_original_party_id;
  end if;

  return v_reversal_txn_id;
exception
  when unique_violation then
    if p_client_op_id is not null then
      select id into v_existing_replay
      from public.txn
      where shop_id = p_shop_id and client_op_id = p_client_op_id;
      if v_existing_replay is not null then
        return v_existing_replay;
      end if;
    end if;
    raise;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke all on function public.auth_can_post_shop(uuid) from public;
revoke all on function public._ref_id(text, text) from public;
revoke all on function public._require_ready_shop(uuid) from public;
revoke all on function public._assert_document_in_shop(uuid, uuid) from public;
revoke all on function public._assert_party_kind(uuid, uuid, text) from public;
revoke all on function public._payment_method_id(text) from public;
revoke all on function public._resolve_item_name_snapshot(uuid, uuid) from public;
revoke all on function public.post_receive(uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text) from public;
revoke all on function public.post_sale(uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text) from public;
revoke all on function public.post_expense(uuid, uuid, numeric, text, uuid, text, timestamptz, text) from public;
revoke all on function public.post_payment(uuid, uuid, char, numeric, text, text, uuid, timestamptz, text) from public;
revoke all on function public.post_inventory_adjustment(uuid, text, jsonb, uuid, text, timestamptz, text) from public;
revoke all on function public.complete_shop_setup(uuid) from public;
revoke all on function public.void_sale(uuid, uuid, text, numeric) from public;
revoke all on function public.void_receive(uuid, uuid, text) from public;

grant execute on function public.auth_can_post_shop(uuid) to authenticated;
grant execute on function public.post_receive(uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text) to authenticated;
grant execute on function public.post_sale(uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text) to authenticated;
grant execute on function public.post_expense(uuid, uuid, numeric, text, uuid, text, timestamptz, text) to authenticated;
grant execute on function public.post_payment(uuid, uuid, char, numeric, text, text, uuid, timestamptz, text) to authenticated;
grant execute on function public.post_inventory_adjustment(uuid, text, jsonb, uuid, text, timestamptz, text) to authenticated;
grant execute on function public.complete_shop_setup(uuid) to authenticated;
grant execute on function public.void_sale(uuid, uuid, text, numeric) to authenticated;
grant execute on function public.void_receive(uuid, uuid, text) to authenticated;
