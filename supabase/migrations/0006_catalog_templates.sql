create table public.catalog_product_concept (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  name_en text not null check (length(btrim(name_en)) > 0),
  description_en text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_catalog_product_concept_updated_at
before update on public.catalog_product_concept
for each row execute function public.set_updated_at();

create table public.catalog_product_translation (
  concept_id uuid not null references public.catalog_product_concept(id) on delete cascade,
  language_code text not null references public.language(code) on delete restrict,
  name text not null check (length(btrim(name)) > 0),
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (concept_id, language_code)
);

create trigger set_catalog_product_translation_updated_at
before update on public.catalog_product_translation
for each row execute function public.set_updated_at();

create table public.catalog_item (
  id uuid primary key default extensions.gen_random_uuid(),
  concept_id uuid not null references public.catalog_product_concept(id) on delete restrict,
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  current_revision_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_catalog_item_updated_at
before update on public.catalog_item
for each row execute function public.set_updated_at();

create table public.catalog_item_revision (
  id uuid primary key default extensions.gen_random_uuid(),
  catalog_item_id uuid not null references public.catalog_item(id) on delete cascade,
  revision_number integer not null check (revision_number > 0),
  name text not null check (length(btrim(name)) > 0),
  brand_name text,
  package_quantity numeric(14, 3),
  package_unit_code text references public.unit(code) on delete restrict,
  variant text,
  category_code text,
  base_unit_code text not null references public.unit(code) on delete restrict,
  default_sale_unit_code text not null references public.unit(code) on delete restrict,
  default_receive_unit_code text not null references public.unit(code) on delete restrict,
  suggested_sale_price numeric(14, 2) check (suggested_sale_price is null or suggested_sale_price >= 0),
  reorder_threshold numeric(14, 3) check (reorder_threshold is null or reorder_threshold >= 0),
  effective_from timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (catalog_item_id, revision_number),
  unique (catalog_item_id, id)
);

alter table public.catalog_item
  add constraint catalog_item_current_revision_fk
  foreign key (id, current_revision_id)
  references public.catalog_item_revision(catalog_item_id, id)
  deferrable initially deferred;

create table public.catalog_item_unit (
  id uuid primary key default extensions.gen_random_uuid(),
  catalog_item_id uuid not null,
  revision_id uuid not null,
  unit_code text not null references public.unit(code) on delete restrict,
  conversion_to_base numeric(14, 6) not null check (conversion_to_base > 0),
  is_base_unit boolean not null default false,
  allow_sale boolean not null default true,
  allow_receive boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (catalog_item_id, revision_id, unit_code),
  unique (catalog_item_id, revision_id, id),
  foreign key (catalog_item_id, revision_id) references public.catalog_item_revision(catalog_item_id, id) on delete cascade
);

create unique index catalog_item_unit_single_base_idx
  on public.catalog_item_unit (catalog_item_id, revision_id)
  where is_base_unit;

create table public.catalog_item_alias (
  id uuid primary key default extensions.gen_random_uuid(),
  catalog_item_id uuid not null references public.catalog_item(id) on delete cascade,
  language_code text references public.language(code) on delete restrict,
  alias_text text not null check (length(btrim(alias_text)) > 0),
  source text not null default 'platform' check (source in ('platform', 'template', 'learned')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (catalog_item_id, language_code, alias_text)
);

create trigger set_catalog_item_alias_updated_at
before update on public.catalog_item_alias
for each row execute function public.set_updated_at();

create table public.template (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  kind text not null default 'shop_starter',
  name text not null check (length(btrim(name)) > 0),
  locale_default text not null references public.language(code) on delete restrict,
  currency_default text not null references public.currency(code) on delete restrict,
  version integer not null check (version > 0),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (code, version),
  unique (id, version)
);

create trigger set_template_updated_at
before update on public.template
for each row execute function public.set_updated_at();

create table public.template_pack (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  code text not null
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  version integer not null check (version > 0),
  is_required boolean not null default true,
  file_path text not null,
  checksum text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, code, version),
  unique (template_id, code)
);

create trigger set_template_pack_updated_at
before update on public.template_pack
for each row execute function public.set_updated_at();

create table public.template_unit (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  unit_code text not null references public.unit(code) on delete restrict,
  label jsonb,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, unit_code)
);

create trigger set_template_unit_updated_at
before update on public.template_unit
for each row execute function public.set_updated_at();

create table public.template_item (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  item_code text not null
    check (item_code = lower(item_code) and item_code ~ '^[a-z][a-z0-9_]*$'),
  catalog_item_id uuid references public.catalog_item(id) on delete restrict,
  catalog_revision_id uuid,
  custom_name text check (custom_name is null or length(btrim(custom_name)) > 0),
  name_override text check (name_override is null or length(btrim(name_override)) > 0),
  base_unit_code_override text references public.unit(code) on delete restrict,
  default_sale_unit_code_override text references public.unit(code) on delete restrict,
  default_receive_unit_code_override text references public.unit(code) on delete restrict,
  suggested_sale_price_override numeric(14, 2) check (suggested_sale_price_override is null or suggested_sale_price_override >= 0),
  reorder_threshold_override numeric(14, 3) check (reorder_threshold_override is null or reorder_threshold_override >= 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, item_code),
  check (
    (catalog_item_id is not null and catalog_revision_id is not null)
    or
    (
      catalog_item_id is null
      and catalog_revision_id is null
      and custom_name is not null
      and base_unit_code_override is not null
      and default_sale_unit_code_override is not null
      and default_receive_unit_code_override is not null
    )
  ),
  foreign key (catalog_item_id, catalog_revision_id) references public.catalog_item_revision(catalog_item_id, id) on delete restrict
);

create trigger set_template_item_updated_at
before update on public.template_item
for each row execute function public.set_updated_at();

create table public.template_item_unit (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null,
  item_code text not null,
  unit_code text not null references public.unit(code) on delete restrict,
  conversion_to_base numeric(14, 6) not null check (conversion_to_base > 0),
  allow_sale boolean not null default true,
  allow_receive boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, item_code, unit_code),
  foreign key (template_id, item_code) references public.template_item(template_id, item_code) on delete cascade
);

