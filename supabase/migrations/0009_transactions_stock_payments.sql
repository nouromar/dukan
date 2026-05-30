create table public.txn (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  type_id uuid not null references public.transaction_type(id) on delete restrict,
  status_id uuid not null references public.transaction_status(id) on delete restrict,
  party_id uuid,
  occurred_at timestamptz not null,
  posted_at timestamptz,
  total_amount numeric(14, 2) not null check (total_amount >= 0),
  paid_amount numeric(14, 2) not null default 0 check (paid_amount >= 0),
  payment_method_id uuid references public.payment_method(id) on delete restrict,
  document_id uuid,
  reverses_transaction_id uuid,
  client_op_id text,
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  check (paid_amount <= total_amount),
  foreign key (shop_id, party_id) references public.party(shop_id, id) on delete restrict,
  foreign key (shop_id, document_id) references public.document(shop_id, id) on delete restrict,
  foreign key (shop_id, reverses_transaction_id) references public.txn(shop_id, id) on delete restrict
);

create unique index txn_shop_client_op_id_idx
  on public.txn (shop_id, client_op_id)
  where client_op_id is not null;

create table public.transaction_line (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  transaction_id uuid not null,
  line_no integer not null check (line_no > 0),
  item_id uuid,
  expense_category_id uuid,
  quantity numeric(14, 3) check (quantity is null or quantity > 0),
  unit_id uuid references public.unit(id) on delete restrict,
  base_quantity numeric(14, 3) check (base_quantity is null or base_quantity > 0),
  unit_amount numeric(14, 4) check (unit_amount is null or unit_amount >= 0),
  item_name_snapshot text,
  unit_code_snapshot text,
  unit_conversion_to_base_snapshot numeric(14, 6) check (unit_conversion_to_base_snapshot is null or unit_conversion_to_base_snapshot > 0),
  catalog_revision_id uuid references public.catalog_item_revision(id) on delete restrict,
  line_total numeric(14, 2) not null check (line_total >= 0),
  cogs_unit_cost numeric(14, 4) check (cogs_unit_cost is null or cogs_unit_cost >= 0),
  cogs_total numeric(14, 2) check (cogs_total is null or cogs_total >= 0),
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  unique (shop_id, transaction_id, line_no),
  check (
    (
      item_id is not null
      and expense_category_id is null
      and quantity is not null
      and unit_id is not null
      and base_quantity is not null
      and item_name_snapshot is not null
      and unit_code_snapshot is not null
      and unit_conversion_to_base_snapshot is not null
    )
    or
    (
      item_id is null
      and expense_category_id is not null
      and quantity is null
      and unit_id is null
      and base_quantity is null
      and item_name_snapshot is null
      and unit_code_snapshot is null
      and unit_conversion_to_base_snapshot is null
      and catalog_revision_id is null
    )
  ),
  foreign key (shop_id, transaction_id) references public.txn(shop_id, id) on delete cascade,
  foreign key (shop_id, item_id) references public.item(shop_id, id) on delete restrict,
  foreign key (shop_id, expense_category_id) references public.expense_category(shop_id, id) on delete restrict
);

create table public.payment (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  party_id uuid,
  direction char(1) not null check (direction in ('I', 'O')),
  amount numeric(14, 2) not null check (amount > 0),
  method_id uuid not null references public.payment_method(id) on delete restrict,
  occurred_at timestamptz not null,
  document_id uuid,
  client_op_id text,
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  foreign key (shop_id, party_id) references public.party(shop_id, id) on delete restrict,
  foreign key (shop_id, document_id) references public.document(shop_id, id) on delete restrict
);

create unique index payment_shop_client_op_id_idx
  on public.payment (shop_id, client_op_id)
  where client_op_id is not null;

