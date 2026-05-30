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
  v_item_id uuid;
  v_unit_id uuid;
  v_line_id uuid;
  v_quantity numeric;
  v_base_quantity numeric;
  v_conversion numeric;
  v_unit_cost numeric;
  v_entered_unit_cost numeric;
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
  v_catalog_revision_id uuid;
  v_unit_code text;
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
    v_item_id := nullif(v_line->>'item_id', '')::uuid;
    v_unit_id := nullif(v_line->>'unit_id', '')::uuid;
    v_quantity := nullif(v_line->>'quantity', '')::numeric;
    v_entered_unit_cost := nullif(v_line->>'unit_cost', '')::numeric;
    v_line_total := nullif(v_line->>'line_total', '')::numeric;

    if v_item_id is null or v_unit_id is null or v_quantity is null then
      raise exception 'Receive line % is missing item, unit, or quantity', v_line_no;
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

    select current_stock, avg_cost, coalesce(name_override, name), catalog_revision_id
    into v_old_stock, v_old_avg_cost, v_item_name, v_catalog_revision_id
    from public.item
    where shop_id = p_shop_id
      and id = v_item_id
      and is_active
    for update;

    if v_old_stock is null then
      raise exception 'Receive line % item does not belong to this shop or is inactive', v_line_no;
    end if;

    select iu.conversion_to_base, u.code
    into v_conversion, v_unit_code
    from public.item_unit iu
    join public.unit u on u.id = iu.unit_id
    where iu.shop_id = p_shop_id
      and iu.item_id = v_item_id
      and iu.unit_id = v_unit_id
      and iu.allow_receive;

    if v_conversion is null then
      raise exception 'Receive line % unit is not valid for this item', v_line_no;
    end if;

    v_base_quantity := v_quantity * v_conversion;

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

    insert into public.transaction_line (
      shop_id,
      transaction_id,
      line_no,
      item_id,
      quantity,
      unit_id,
      base_quantity,
      unit_amount,
      item_name_snapshot,
      unit_code_snapshot,
      unit_conversion_to_base_snapshot,
      catalog_revision_id,
      line_total
    )
    values (
      p_shop_id,
      v_txn_id,
      v_line_no,
      v_item_id,
      v_quantity,
      v_unit_id,
      v_base_quantity,
      v_entered_unit_cost,
      v_item_name,
      v_unit_code,
      v_conversion,
      v_catalog_revision_id,
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
      v_item_id,
      v_line_id,
      v_base_quantity,
      v_unit_cost,
      v_occurred_at
    );

    v_new_stock := v_old_stock + v_base_quantity;
    if v_old_stock <= 0 then
      v_new_avg_cost := v_unit_cost;
    else
      v_new_avg_cost := pg_catalog.round(((v_old_stock * v_old_avg_cost) + v_line_total) / v_new_stock, 4);
    end if;

    update public.item
    set current_stock = v_new_stock,
        avg_cost = v_new_avg_cost,
        last_cost = v_unit_cost
    where shop_id = p_shop_id and id = v_item_id;

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
  v_item_id uuid;
  v_unit_id uuid;
  v_line_id uuid;
  v_quantity numeric;
  v_base_quantity numeric;
  v_conversion numeric;
  v_unit_price numeric;
  v_line_total numeric;
  v_total numeric := 0;
  v_paid numeric;
  v_unpaid numeric;
  v_occurred_at timestamptz := coalesce(p_occurred_at, pg_catalog.now());
  v_current_stock numeric;
  v_avg_cost numeric;
  v_sale_price numeric;
  v_negative_policy text;
  v_cogs_total numeric;
  v_payment_method_id uuid;
  v_item_name text;
  v_catalog_revision_id uuid;
  v_unit_code text;
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

  select coalesce(ss.value #>> '{}', 'warn')
  into v_negative_policy
  from public.shop_setting ss
  where ss.shop_id = p_shop_id and ss.key = 'negative_stock_policy';

  v_negative_policy := coalesce(v_negative_policy, 'warn');

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
    v_item_id := nullif(v_line->>'item_id', '')::uuid;
    v_unit_id := nullif(v_line->>'unit_id', '')::uuid;
    v_quantity := nullif(v_line->>'quantity', '')::numeric;
    v_unit_price := nullif(v_line->>'unit_price', '')::numeric;

    if v_item_id is null or v_unit_id is null or v_quantity is null then
      raise exception 'Sale line % is missing item, unit, or quantity', v_line_no;
    end if;

    if v_quantity <= 0 then
      raise exception 'Sale line % quantity must be greater than zero', v_line_no;
    end if;

    if v_unit_price is not null and v_unit_price < 0 then
      raise exception 'Sale line % unit price cannot be negative', v_line_no;
    end if;

    select current_stock, avg_cost, sale_price, coalesce(name_override, name), catalog_revision_id
    into v_current_stock, v_avg_cost, v_sale_price, v_item_name, v_catalog_revision_id
    from public.item
    where shop_id = p_shop_id
      and id = v_item_id
      and is_active
    for update;

    if v_current_stock is null then
      raise exception 'Sale line % item does not belong to this shop or is inactive', v_line_no;
    end if;

    if v_unit_price is null then
      v_unit_price := v_sale_price;
    end if;

    if v_unit_price is null then
      raise exception 'Sale line % requires a unit price', v_line_no;
    end if;

    select iu.conversion_to_base, u.code
    into v_conversion, v_unit_code
    from public.item_unit iu
    join public.unit u on u.id = iu.unit_id
    where iu.shop_id = p_shop_id
      and iu.item_id = v_item_id
      and iu.unit_id = v_unit_id
      and iu.allow_sale;

    if v_conversion is null then
      raise exception 'Sale line % unit is not valid for this item', v_line_no;
    end if;

    v_base_quantity := v_quantity * v_conversion;

    if v_negative_policy = 'block' and (v_current_stock - v_base_quantity) < 0 then
      raise exception 'Sale line % would make stock negative', v_line_no;
    end if;

    v_line_total := pg_catalog.round(v_quantity * v_unit_price, 2);
    v_cogs_total := pg_catalog.round(v_base_quantity * v_avg_cost, 2);

    insert into public.transaction_line (
      shop_id,
      transaction_id,
      line_no,
      item_id,
      quantity,
      unit_id,
      base_quantity,
      unit_amount,
      item_name_snapshot,
      unit_code_snapshot,
      unit_conversion_to_base_snapshot,
      catalog_revision_id,
      line_total,
      cogs_unit_cost,
      cogs_total
    )
    values (
      p_shop_id,
      v_txn_id,
      v_line_no,
      v_item_id,
      v_quantity,
      v_unit_id,
      v_base_quantity,
      v_unit_price,
      v_item_name,
      v_unit_code,
      v_conversion,
      v_catalog_revision_id,
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
      v_item_id,
      v_line_id,
      -v_base_quantity,
      v_avg_cost,
      v_occurred_at
    );

    update public.item
    set current_stock = current_stock - v_base_quantity
    where shop_id = p_shop_id and id = v_item_id;

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
  v_item_id uuid;
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
    v_item_id := nullif(v_line->>'item_id', '')::uuid;
    v_quantity_delta := nullif(v_line->>'quantity_delta', '')::numeric;
    v_unit_cost := nullif(v_line->>'unit_cost', '')::numeric;

    if v_item_id is null or v_quantity_delta is null then
      raise exception 'Adjustment line % is missing item or quantity_delta', v_line_no;
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
    from public.item
    where shop_id = p_shop_id
      and id = v_item_id
      and is_active
    for update;

    if v_old_stock is null then
      raise exception 'Adjustment line % item does not belong to this shop or is inactive', v_line_no;
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
      v_item_id,
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
      v_item_id,
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

    update public.item
    set current_stock = v_new_stock,
        avg_cost = v_new_avg_cost,
        last_cost = case when v_quantity_delta > 0 then v_unit_cost else last_cost end
    where shop_id = p_shop_id and id = v_item_id;
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

revoke all on function public.auth_can_post_shop(uuid) from public;
revoke all on function public._ref_id(text, text) from public;
revoke all on function public._require_ready_shop(uuid) from public;
revoke all on function public._assert_document_in_shop(uuid, uuid) from public;
revoke all on function public._assert_party_kind(uuid, uuid, text) from public;
revoke all on function public._payment_method_id(text) from public;
revoke all on function public.post_receive(uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text) from public;
revoke all on function public.post_sale(uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text) from public;
revoke all on function public.post_expense(uuid, uuid, numeric, text, uuid, text, timestamptz, text) from public;
revoke all on function public.post_payment(uuid, uuid, char, numeric, text, text, uuid, timestamptz, text) from public;
revoke all on function public.post_inventory_adjustment(uuid, text, jsonb, uuid, text, timestamptz, text) from public;
revoke all on function public.complete_shop_setup(uuid) from public;

grant execute on function public.auth_can_post_shop(uuid) to authenticated;
grant execute on function public.post_receive(uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text) to authenticated;
grant execute on function public.post_sale(uuid, uuid, jsonb, numeric, text, uuid, text, timestamptz, text) to authenticated;
grant execute on function public.post_expense(uuid, uuid, numeric, text, uuid, text, timestamptz, text) to authenticated;
grant execute on function public.post_payment(uuid, uuid, char, numeric, text, text, uuid, timestamptz, text) to authenticated;
grant execute on function public.post_inventory_adjustment(uuid, text, jsonb, uuid, text, timestamptz, text) to authenticated;
grant execute on function public.complete_shop_setup(uuid) to authenticated;