create trigger set_template_item_unit_updated_at
before update on public.template_item_unit
for each row execute function public.set_updated_at();

create table public.template_supplier_type (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  supplier_type_code text not null
    check (supplier_type_code = lower(supplier_type_code) and supplier_type_code ~ '^[a-z][a-z0-9_]*$'),
  label jsonb,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, supplier_type_code)
);

create trigger set_template_supplier_type_updated_at
before update on public.template_supplier_type
for each row execute function public.set_updated_at();

create table public.template_supplier_item (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null,
  supplier_type_code text not null,
  item_code text not null,
  usual_unit_code text references public.unit(code) on delete restrict,
  cost_entry_mode text check (cost_entry_mode in ('unit_cost', 'line_total')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, supplier_type_code, item_code),
  foreign key (template_id, supplier_type_code) references public.template_supplier_type(template_id, supplier_type_code) on delete cascade,
  foreign key (template_id, item_code) references public.template_item(template_id, item_code) on delete cascade
);

create trigger set_template_supplier_item_updated_at
before update on public.template_supplier_item
for each row execute function public.set_updated_at();

create table public.template_quantity_suggestion (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  item_code text,
  category_code text,
  context text not null check (context in ('sale', 'receive')),
  quantity numeric(14, 3) not null check (quantity > 0),
  unit_code text not null references public.unit(code) on delete restrict,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (item_code is not null or category_code is not null)
);

create trigger set_template_quantity_suggestion_updated_at
before update on public.template_quantity_suggestion
for each row execute function public.set_updated_at();

create table public.template_quick_action (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  screen text not null check (screen in ('sale', 'receive', 'expense')),
  position integer not null check (position > 0),
  item_code text,
  expense_category_code text,
  label jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, screen, position),
  check (item_code is not null or expense_category_code is not null or label is not null)
);

create trigger set_template_quick_action_updated_at
before update on public.template_quick_action
for each row execute function public.set_updated_at();

create table public.template_item_alias (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null,
  item_code text not null,
  language_code text references public.language(code) on delete restrict,
  alias_text text not null check (length(btrim(alias_text)) > 0),
  source text not null default 'template',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, item_code, language_code, alias_text),
  foreign key (template_id, item_code) references public.template_item(template_id, item_code) on delete cascade
);

