-- Global catalog (platform-curated) + template definitions.
--
-- Major shape change from v1: catalog_item_revision + catalog_product_concept
-- are gone. Activation + line snapshots already provide all the
-- immutability we need (see docs/data-model-v2.md §1).
--
-- The "catalog_*" prefix is dropped — these tables are simply
--   item, item_unit, item_alias, item_barcode
-- alongside a new `category`. Names live in item_alias (is_display=true)
-- instead of a name column + translations sidecar.

-- ---------------------------------------------------------------------------
-- category
-- ---------------------------------------------------------------------------

create table public.category (
  id                 uuid primary key default extensions.gen_random_uuid(),
  code               text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  parent_id          uuid references public.category(id) on delete restrict,
  name               text not null check (length(btrim(name)) > 0),
  name_translations  jsonb not null default '{}'::jsonb,
  sort_order         integer not null default 0,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create trigger set_category_updated_at
before update on public.category
for each row execute function public.set_updated_at();

create index category_parent_sort_idx
  on public.category (parent_id, sort_order, name);

-- ---------------------------------------------------------------------------
-- item (global SKU, slim shape)
-- ---------------------------------------------------------------------------
--
-- No name on the row — display name lives in item_alias (is_display=true).
-- `code` is the human-readable slug for admin debugging.

create table public.item (
  id              uuid primary key default extensions.gen_random_uuid(),
  code            text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  category_id     uuid not null references public.category(id) on delete restrict,
  base_unit_code  text not null references public.unit(code) on delete restrict,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create trigger set_item_updated_at
before update on public.item
for each row execute function public.set_updated_at();

create index item_category_idx on public.item (category_id) where is_active;

-- ---------------------------------------------------------------------------
-- item_unit (global packagings of an item)
-- ---------------------------------------------------------------------------
--
-- Same unit_code can appear multiple times on one item with different
-- conversion_to_base (e.g., "bag" = 10 kg vs 25 kg vs 50 kg).
-- Uniqueness is on the triple (item_id, unit_code, conversion_to_base).
--
-- The base unit is identified by conversion_to_base = 1 — no is_base_unit
-- flag (see docs/data-model-v2.md §4.4). A partial unique index enforces
-- exactly one base-unit row per item.
--
-- Critique #3: is_active lets the platform retire a packaging without
-- deleting it (existing shop activations still reference the row).

create table public.item_unit (
  id                  uuid primary key default extensions.gen_random_uuid(),
  item_id             uuid not null references public.item(id) on delete cascade,
  unit_code           text not null references public.unit(code) on delete restrict,
  conversion_to_base  numeric(14, 6) not null check (conversion_to_base > 0),
  is_default_sale     boolean not null default false,
  is_default_receive  boolean not null default false,
  sort_order          integer not null default 0,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (item_id, unit_code, conversion_to_base)
);

create trigger set_item_unit_updated_at
before update on public.item_unit
for each row execute function public.set_updated_at();

-- Exactly one base-unit row per item (the conversion=1 row).
create unique index item_unit_single_base_idx
  on public.item_unit (item_id)
  where conversion_to_base = 1;

-- At most one default sale / receive packaging per item.
create unique index item_unit_default_sale_idx
  on public.item_unit (item_id)
  where is_default_sale;
create unique index item_unit_default_receive_idx
  on public.item_unit (item_id)
  where is_default_receive;

create index item_unit_item_sort_idx
  on public.item_unit (item_id, sort_order, unit_code);

-- Base-unit guard (critique #4 + design lock):
--   when conversion_to_base = 1, the unit_code MUST equal item.base_unit_code.
-- Catches silent drift between item.base_unit_code and its conversion=1
-- row that would otherwise corrupt stock math.
create or replace function public.check_item_unit_base_consistency()
returns trigger
language plpgsql
as $$
declare
  v_base_unit_code text;
begin
  if new.conversion_to_base = 1 then
    select base_unit_code into v_base_unit_code
    from public.item where id = new.item_id;
    if v_base_unit_code is null then
      raise exception
        'item_unit insert/update: referenced item % does not exist', new.item_id;
    end if;
    if new.unit_code <> v_base_unit_code then
      raise exception
        'item_unit base-unit guard: conversion=1 row must use item.base_unit_code (%) but got %',
        v_base_unit_code, new.unit_code;
    end if;
  end if;
  return new;
end;
$$;

create trigger check_item_unit_base_consistency_trg
before insert or update on public.item_unit
for each row execute function public.check_item_unit_base_consistency();

-- ---------------------------------------------------------------------------
-- item_alias (display name + search nicknames + translations, one table)
-- ---------------------------------------------------------------------------
--
-- `is_display = true` marks the official name in a given language.
-- All other rows are search variants (nicknames, abbreviations, OCR typos).
--
-- Critique #1: alias_text_norm is a generated column (lowercased + trimmed)
-- so "Bariis", "bariis", and " bariis " don't become three distinct rows.
-- Uniqueness and search index live on the normalized column.

create table public.item_alias (
  id             uuid primary key default extensions.gen_random_uuid(),
  item_id        uuid not null references public.item(id) on delete cascade,
  alias_text     text not null check (length(btrim(alias_text)) > 0),
  alias_text_norm text generated always as (lower(btrim(alias_text))) stored,
  language_code  text references public.language(code) on delete restrict,
  is_display     boolean not null default false,
  source         text not null default 'platform'
    check (source in ('platform', 'learned', 'ocr_correction')),
  weight         integer not null default 0,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (item_id, language_code, alias_text_norm)
);

create trigger set_item_alias_updated_at
before update on public.item_alias
for each row execute function public.set_updated_at();

-- At most one display alias per (item, language).
create unique index item_alias_display_idx
  on public.item_alias (item_id, language_code)
  where is_display;

-- Prefix search index on normalized text.
create index item_alias_norm_prefix_idx
  on public.item_alias (alias_text_norm text_pattern_ops)
  where is_active;

-- Trigram for fuzzy search if pg_trgm is available.
create index item_alias_norm_trgm_idx
  on public.item_alias using gin (alias_text_norm extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- item_barcode (per-packaging, many-to-one with item_unit)
-- ---------------------------------------------------------------------------
--
-- Barcodes are not globally unique (real-world collisions exist).
-- Soft index for scan lookups; admin tooling flags duplicates.

create table public.item_barcode (
  id            uuid primary key default extensions.gen_random_uuid(),
  item_unit_id  uuid not null references public.item_unit(id) on delete cascade,
  barcode       text not null check (length(btrim(barcode)) > 0),
  symbology     text,
  source        text not null default 'manufacturer'
    check (source in ('manufacturer', 'platform', 'learned')),
  is_primary    boolean not null default false,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (item_unit_id, barcode)
);

create trigger set_item_barcode_updated_at
before update on public.item_barcode
for each row execute function public.set_updated_at();

create unique index item_barcode_primary_idx
  on public.item_barcode (item_unit_id)
  where is_primary and is_active;

create index item_barcode_lookup_idx
  on public.item_barcode (barcode)
  where is_active;

-- ---------------------------------------------------------------------------
-- template + template_pack (unchanged shape; references reworked below)
-- ---------------------------------------------------------------------------

create table public.template (
  id               uuid primary key default extensions.gen_random_uuid(),
  code             text not null
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  kind             text not null default 'shop_starter',
  name             text not null check (length(btrim(name)) > 0),
  locale_default   text not null references public.language(code) on delete restrict,
  currency_default text not null references public.currency(code) on delete restrict,
  version          integer not null check (version > 0),
  is_active        boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (code, version),
  unique (id, version)
);

create trigger set_template_updated_at
before update on public.template
for each row execute function public.set_updated_at();

create table public.template_pack (
  id          uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  code        text not null
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  version     integer not null check (version > 0),
  is_required boolean not null default true,
  file_path   text not null,
  checksum    text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (template_id, code, version),
  unique (template_id, code)
);

create trigger set_template_pack_updated_at
before update on public.template_pack
for each row execute function public.set_updated_at();

create table public.template_unit (
  id          uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  unit_code   text not null references public.unit(code) on delete restrict,
  label       jsonb,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (template_id, unit_code)
);

create trigger set_template_unit_updated_at
before update on public.template_unit
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- template_item (now references global item directly — no revisions)
-- ---------------------------------------------------------------------------
--
-- Two valid configurations (enforced by the CHECK below):
--   (a) Reference an existing global item — catalog_item_id (renamed to
--       item_id) is set; overrides are optional starter-pack hints.
--   (b) Template-defined custom item — item_id is null; custom_name +
--       base_unit_code_override are required so apply_template can call
--       create_shop_item.

create table public.template_item (
  id                                  uuid primary key default extensions.gen_random_uuid(),
  template_id                         uuid not null references public.template(id) on delete cascade,
  item_code                           text not null
    check (item_code = lower(item_code) and item_code ~ '^[a-z][a-z0-9_]*$'),
  item_id                             uuid references public.item(id) on delete restrict,
  custom_name                         text check (custom_name is null or length(btrim(custom_name)) > 0),
  base_unit_code_override             text references public.unit(code) on delete restrict,
  default_sale_unit_code_override     text references public.unit(code) on delete restrict,
  default_receive_unit_code_override  text references public.unit(code) on delete restrict,
  suggested_sale_price                numeric(14, 2) check (suggested_sale_price is null or suggested_sale_price >= 0),
  reorder_threshold                   numeric(14, 3) check (reorder_threshold is null or reorder_threshold >= 0),
  sort_order                          integer not null default 0,
  created_at                          timestamptz not null default now(),
  updated_at                          timestamptz not null default now(),
  unique (template_id, item_code),
  -- Either an existing global item (item_id set), or a fully-described
  -- template-local item (custom_name + base unit required). Comment
  -- per critique #6.
  check (
    item_id is not null
    or (custom_name is not null and base_unit_code_override is not null)
  )
);

create trigger set_template_item_updated_at
before update on public.template_item
for each row execute function public.set_updated_at();

create table public.template_item_unit (
  id                  uuid primary key default extensions.gen_random_uuid(),
  template_id         uuid not null,
  item_code           text not null,
  unit_code           text not null references public.unit(code) on delete restrict,
  conversion_to_base  numeric(14, 6) not null check (conversion_to_base > 0),
  sort_order          integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (template_id, item_code, unit_code, conversion_to_base),
  foreign key (template_id, item_code) references public.template_item(template_id, item_code) on delete cascade
);

create trigger set_template_item_unit_updated_at
before update on public.template_item_unit
for each row execute function public.set_updated_at();

create table public.template_supplier_type (
  id                  uuid primary key default extensions.gen_random_uuid(),
  template_id         uuid not null references public.template(id) on delete cascade,
  supplier_type_code  text not null
    check (supplier_type_code = lower(supplier_type_code) and supplier_type_code ~ '^[a-z][a-z0-9_]*$'),
  label               jsonb,
  sort_order          integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (template_id, supplier_type_code)
);

create trigger set_template_supplier_type_updated_at
before update on public.template_supplier_type
for each row execute function public.set_updated_at();

create table public.template_supplier_item (
  id                  uuid primary key default extensions.gen_random_uuid(),
  template_id         uuid not null,
  supplier_type_code  text not null,
  item_code           text not null,
  usual_unit_code     text references public.unit(code) on delete restrict,
  cost_entry_mode     text check (cost_entry_mode in ('unit_cost', 'line_total')),
  sort_order          integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (template_id, supplier_type_code, item_code),
  foreign key (template_id, supplier_type_code) references public.template_supplier_type(template_id, supplier_type_code) on delete cascade,
  foreign key (template_id, item_code) references public.template_item(template_id, item_code) on delete cascade
);

create trigger set_template_supplier_item_updated_at
before update on public.template_supplier_item
for each row execute function public.set_updated_at();

create table public.template_quantity_suggestion (
  id            uuid primary key default extensions.gen_random_uuid(),
  template_id   uuid not null references public.template(id) on delete cascade,
  item_code     text,
  category_code text,
  context       text not null check (context in ('sale', 'receive')),
  quantity      numeric(14, 3) not null check (quantity > 0),
  unit_code     text not null references public.unit(code) on delete restrict,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- Suggestion targets either a specific item OR a whole category — at
  -- least one must be set. Comment per critique #6.
  check (item_code is not null or category_code is not null)
);

create trigger set_template_quantity_suggestion_updated_at
before update on public.template_quantity_suggestion
for each row execute function public.set_updated_at();

create table public.template_quick_action (
  id                    uuid primary key default extensions.gen_random_uuid(),
  template_id           uuid not null references public.template(id) on delete cascade,
  screen                text not null check (screen in ('sale', 'receive', 'expense')),
  position              integer not null check (position > 0),
  item_code             text,
  expense_category_code text,
  label                 jsonb,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (template_id, screen, position),
  -- A quick-action button targets either an item or an expense
  -- category, or it's a labeled placeholder. At least one identifying
  -- field must be present. Comment per critique #6.
  check (item_code is not null or expense_category_code is not null or label is not null)
);

create trigger set_template_quick_action_updated_at
before update on public.template_quick_action
for each row execute function public.set_updated_at();

create table public.template_item_alias (
  id              uuid primary key default extensions.gen_random_uuid(),
  template_id     uuid not null,
  item_code       text not null,
  language_code   text references public.language(code) on delete restrict,
  alias_text      text not null check (length(btrim(alias_text)) > 0),
  alias_text_norm text generated always as (lower(btrim(alias_text))) stored,
  source          text not null default 'template',
  is_display      boolean not null default false,
  weight          integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (template_id, item_code, language_code, alias_text_norm),
  foreign key (template_id, item_code) references public.template_item(template_id, item_code) on delete cascade
);

create trigger set_template_item_alias_updated_at
before update on public.template_item_alias
for each row execute function public.set_updated_at();

create unique index template_item_alias_display_idx
  on public.template_item_alias (template_id, item_code, language_code)
  where is_display;

create table public.template_party_alias (
  id              uuid primary key default extensions.gen_random_uuid(),
  template_id     uuid not null references public.template(id) on delete cascade,
  party_code      text not null
    check (party_code = lower(party_code) and party_code ~ '^[a-z][a-z0-9_]*$'),
  language_code   text references public.language(code) on delete restrict,
  alias_text      text not null check (length(btrim(alias_text)) > 0),
  alias_text_norm text generated always as (lower(btrim(alias_text))) stored,
  source          text not null default 'template',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (template_id, party_code, language_code, alias_text_norm)
);

create trigger set_template_party_alias_updated_at
before update on public.template_party_alias
for each row execute function public.set_updated_at();

create table public.template_expense_category (
  id                uuid primary key default extensions.gen_random_uuid(),
  template_id       uuid not null references public.template(id) on delete cascade,
  code              text not null
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  name              text not null check (length(btrim(name)) > 0),
  name_translations jsonb,
  sort_order        integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (template_id, code)
);

create trigger set_template_expense_category_updated_at
before update on public.template_expense_category
for each row execute function public.set_updated_at();

create table public.template_setting (
  id          uuid primary key default extensions.gen_random_uuid(),
  template_id uuid not null references public.template(id) on delete cascade,
  key         text not null
    check (key = lower(key) and key ~ '^[a-z][a-z0-9_]*$'),
  value       jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (template_id, key)
);

create trigger set_template_setting_updated_at
before update on public.template_setting
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- template_application + template_pack_application (unchanged)
-- ---------------------------------------------------------------------------

create table public.template_application (
  id                 uuid primary key default extensions.gen_random_uuid(),
  shop_id            uuid not null references public.shop(id) on delete cascade,
  template_id        uuid not null references public.template(id) on delete restrict,
  template_version   integer not null check (template_version > 0),
  applied_by         uuid references auth.users(id) on delete set null,
  applied_at         timestamptz not null default now(),
  merge_strategy     text not null check (merge_strategy in ('first_apply', 'merge_update')),
  status             text not null default 'applied' check (status in ('applying', 'applied', 'failed')),
  unique (shop_id, template_id, template_version),
  unique (shop_id, id),
  foreign key (template_id, template_version) references public.template(id, version) on delete restrict
);

create table public.template_pack_application (
  id                       uuid primary key default extensions.gen_random_uuid(),
  shop_id                  uuid not null,
  template_application_id  uuid not null,
  pack_code                text not null,
  pack_version             integer not null check (pack_version > 0),
  applied_at               timestamptz not null default now(),
  status                   text not null check (status in ('applied', 'skipped', 'failed')),
  unique (template_application_id, pack_code),
  unique (shop_id, id),
  foreign key (shop_id, template_application_id) references public.template_application(shop_id, id) on delete cascade
);

create index template_item_template_id_sort_order_idx
  on public.template_item (template_id, sort_order);
create index template_quantity_suggestion_template_context_idx
  on public.template_quantity_suggestion (template_id, context, sort_order);
create index template_application_shop_id_applied_at_idx
  on public.template_application (shop_id, applied_at desc);

-- ---------------------------------------------------------------------------
-- Grants + RLS
-- ---------------------------------------------------------------------------

grant select on
  public.category,
  public.item,
  public.item_unit,
  public.item_alias,
  public.item_barcode,
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

-- Global catalog writes restricted to platform staff. Convention only —
-- service role bypasses RLS; admin portal MUST go through the same
-- policies (see docs/data-model-v2.md §7 sanctioned-writers rule).
grant insert, update on
  public.category,
  public.item,
  public.item_unit,
  public.item_alias,
  public.item_barcode,
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

alter table public.category enable row level security;
alter table public.item enable row level security;
alter table public.item_unit enable row level security;
alter table public.item_alias enable row level security;
alter table public.item_barcode enable row level security;
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

create policy category_select on public.category
  for select using (is_active or public.auth_is_platform_staff(null));
create policy item_select on public.item
  for select using (is_active or public.auth_is_platform_staff(null));
create policy item_unit_select on public.item_unit
  for select using (
    exists (
      select 1 from public.item i
      where i.id = item_id and (i.is_active or public.auth_is_platform_staff(null))
    )
  );
create policy item_alias_select on public.item_alias
  for select using (
    exists (
      select 1 from public.item i
      where i.id = item_id and (i.is_active or public.auth_is_platform_staff(null))
    )
  );
create policy item_barcode_select on public.item_barcode
  for select using (
    exists (
      select 1
      from public.item_unit iu
      join public.item i on i.id = iu.item_id
      where iu.id = item_unit_id and (i.is_active or public.auth_is_platform_staff(null))
    )
  );

create policy template_select on public.template
  for select using (is_active or public.auth_is_platform_staff(null));
create policy template_pack_select on public.template_pack
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_unit_select on public.template_unit
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_item_select on public.template_item
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_item_unit_select on public.template_item_unit
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_supplier_type_select on public.template_supplier_type
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_supplier_item_select on public.template_supplier_item
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_quantity_suggestion_select on public.template_quantity_suggestion
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_quick_action_select on public.template_quick_action
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_item_alias_select on public.template_item_alias
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_party_alias_select on public.template_party_alias
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_expense_category_select on public.template_expense_category
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );
create policy template_setting_select on public.template_setting
  for select using (
    exists (select 1 from public.template t where t.id = template_id and (t.is_active or public.auth_is_platform_staff(null)))
  );

create policy category_manage on public.category
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy item_manage on public.item
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy item_unit_manage on public.item_unit
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy item_alias_manage on public.item_alias
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy item_barcode_manage on public.item_barcode
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));

create policy template_manage on public.template
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_pack_manage on public.template_pack
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_unit_manage on public.template_unit
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_item_manage on public.template_item
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_item_unit_manage on public.template_item_unit
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_supplier_type_manage on public.template_supplier_type
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_supplier_item_manage on public.template_supplier_item
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_quantity_suggestion_manage on public.template_quantity_suggestion
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_quick_action_manage on public.template_quick_action
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_item_alias_manage on public.template_item_alias
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_party_alias_manage on public.template_party_alias
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_expense_category_manage on public.template_expense_category
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));
create policy template_setting_manage on public.template_setting
  for all using (public.auth_is_platform_staff('platform_admin'))
  with check (public.auth_is_platform_staff('platform_admin'));

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