create table public.payment_allocation (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  payment_id uuid not null,
  transaction_id uuid not null,
  amount numeric(14, 2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  unique (payment_id, transaction_id),
  unique (shop_id, id),
  foreign key (shop_id, payment_id) references public.payment(shop_id, id) on delete cascade,
  foreign key (shop_id, transaction_id) references public.txn(shop_id, id) on delete restrict
);

create table public.stock_movement (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  item_id uuid not null,
  location_id uuid,
  transaction_line_id uuid,
  inventory_adjustment_line_id uuid,
  quantity_delta numeric(14, 3) not null check (quantity_delta <> 0),
  unit_cost numeric(14, 4) check (unit_cost is null or unit_cost >= 0),
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  check (
    (transaction_line_id is not null and inventory_adjustment_line_id is null)
    or
    (transaction_line_id is null and inventory_adjustment_line_id is not null)
  ),
  foreign key (shop_id, item_id) references public.item(shop_id, id) on delete restrict,
  foreign key (shop_id, location_id) references public.location(shop_id, id) on delete restrict,
  foreign key (shop_id, transaction_line_id) references public.transaction_line(shop_id, id) on delete cascade
);

create table public.inventory_adjustment (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  reason_id uuid not null references public.adjustment_reason(id) on delete restrict,
  status_id uuid not null references public.transaction_status(id) on delete restrict,
  occurred_at timestamptz not null,
  posted_at timestamptz,
  document_id uuid,
  client_op_id text,
  notes text,
  approved_by uuid references auth.users(id) on delete restrict,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  foreign key (shop_id, document_id) references public.document(shop_id, id) on delete restrict
);

create unique index inventory_adjustment_shop_client_op_id_idx
  on public.inventory_adjustment (shop_id, client_op_id)
  where client_op_id is not null;

create table public.inventory_adjustment_line (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  adjustment_id uuid not null,
  item_id uuid not null,
  quantity_delta numeric(14, 3) not null check (quantity_delta <> 0),
  unit_cost numeric(14, 4) check (unit_cost is null or unit_cost >= 0),
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  foreign key (shop_id, adjustment_id) references public.inventory_adjustment(shop_id, id) on delete cascade,
  foreign key (shop_id, item_id) references public.item(shop_id, id) on delete restrict
);

alter table public.stock_movement
  add constraint stock_movement_adjustment_line_fk
  foreign key (shop_id, inventory_adjustment_line_id)
  references public.inventory_adjustment_line(shop_id, id)
  on delete cascade;

create unique index stock_movement_transaction_line_idx
  on public.stock_movement (shop_id, transaction_line_id)
  where transaction_line_id is not null;

create unique index stock_movement_adjustment_line_idx
  on public.stock_movement (shop_id, inventory_adjustment_line_id)
  where inventory_adjustment_line_id is not null;

create index txn_shop_occurred_at_idx on public.txn (shop_id, occurred_at desc);
create index txn_shop_type_status_occurred_at_idx on public.txn (shop_id, type_id, status_id, occurred_at desc);
create index txn_shop_party_occurred_at_idx on public.txn (shop_id, party_id, occurred_at desc);
create index transaction_line_shop_transaction_idx on public.transaction_line (shop_id, transaction_id, line_no);
create index transaction_line_shop_item_idx on public.transaction_line (shop_id, item_id);
create index payment_shop_party_occurred_at_idx on public.payment (shop_id, party_id, occurred_at desc);
create index payment_allocation_shop_transaction_idx on public.payment_allocation (shop_id, transaction_id);
create index stock_movement_shop_item_occurred_at_idx on public.stock_movement (shop_id, item_id, occurred_at desc);
create index inventory_adjustment_shop_occurred_at_idx on public.inventory_adjustment (shop_id, occurred_at desc);
create index inventory_adjustment_line_shop_item_idx on public.inventory_adjustment_line (shop_id, item_id);

grant select on
  public.txn,
  public.transaction_line,
  public.payment,
  public.payment_allocation,
  public.stock_movement,
  public.inventory_adjustment,
  public.inventory_adjustment_line
to authenticated;

alter table public.txn enable row level security;
alter table public.transaction_line enable row level security;
alter table public.payment enable row level security;
alter table public.payment_allocation enable row level security;
alter table public.stock_movement enable row level security;
alter table public.inventory_adjustment enable row level security;
alter table public.inventory_adjustment_line enable row level security;

create policy txn_select
on public.txn
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy transaction_line_select
on public.transaction_line
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy payment_select
on public.payment
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy payment_allocation_select
on public.payment_allocation
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy stock_movement_select
on public.stock_movement
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy inventory_adjustment_select
on public.inventory_adjustment
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy inventory_adjustment_line_select
on public.inventory_adjustment_line
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);