create trigger set_template_item_alias_updated_at
before update on public.template_item_alias
for each row execute function public.set_updated_at();

create table public.template_party_alias (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  party_code text not null
    check (party_code = lower(party_code) and party_code ~ '^[a-z][a-z0-9_]*$'),
  language_code text references public.language(code) on delete restrict,
  alias_text text not null check (length(btrim(alias_text)) > 0),
  source text not null default 'template',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, party_code, language_code, alias_text)
);

create trigger set_template_party_alias_updated_at
before update on public.template_party_alias
for each row execute function public.set_updated_at();

create table public.template_expense_category (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  code text not null
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  name text not null check (length(btrim(name)) > 0),
  name_translations jsonb,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, code)
);

create trigger set_template_expense_category_updated_at
before update on public.template_expense_category
for each row execute function public.set_updated_at();

create table public.template_setting (
  id uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  key text not null
    check (key = lower(key) and key ~ '^[a-z][a-z0-9_]*$'),
  value jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, key)
);

create trigger set_template_setting_updated_at
before update on public.template_setting
for each row execute function public.set_updated_at();

create table public.template_application (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  template_id uuid not null references public.template(id) on delete restrict,
  template_version integer not null check (template_version > 0),
  applied_by uuid references auth.users(id) on delete set null,
  applied_at timestamptz not null default now(),
  merge_strategy text not null check (merge_strategy in ('first_apply', 'merge_update')),
  status text not null default 'applied' check (status in ('applying', 'applied', 'failed')),
  unique (shop_id, template_id, template_version),
  unique (shop_id, id),
  foreign key (template_id, template_version) references public.template(id, version) on delete restrict
);

create table public.template_pack_application (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null,
  template_application_id uuid not null,
  pack_code text not null,
  pack_version integer not null check (pack_version > 0),
  applied_at timestamptz not null default now(),
  status text not null check (status in ('applied', 'skipped', 'failed')),
  unique (template_application_id, pack_code),
  unique (shop_id, id),
  foreign key (shop_id, template_application_id) references public.template_application(shop_id, id) on delete cascade
);

create index catalog_item_concept_id_idx on public.catalog_item (concept_id);
create index catalog_item_revision_catalog_item_id_idx on public.catalog_item_revision (catalog_item_id, revision_number desc);
create index catalog_item_unit_revision_idx on public.catalog_item_unit (catalog_item_id, revision_id, sort_order);
create index catalog_item_alias_trgm_idx on public.catalog_item_alias using gin (alias_text extensions.gin_trgm_ops);
create index template_item_template_id_sort_order_idx on public.template_item (template_id, sort_order);
create index template_quantity_suggestion_template_context_idx on public.template_quantity_suggestion (template_id, context, sort_order);
create index template_application_shop_id_applied_at_idx on public.template_application (shop_id, applied_at desc);

grant select on
  public.catalog_product_concept,
  public.catalog_product_translation,
  public.catalog_item,
  public.catalog_item_revision,
  public.catalog_item_unit,
  public.catalog_item_alias,
  public.template,
  public.template_pack,
  public.template_unit,
  public.template_item,
  public.template_item_unit,
  public.template_supplier_type,
  public.template_supplier_item,
  public.template_quantity_suggestion,
  public.template_quick_action,
  public.template_item_alias,
  public.template_party_alias,
  public.template_expense_category,
  public.template_setting
to anon, authenticated;

grant insert, update on
  public.catalog_product_concept,
  public.catalog_product_translation,
  public.catalog_item,
  public.catalog_item_revision,
  public.catalog_item_unit,
  public.catalog_item_alias,
  public.template,
  public.template_pack,
  public.template_unit,
  public.template_item,
  public.template_item_unit,
  public.template_supplier_type,
  public.template_supplier_item,
  public.template_quantity_suggestion,
  public.template_quick_action,
  public.template_item_alias,
  public.template_party_alias,
  public.template_expense_category,
  public.template_setting
to authenticated;

grant select, insert, update on
  public.template_application,
  public.template_pack_application
to authenticated;

