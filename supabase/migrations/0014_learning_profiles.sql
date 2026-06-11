-- Per-shop learning artifacts and suggestion cache.
--
-- v2 schema notes:
--   - The old `learned_supplier_item_cost` table is gone. It is
--     replaced by `supplier_item_unit_cost` in 0007 (keyed on packaging
--     rather than item). Do not recreate it here.
--   - Per-shop `item` is now `shop_item`; all FKs target shop_item.
--   - Display names live in the alias chain — `v_shop_suggestions`
--     reads them via `shop_item_display_name(...)` from 0013.
--   - Template-driven suggestion seeding now resolves template_item by
--     code → global `item` → shop_item (the shop's activation row).
--   - `unit_id` columns still target the global `unit` table since
--     per-shop unit configuration is out of scope for v1.

-- ---------------------------------------------------------------------------
-- shop_item_usage
-- ---------------------------------------------------------------------------
--
-- Aggregate usage per (shop, shop_item). Drives recency boosts in
-- search ranking and "frequently sold" suggestions.

create table public.shop_item_usage (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  item_id uuid not null,
  sale_count integer not null default 0 check (sale_count >= 0),
  receive_count integer not null default 0 check (receive_count >= 0),
  total_sale_base_quantity numeric(14, 3) not null default 0 check (total_sale_base_quantity >= 0),
  total_receive_base_quantity numeric(14, 3) not null default 0 check (total_receive_base_quantity >= 0),
  last_sale_at timestamptz,
  last_receive_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, item_id),
  unique (shop_id, id),
  foreign key (shop_id, item_id) references public.shop_item(shop_id, id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- shop_item_entry_profile
-- ---------------------------------------------------------------------------
--
-- Tracks recurring (unit, quantity) combinations on sale/receive lines.
-- Powers quantity-suggestion chips. unit_id stays on the global `unit`
-- table — per-shop units are out of v1 scope.

create table public.shop_item_entry_profile (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  item_id uuid not null,
  context text not null check (context in ('sale', 'receive')),
  unit_id uuid not null references public.unit(id) on delete restrict,
  quantity numeric(14, 3) not null check (quantity > 0),
  usage_count integer not null default 0 check (usage_count >= 0),
  last_unit_amount numeric(14, 4) check (last_unit_amount is null or last_unit_amount >= 0),
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, item_id, context, unit_id, quantity),
  unique (shop_id, id),
  foreign key (shop_id, item_id) references public.shop_item(shop_id, id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- shop_supplier_item_profile
-- ---------------------------------------------------------------------------
--
-- Per-supplier learned usage. Drives "this supplier usually brings ..."
-- suggestion lists in Receive search. NOT the cost cache — that lives
-- in supplier_item_unit_cost (0007) keyed on packaging.

create table public.shop_supplier_item_profile (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  supplier_id uuid not null,
  item_id uuid not null,
  unit_id uuid not null references public.unit(id) on delete restrict,
  receive_count integer not null default 0 check (receive_count >= 0),
  total_base_quantity numeric(14, 3) not null default 0 check (total_base_quantity >= 0),
  last_unit_cost numeric(14, 4) check (last_unit_cost is null or last_unit_cost >= 0),
  last_received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, supplier_id, item_id, unit_id),
  unique (shop_id, id),
  foreign key (shop_id, supplier_id) references public.party(shop_id, id) on delete cascade,
  foreign key (shop_id, item_id) references public.shop_item(shop_id, id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- shop_party_usage
-- ---------------------------------------------------------------------------

create table public.shop_party_usage (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  party_id uuid not null,
  sale_count integer not null default 0 check (sale_count >= 0),
  receive_count integer not null default 0 check (receive_count >= 0),
  payment_count integer not null default 0 check (payment_count >= 0),
  last_sale_at timestamptz,
  last_receive_at timestamptz,
  last_payment_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, party_id),
  unique (shop_id, id),
  foreign key (shop_id, party_id) references public.party(shop_id, id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- shop_suggestion
-- ---------------------------------------------------------------------------

create table public.shop_suggestion (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  screen text not null check (screen in ('sale', 'receive', 'payment', 'expense', 'dashboard')),
  context_key text not null default 'global',
  suggestion_type text not null check (suggestion_type in ('item', 'quantity', 'supplier_item', 'customer', 'supplier', 'expense_category', 'payment_method')),
  target_key text not null,
  item_id uuid,
  party_id uuid,
  expense_category_id uuid,
  payment_method_id uuid references public.payment_method(id) on delete restrict,
  unit_id uuid references public.unit(id) on delete restrict,
  quantity numeric(14, 3) check (quantity is null or quantity > 0),
  value_text text,
  source text not null check (source in ('template', 'setup', 'learned', 'manual')),
  rank integer not null,
  is_active boolean not null default true,
  usage_count integer not null default 0 check (usage_count >= 0),
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, screen, context_key, suggestion_type, target_key, source),
  unique (shop_id, id),
  foreign key (shop_id, item_id) references public.shop_item(shop_id, id) on delete cascade,
  foreign key (shop_id, party_id) references public.party(shop_id, id) on delete cascade,
  foreign key (shop_id, expense_category_id) references public.expense_category(shop_id, id) on delete cascade,
  check (
    (suggestion_type in ('item', 'supplier_item') and item_id is not null)
    or (suggestion_type = 'quantity' and item_id is not null and unit_id is not null and quantity is not null)
    or (suggestion_type in ('customer', 'supplier') and party_id is not null)
    or (suggestion_type = 'expense_category' and expense_category_id is not null)
    or (suggestion_type = 'payment_method' and payment_method_id is not null)
  )
);

create index shop_item_usage_shop_rank_idx
  on public.shop_item_usage (shop_id, sale_count desc, last_sale_at desc);

create index shop_supplier_item_profile_shop_supplier_idx
  on public.shop_supplier_item_profile (shop_id, supplier_id, receive_count desc, last_received_at desc);

create index shop_party_usage_shop_recent_idx
  on public.shop_party_usage (shop_id, greatest(coalesce(last_sale_at, '-infinity'::timestamptz), coalesce(last_receive_at, '-infinity'::timestamptz), coalesce(last_payment_at, '-infinity'::timestamptz)) desc);

create index shop_suggestion_read_idx
  on public.shop_suggestion (shop_id, screen, context_key, rank)
  where is_active;

-- ---------------------------------------------------------------------------
-- v_shop_suggestions
-- ---------------------------------------------------------------------------
--
-- Read-side projection used by the app. Resolves display name via the
-- alias chain (see shop_item_display_name in 0013).

create view public.v_shop_suggestions
with (security_invoker = true)
as
select
  ss.shop_id,
  ss.id as suggestion_id,
  ss.screen,
  ss.context_key,
  ss.suggestion_type,
  ss.item_id,
  public.shop_item_display_name(ss.item_id, 'en') as item_name,
  ss.party_id,
  p.name as party_name,
  ss.expense_category_id,
  ec.code as expense_category_code,
  ec.name as expense_category_name,
  ss.payment_method_id,
  pm.code as payment_method_code,
  ss.unit_id,
  u.code as unit_code,
  ss.quantity,
  ss.value_text,
  ss.source,
  ss.rank,
  ss.usage_count,
  ss.last_used_at,
  ss.created_at,
  ss.updated_at
from public.shop_suggestion ss
left join public.shop_item si
  on si.shop_id = ss.shop_id
  and si.id = ss.item_id
left join public.party p
  on p.shop_id = ss.shop_id
  and p.id = ss.party_id
left join public.expense_category ec
  on ec.shop_id = ss.shop_id
  and ec.id = ss.expense_category_id
left join public.payment_method pm on pm.id = ss.payment_method_id
left join public.unit u on u.id = ss.unit_id
where ss.is_active;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public._suggestion_target_key(
  p_item_id uuid,
  p_party_id uuid,
  p_expense_category_id uuid,
  p_payment_method_id uuid,
  p_unit_id uuid,
  p_quantity numeric,
  p_value_text text
)
returns text
language sql
immutable
as $$
  select md5(concat_ws(
    '|',
    coalesce(p_item_id::text, ''),
    coalesce(p_party_id::text, ''),
    coalesce(p_expense_category_id::text, ''),
    coalesce(p_payment_method_id::text, ''),
    coalesce(p_unit_id::text, ''),
    coalesce(p_quantity::text, ''),
    coalesce(p_value_text, '')
  ));
$$;

create or replace function public._suggestion_rank(
  p_source text,
  p_usage_count integer,
  p_seed_rank integer default 0
)
returns integer
language sql
immutable
as $$
  select case p_source
    when 'manual' then 100 + p_seed_rank
    when 'setup' then 500 + p_seed_rank
    when 'learned' then 1000 + greatest(0, 500 - least(coalesce(p_usage_count, 0), 500))
    else 3000 + p_seed_rank
  end;
$$;

create or replace function public._upsert_shop_suggestion(
  p_shop_id uuid,
  p_screen text,
  p_context_key text,
  p_suggestion_type text,
  p_item_id uuid,
  p_party_id uuid,
  p_expense_category_id uuid,
  p_payment_method_id uuid,
  p_unit_id uuid,
  p_quantity numeric,
  p_value_text text,
  p_source text,
  p_rank integer,
  p_is_active boolean,
  p_usage_count integer,
  p_last_used_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.shop_suggestion (
    shop_id,
    screen,
    context_key,
    suggestion_type,
    target_key,
    item_id,
    party_id,
    expense_category_id,
    payment_method_id,
    unit_id,
    quantity,
    value_text,
    source,
    rank,
    is_active,
    usage_count,
    last_used_at
  )
  values (
    p_shop_id,
    p_screen,
    coalesce(p_context_key, 'global'),
    p_suggestion_type,
    public._suggestion_target_key(p_item_id, p_party_id, p_expense_category_id, p_payment_method_id, p_unit_id, p_quantity, p_value_text),
    p_item_id,
    p_party_id,
    p_expense_category_id,
    p_payment_method_id,
    p_unit_id,
    p_quantity,
    p_value_text,
    p_source,
    p_rank,
    p_is_active,
    coalesce(p_usage_count, 0),
    p_last_used_at
  )
  on conflict (shop_id, screen, context_key, suggestion_type, target_key, source)
  do update set
    rank = excluded.rank,
    is_active = excluded.is_active,
    usage_count = greatest(public.shop_suggestion.usage_count, excluded.usage_count),
    last_used_at = case
      when public.shop_suggestion.last_used_at is null then excluded.last_used_at
      when excluded.last_used_at is null then public.shop_suggestion.last_used_at
      else greatest(public.shop_suggestion.last_used_at, excluded.last_used_at)
    end,
    updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- rebuild_shop_suggestions(shop_id)
-- ---------------------------------------------------------------------------
--
-- Seeds template-driven suggestions for a shop after a template
-- application. Template rows reference items by global `item.code`;
-- we resolve those to the shop's `shop_item` (which must already be
-- activated by `apply_template` for the join to land).

create or replace function public.rebuild_shop_suggestions(p_shop_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (
    public.auth_can_access_shop(p_shop_id)
    or public.auth_is_platform_staff(null)
  ) then
    raise exception 'Not allowed to rebuild suggestions for this shop';
  end if;

  -- Item suggestions sourced from template_item, resolved via the
  -- global item row to the shop's activation row.
  insert into public.shop_suggestion (
    shop_id,
    screen,
    context_key,
    suggestion_type,
    target_key,
    item_id,
    source,
    rank,
    is_active
  )
  select
    p_shop_id,
    screen_code,
    'global',
    'item',
    public._suggestion_target_key(si.id, null, null, null, null, null, null),
    si.id,
    'template',
    public._suggestion_rank('template', 0, min(sort_order)),
    true
  from (
    select ti.template_id, ti.item_code, ti.sort_order, 'sale'::text as screen_code
    from public.template_application ta
    join public.template_item ti on ti.template_id = ta.template_id
    where ta.shop_id = p_shop_id and ta.status = 'applied'
    union all
    select ti.template_id, ti.item_code, ti.sort_order, 'receive'::text as screen_code
    from public.template_application ta
    join public.template_item ti on ti.template_id = ta.template_id
    where ta.shop_id = p_shop_id and ta.status = 'applied'
  ) template_items
  join public.item gi on gi.code = template_items.item_code
  join public.shop_item si
    on si.shop_id = p_shop_id
    and si.item_id = gi.id
  group by si.id, screen_code
  on conflict (shop_id, screen, context_key, suggestion_type, target_key, source)
  do update set
    rank = least(public.shop_suggestion.rank, excluded.rank),
    is_active = true,
    updated_at = now();

  -- Quantity suggestions sourced from template_quantity_suggestion.
  insert into public.shop_suggestion (
    shop_id,
    screen,
    context_key,
    suggestion_type,
    target_key,
    item_id,
    unit_id,
    quantity,
    source,
    rank,
    is_active
  )
  select
    p_shop_id,
    tqs.context,
    'global',
    'quantity',
    public._suggestion_target_key(si.id, null, null, null, u.id, tqs.quantity, null),
    si.id,
    u.id,
    tqs.quantity,
    'template',
    public._suggestion_rank('template', 0, min(tqs.sort_order)),
    true
  from public.template_application ta
  join public.template_quantity_suggestion tqs on tqs.template_id = ta.template_id
  join public.item gi on gi.code = tqs.item_code
  join public.shop_item si
    on si.shop_id = p_shop_id
    and si.item_id = gi.id
  join public.unit u on u.code = tqs.unit_code and u.is_active
  where ta.shop_id = p_shop_id
    and ta.status = 'applied'
    and tqs.item_code is not null
    and tqs.context in ('sale', 'receive')
  group by tqs.context, si.id, u.id, tqs.quantity
  on conflict (shop_id, screen, context_key, suggestion_type, target_key, source)
  do update set
    rank = least(public.shop_suggestion.rank, excluded.rank),
    is_active = true,
    updated_at = now();

  -- Quick-action seeds (item or expense_category, per row).
  insert into public.shop_suggestion (
    shop_id,
    screen,
    context_key,
    suggestion_type,
    target_key,
    item_id,
    expense_category_id,
    source,
    rank,
    is_active
  )
  select
    p_shop_id,
    tqa.screen,
    'global',
    case when tqa.item_code is not null then 'item' else 'expense_category' end,
    public._suggestion_target_key(si.id, null, ec.id, null, null, null, null),
    si.id,
    ec.id,
    'template',
    public._suggestion_rank('template', 0, min(tqa.position)),
    true
  from public.template_application ta
  join public.template_quick_action tqa on tqa.template_id = ta.template_id
  left join public.item gi on gi.code = tqa.item_code
  left join public.shop_item si
    on si.shop_id = p_shop_id
    and si.item_id = gi.id
  left join public.expense_category ec
    on ec.shop_id = p_shop_id
    and ec.code = tqa.expense_category_code
  where ta.shop_id = p_shop_id
    and ta.status = 'applied'
    and (
      (tqa.item_code is not null and si.id is not null)
      or (tqa.expense_category_code is not null and ec.id is not null)
    )
  group by tqa.screen, tqa.item_code, si.id, ec.id
  on conflict (shop_id, screen, context_key, suggestion_type, target_key, source)
  do update set
    rank = least(public.shop_suggestion.rank, excluded.rank),
    is_active = true,
    updated_at = now();

  -- Expense category catalog (independent of template_item rows).
  insert into public.shop_suggestion (
    shop_id,
    screen,
    context_key,
    suggestion_type,
    target_key,
    expense_category_id,
    source,
    rank,
    is_active
  )
  select
    p_shop_id,
    'expense',
    'global',
    'expense_category',
    public._suggestion_target_key(null, null, ec.id, null, null, null, null),
    ec.id,
    'template',
    public._suggestion_rank('template', 0, row_number() over (order by ec.code)::integer),
    true
  from public.expense_category ec
  where ec.shop_id = p_shop_id
  on conflict (shop_id, screen, context_key, suggestion_type, target_key, source)
  do update set
    rank = least(public.shop_suggestion.rank, excluded.rank),
    is_active = true,
    updated_at = now();
end;
$$;

create or replace function public._seed_shop_suggestions_after_template_application()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'applied' and old.status is distinct from new.status then
    perform public.rebuild_shop_suggestions(new.shop_id);
  end if;

  return new;
end;
$$;

create trigger template_application_seed_shop_suggestions
after update of status on public.template_application
for each row
execute function public._seed_shop_suggestions_after_template_application();

-- ---------------------------------------------------------------------------
-- Learn from transaction_line / payment
-- ---------------------------------------------------------------------------
--
-- These triggers read `new.item_id` (now a `shop_item.id`) and
-- `new.unit_id` (still a global `unit.id`). The shape is unchanged
-- from the pre-v2 trigger.

create or replace function public._learn_from_transaction_line()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transaction_type text;
  v_status_code text;
  v_party_id uuid;
  v_occurred_at timestamptz;
  v_reverses_transaction_id uuid;
  v_usage_count integer;
  v_rank integer;
begin
  select tt.code, ts.code, t.party_id, t.occurred_at, t.reverses_transaction_id
  into v_transaction_type, v_status_code, v_party_id, v_occurred_at, v_reverses_transaction_id
  from public.txn t
  join public.transaction_type tt on tt.id = t.type_id
  join public.transaction_status ts on ts.id = t.status_id
  where t.shop_id = new.shop_id
    and t.id = new.transaction_id;

  if v_status_code <> 'posted' or v_reverses_transaction_id is not null then
    return new;
  end if;

  if v_transaction_type = 'sale' and new.item_id is not null then
    insert into public.shop_item_usage (
      shop_id,
      item_id,
      sale_count,
      total_sale_base_quantity,
      last_sale_at
    )
    values (
      new.shop_id,
      new.item_id,
      1,
      coalesce(new.base_quantity, 0),
      v_occurred_at
    )
    on conflict (shop_id, item_id)
    do update set
      sale_count = public.shop_item_usage.sale_count + 1,
      total_sale_base_quantity = public.shop_item_usage.total_sale_base_quantity + coalesce(excluded.total_sale_base_quantity, 0),
      last_sale_at = greatest(coalesce(public.shop_item_usage.last_sale_at, excluded.last_sale_at), excluded.last_sale_at),
      updated_at = now()
    returning sale_count into v_usage_count;

    v_rank := public._suggestion_rank('learned', v_usage_count, 0);
    perform public._upsert_shop_suggestion(new.shop_id, 'sale', 'global', 'item', new.item_id, null, null, null, null, null, null, 'learned', v_rank, v_usage_count >= 2, v_usage_count, v_occurred_at);

    insert into public.shop_item_entry_profile (
      shop_id,
      item_id,
      context,
      unit_id,
      quantity,
      usage_count,
      last_unit_amount,
      last_used_at
    )
    values (
      new.shop_id,
      new.item_id,
      'sale',
      new.unit_id,
      new.quantity,
      1,
      new.unit_amount,
      v_occurred_at
    )
    on conflict (shop_id, item_id, context, unit_id, quantity)
    do update set
      usage_count = public.shop_item_entry_profile.usage_count + 1,
      last_unit_amount = excluded.last_unit_amount,
      last_used_at = greatest(coalesce(public.shop_item_entry_profile.last_used_at, excluded.last_used_at), excluded.last_used_at),
      updated_at = now()
    returning usage_count into v_usage_count;

    v_rank := public._suggestion_rank('learned', v_usage_count, 100);
    perform public._upsert_shop_suggestion(new.shop_id, 'sale', 'global', 'quantity', new.item_id, null, null, null, new.unit_id, new.quantity, null, 'learned', v_rank, v_usage_count >= 2, v_usage_count, v_occurred_at);

    if v_party_id is not null then
      insert into public.shop_party_usage (shop_id, party_id, sale_count, last_sale_at)
      values (new.shop_id, v_party_id, 1, v_occurred_at)
      on conflict (shop_id, party_id)
      do update set
        sale_count = public.shop_party_usage.sale_count + 1,
        last_sale_at = greatest(coalesce(public.shop_party_usage.last_sale_at, excluded.last_sale_at), excluded.last_sale_at),
        updated_at = now()
      returning sale_count into v_usage_count;

      v_rank := public._suggestion_rank('learned', v_usage_count, 0);
      perform public._upsert_shop_suggestion(new.shop_id, 'sale', 'global', 'customer', null, v_party_id, null, null, null, null, null, 'learned', v_rank, v_usage_count >= 2, v_usage_count, v_occurred_at);
    end if;
  elsif v_transaction_type = 'receive' and new.item_id is not null then
    insert into public.shop_item_usage (
      shop_id,
      item_id,
      receive_count,
      total_receive_base_quantity,
      last_receive_at
    )
    values (
      new.shop_id,
      new.item_id,
      1,
      coalesce(new.base_quantity, 0),
      v_occurred_at
    )
    on conflict (shop_id, item_id)
    do update set
      receive_count = public.shop_item_usage.receive_count + 1,
      total_receive_base_quantity = public.shop_item_usage.total_receive_base_quantity + coalesce(excluded.total_receive_base_quantity, 0),
      last_receive_at = greatest(coalesce(public.shop_item_usage.last_receive_at, excluded.last_receive_at), excluded.last_receive_at),
      updated_at = now()
    returning receive_count into v_usage_count;

    v_rank := public._suggestion_rank('learned', v_usage_count, 0);
    perform public._upsert_shop_suggestion(new.shop_id, 'receive', 'global', 'item', new.item_id, null, null, null, null, null, null, 'learned', v_rank, v_usage_count >= 1, v_usage_count, v_occurred_at);

    insert into public.shop_item_entry_profile (
      shop_id,
      item_id,
      context,
      unit_id,
      quantity,
      usage_count,
      last_unit_amount,
      last_used_at
    )
    values (
      new.shop_id,
      new.item_id,
      'receive',
      new.unit_id,
      new.quantity,
      1,
      new.unit_amount,
      v_occurred_at
    )
    on conflict (shop_id, item_id, context, unit_id, quantity)
    do update set
      usage_count = public.shop_item_entry_profile.usage_count + 1,
      last_unit_amount = excluded.last_unit_amount,
      last_used_at = greatest(coalesce(public.shop_item_entry_profile.last_used_at, excluded.last_used_at), excluded.last_used_at),
      updated_at = now()
    returning usage_count into v_usage_count;

    v_rank := public._suggestion_rank('learned', v_usage_count, 100);
    perform public._upsert_shop_suggestion(new.shop_id, 'receive', 'global', 'quantity', new.item_id, null, null, null, new.unit_id, new.quantity, null, 'learned', v_rank, v_usage_count >= 1, v_usage_count, v_occurred_at);

    if v_party_id is not null then
      insert into public.shop_supplier_item_profile (
        shop_id,
        supplier_id,
        item_id,
        unit_id,
        receive_count,
        total_base_quantity,
        last_unit_cost,
        last_received_at
      )
      values (
        new.shop_id,
        v_party_id,
        new.item_id,
        new.unit_id,
        1,
        coalesce(new.base_quantity, 0),
        new.unit_amount,
        v_occurred_at
      )
      on conflict (shop_id, supplier_id, item_id, unit_id)
      do update set
        receive_count = public.shop_supplier_item_profile.receive_count + 1,
        total_base_quantity = public.shop_supplier_item_profile.total_base_quantity + coalesce(excluded.total_base_quantity, 0),
        last_unit_cost = excluded.last_unit_cost,
        last_received_at = greatest(coalesce(public.shop_supplier_item_profile.last_received_at, excluded.last_received_at), excluded.last_received_at),
        updated_at = now()
      returning receive_count into v_usage_count;

      v_rank := public._suggestion_rank('learned', v_usage_count, 0);
      perform public._upsert_shop_suggestion(new.shop_id, 'receive', 'supplier:' || v_party_id::text, 'supplier_item', new.item_id, v_party_id, null, null, null, null, null, 'learned', v_rank, v_usage_count >= 1, v_usage_count, v_occurred_at);

      insert into public.shop_party_usage (shop_id, party_id, receive_count, last_receive_at)
      values (new.shop_id, v_party_id, 1, v_occurred_at)
      on conflict (shop_id, party_id)
      do update set
        receive_count = public.shop_party_usage.receive_count + 1,
        last_receive_at = greatest(coalesce(public.shop_party_usage.last_receive_at, excluded.last_receive_at), excluded.last_receive_at),
        updated_at = now()
      returning receive_count into v_usage_count;

      v_rank := public._suggestion_rank('learned', v_usage_count, 0);
      perform public._upsert_shop_suggestion(new.shop_id, 'receive', 'global', 'supplier', null, v_party_id, null, null, null, null, null, 'learned', v_rank, v_usage_count >= 1, v_usage_count, v_occurred_at);
    end if;
  elsif v_transaction_type = 'expense' and new.expense_category_id is not null then
    perform public._upsert_shop_suggestion(new.shop_id, 'expense', 'global', 'expense_category', null, null, new.expense_category_id, null, null, null, null, 'learned', public._suggestion_rank('learned', 1, 0), true, 1, v_occurred_at);
  end if;

  return new;
end;
$$;

create trigger transaction_line_learn_from_insert
after insert on public.transaction_line
for each row
execute function public._learn_from_transaction_line();

create or replace function public._learn_from_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usage_count integer;
  v_rank integer;
begin
  perform public._upsert_shop_suggestion(
    new.shop_id,
    'payment',
    'direction:' || new.direction,
    'payment_method',
    null,
    null,
    null,
    new.method_id,
    null,
    null,
    null,
    'learned',
    public._suggestion_rank('learned', 1, 0),
    true,
    1,
    new.occurred_at
  );

  if new.party_id is not null then
    insert into public.shop_party_usage (shop_id, party_id, payment_count, last_payment_at)
    values (new.shop_id, new.party_id, 1, new.occurred_at)
    on conflict (shop_id, party_id)
    do update set
      payment_count = public.shop_party_usage.payment_count + 1,
      last_payment_at = greatest(coalesce(public.shop_party_usage.last_payment_at, excluded.last_payment_at), excluded.last_payment_at),
      updated_at = now()
    returning payment_count into v_usage_count;

    v_rank := public._suggestion_rank('learned', v_usage_count, 0);
    perform public._upsert_shop_suggestion(new.shop_id, 'payment', 'global', case when new.direction = 'I' then 'customer' else 'supplier' end, null, new.party_id, null, null, null, null, null, 'learned', v_rank, v_usage_count >= 1, v_usage_count, new.occurred_at);
  end if;

  return new;
end;
$$;

create trigger payment_learn_from_insert
after insert on public.payment
for each row
execute function public._learn_from_payment();

-- ---------------------------------------------------------------------------
-- RLS + grants
-- ---------------------------------------------------------------------------

alter table public.shop_item_usage enable row level security;
alter table public.shop_item_entry_profile enable row level security;
alter table public.shop_supplier_item_profile enable row level security;
alter table public.shop_party_usage enable row level security;
alter table public.shop_suggestion enable row level security;

create policy shop_item_usage_select on public.shop_item_usage for select using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy shop_item_entry_profile_select on public.shop_item_entry_profile for select using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy shop_supplier_item_profile_select on public.shop_supplier_item_profile for select using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy shop_party_usage_select on public.shop_party_usage for select using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy shop_suggestion_select on public.shop_suggestion for select using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

grant select on
  public.shop_item_usage,
  public.shop_item_entry_profile,
  public.shop_supplier_item_profile,
  public.shop_party_usage,
  public.shop_suggestion,
  public.v_shop_suggestions
to authenticated;

revoke all on function public._suggestion_target_key(uuid, uuid, uuid, uuid, uuid, numeric, text) from public;
revoke all on function public._suggestion_rank(text, integer, integer) from public;
revoke all on function public._upsert_shop_suggestion(uuid, text, text, text, uuid, uuid, uuid, uuid, uuid, numeric, text, text, integer, boolean, integer, timestamptz) from public;
revoke all on function public._seed_shop_suggestions_after_template_application() from public;
revoke all on function public._learn_from_transaction_line() from public;
revoke all on function public._learn_from_payment() from public;
revoke all on function public.rebuild_shop_suggestions(uuid) from public;
grant execute on function public.rebuild_shop_suggestions(uuid) to authenticated;
