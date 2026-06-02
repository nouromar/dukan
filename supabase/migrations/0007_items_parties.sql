create table public.item (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  code text
    check (code is null or (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$')),
  catalog_item_id uuid references public.catalog_item(id) on delete restrict,
  catalog_revision_id uuid,
  source_template_item_id uuid references public.template_item(id) on delete set null,
  name text not null check (length(btrim(name)) > 0),
  name_override text check (name_override is null or length(btrim(name_override)) > 0),
  base_unit_id uuid not null references public.unit(id) on delete restrict,
  default_sale_unit_id uuid not null references public.unit(id) on delete restrict,
  default_receive_unit_id uuid not null references public.unit(id) on delete restrict,
  sale_price numeric(14, 2) check (sale_price is null or sale_price >= 0),
  last_cost numeric(14, 4) check (last_cost is null or last_cost >= 0),
  avg_cost numeric(14, 4) not null default 0 check (avg_cost >= 0),
  current_stock numeric(14, 3) not null default 0,
  reorder_threshold numeric(14, 3) check (reorder_threshold is null or reorder_threshold >= 0),
  barcode text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, code),
  unique (shop_id, id),
  check (
    (catalog_item_id is null and catalog_revision_id is null)
    or
    (catalog_item_id is not null and catalog_revision_id is not null)
  ),
  foreign key (catalog_item_id, catalog_revision_id) references public.catalog_item_revision(catalog_item_id, id) on delete restrict
);

create trigger set_item_updated_at
before update on public.item
for each row execute function public.set_updated_at();

create table public.item_unit (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null,
  item_id uuid not null,
  unit_id uuid not null references public.unit(id) on delete restrict,
  source_catalog_item_unit_id uuid references public.catalog_item_unit(id) on delete set null,
  source text not null default 'manual' check (source in ('catalog', 'template', 'manual', 'override')),
  conversion_to_base numeric(14, 6) not null check (conversion_to_base > 0),
  is_base_unit boolean not null default false,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, item_id, unit_id),
  unique (shop_id, id),
  foreign key (shop_id, item_id) references public.item(shop_id, id) on delete cascade
);

create trigger set_item_unit_updated_at
before update on public.item_unit
for each row execute function public.set_updated_at();

create unique index item_unit_single_base_unit_idx
  on public.item_unit (shop_id, item_id)
  where is_base_unit;

create table public.item_alias (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null,
  item_id uuid not null,
  alias_text text not null check (length(btrim(alias_text)) > 0),
  language_code text references public.language(code) on delete restrict,
  source text not null check (source in ('template', 'manual', 'ocr_correction', 'learned')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, alias_text, item_id),
  unique (shop_id, id),
  foreign key (shop_id, item_id) references public.item(shop_id, id) on delete cascade
);

create trigger set_item_alias_updated_at
before update on public.item_alias
for each row execute function public.set_updated_at();

create table public.supplier_type (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  code text not null
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  label text not null check (length(btrim(label)) > 0),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, code),
  unique (shop_id, id)
);

create trigger set_supplier_type_updated_at
before update on public.supplier_type
for each row execute function public.set_updated_at();

create table public.party (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  phone text,
  type_id uuid not null references public.party_type(id) on delete restrict,
  supplier_type_id uuid,
  receivable numeric(14, 2) not null default 0 check (receivable >= 0),
  payable numeric(14, 2) not null default 0 check (payable >= 0),
  notes text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, id),
  foreign key (shop_id, supplier_type_id) references public.supplier_type(shop_id, id) on delete set null
);

create trigger set_party_updated_at
before update on public.party
for each row execute function public.set_updated_at();

create table public.party_alias (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null,
  party_id uuid not null,
  alias_text text not null check (length(btrim(alias_text)) > 0),
  language_code text references public.language(code) on delete restrict,
  source text not null check (source in ('template', 'manual', 'ocr_correction', 'learned')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, alias_text, party_id),
  unique (shop_id, id),
  foreign key (shop_id, party_id) references public.party(shop_id, id) on delete cascade
);

create trigger set_party_alias_updated_at
before update on public.party_alias
for each row execute function public.set_updated_at();

create index item_shop_id_active_idx on public.item (shop_id, is_active);
create index item_shop_id_code_idx on public.item (shop_id, code);
create index item_shop_id_catalog_item_id_idx on public.item (shop_id, catalog_item_id);
create index item_catalog_revision_id_idx on public.item (catalog_revision_id);
create index item_alias_trgm_idx on public.item_alias using gin (alias_text extensions.gin_trgm_ops);
create index supplier_type_shop_id_active_idx on public.supplier_type (shop_id, is_active, sort_order);
create index party_shop_id_type_id_active_idx on public.party (shop_id, type_id, is_active);
create index party_alias_trgm_idx on public.party_alias using gin (alias_text extensions.gin_trgm_ops);

create view public.v_item_effective
with (security_invoker = true)
as
select
  i.id,
  i.shop_id,
  i.code,
  i.catalog_item_id,
  i.catalog_revision_id,
  i.source_template_item_id,
  coalesce(i.name_override, i.name) as display_name,
  i.name as inherited_name,
  i.name_override,
  cir.name as catalog_name,
  i.base_unit_id,
  bu.code as base_unit_code,
  i.default_sale_unit_id,
  su.code as default_sale_unit_code,
  i.default_receive_unit_id,
  ru.code as default_receive_unit_code,
  i.sale_price,
  i.last_cost,
  i.avg_cost,
  i.current_stock,
  i.reorder_threshold,
  i.barcode,
  i.is_active,
  i.created_at,
  i.updated_at
from public.item i
join public.unit bu on bu.id = i.base_unit_id
join public.unit su on su.id = i.default_sale_unit_id
join public.unit ru on ru.id = i.default_receive_unit_id
left join public.catalog_item_revision cir on cir.id = i.catalog_revision_id;

grant select, insert, update on
  public.item,
  public.item_unit,
  public.item_alias,
  public.supplier_type,
  public.party,
  public.party_alias
to authenticated;

grant select on public.v_item_effective to authenticated;

alter table public.item enable row level security;
alter table public.item_unit enable row level security;
alter table public.item_alias enable row level security;
alter table public.supplier_type enable row level security;
alter table public.party enable row level security;
alter table public.party_alias enable row level security;

create policy item_select
on public.item
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy item_insert
on public.item
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy item_update
on public.item
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));

create policy item_unit_select
on public.item_unit
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy item_unit_insert
on public.item_unit
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy item_unit_update
on public.item_unit
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));

create policy item_alias_select
on public.item_alias
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy item_alias_insert
on public.item_alias
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy item_alias_update
on public.item_alias
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));

create policy supplier_type_select
on public.supplier_type
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy supplier_type_insert
on public.supplier_type
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy supplier_type_update
on public.supplier_type
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));

create policy party_select
on public.party
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy party_insert
on public.party
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy party_update
on public.party
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));

create policy party_alias_select
on public.party_alias
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy party_alias_insert
on public.party_alias
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy party_alias_update
on public.party_alias
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));