alter table public.catalog_product_concept enable row level security;
alter table public.catalog_product_translation enable row level security;
alter table public.catalog_item enable row level security;
alter table public.catalog_item_revision enable row level security;
alter table public.catalog_item_unit enable row level security;
alter table public.catalog_item_alias enable row level security;
alter table public.template enable row level security;
alter table public.template_pack enable row level security;
alter table public.template_unit enable row level security;
alter table public.template_item enable row level security;
alter table public.template_item_unit enable row level security;
alter table public.template_supplier_type enable row level security;
alter table public.template_supplier_item enable row level security;
alter table public.template_quantity_suggestion enable row level security;
alter table public.template_quick_action enable row level security;
alter table public.template_item_alias enable row level security;
alter table public.template_party_alias enable row level security;
alter table public.template_expense_category enable row level security;
alter table public.template_setting enable row level security;
alter table public.template_application enable row level security;
alter table public.template_pack_application enable row level security;

create policy catalog_product_concept_select on public.catalog_product_concept for select using (is_active or public.auth_is_platform_staff(null));
create policy catalog_product_translation_select on public.catalog_product_translation for select using (true);
create policy catalog_item_select on public.catalog_item for select using (is_active or public.auth_is_platform_staff(null));
create policy catalog_item_revision_select on public.catalog_item_revision for select using (
  exists (
    select 1 from public.catalog_item ci
    where ci.id = catalog_item_id and (ci.is_active or public.auth_is_platform_staff(null))
  )
);
create policy catalog_item_unit_select on public.catalog_item_unit for select using (
  exists (
    select 1 from public.catalog_item ci
    where ci.id = catalog_item_id and (ci.is_active or public.auth_is_platform_staff(null))
  )
);
create policy catalog_item_alias_select on public.catalog_item_alias for select using (
  exists (
    select 1 from public.catalog_item ci
    where ci.id = catalog_item_id and (ci.is_active or public.auth_is_platform_staff(null))
  )
);
create policy template_select on public.template for select using (is_active or public.auth_is_platform_staff(null));
create policy template_child_select on public.template_pack for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_unit_select on public.template_unit for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_item_select on public.template_item for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_item_unit_select on public.template_item_unit for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_supplier_type_select on public.template_supplier_type for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_supplier_item_select on public.template_supplier_item for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_quantity_suggestion_select on public.template_quantity_suggestion for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_quick_action_select on public.template_quick_action for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_item_alias_select on public.template_item_alias for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_party_alias_select on public.template_party_alias for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_expense_category_select on public.template_expense_category for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);
create policy template_setting_select on public.template_setting for select using (
  exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
);

create policy catalog_product_concept_manage on public.catalog_product_concept for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy catalog_product_translation_manage on public.catalog_product_translation for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy catalog_item_manage on public.catalog_item for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy catalog_item_revision_manage on public.catalog_item_revision for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy catalog_item_unit_manage on public.catalog_item_unit for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy catalog_item_alias_manage on public.catalog_item_alias for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_manage on public.template for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_pack_manage on public.template_pack for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_unit_manage on public.template_unit for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_item_manage on public.template_item for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_item_unit_manage on public.template_item_unit for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_supplier_type_manage on public.template_supplier_type for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_supplier_item_manage on public.template_supplier_item for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_quantity_suggestion_manage on public.template_quantity_suggestion for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_quick_action_manage on public.template_quick_action for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_item_alias_manage on public.template_item_alias for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_party_alias_manage on public.template_party_alias for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_expense_category_manage on public.template_expense_category for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));
create policy template_setting_manage on public.template_setting for all using (public.auth_is_platform_staff('platform_admin')) with check (public.auth_is_platform_staff('platform_admin'));

create policy template_application_select
on public.template_application
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy template_application_insert
on public.template_application
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy template_application_update
on public.template_application
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));

create policy template_pack_application_select
on public.template_pack_application
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy template_pack_application_insert
on public.template_pack_application
for insert
with check (public.auth_can_manage_shop_setup(shop_id));

create policy template_pack_application_update
on public.template_pack_application
for update
using (public.auth_can_manage_shop_setup(shop_id))
with check (public.auth_can_manage_shop_setup(shop_id));
