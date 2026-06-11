-- Shop overlay: per-shop projection of the global catalog plus
-- per-shop entities (parties, supplier_type).
--
-- Renamed from the pre-v2 layout:
--   item        → shop_item        (snapshot pattern; see data-model-v2 §5.1)
--   item_unit   → shop_item_unit   (snapshot pattern; see §5.2)
--   item_alias  → shop_item_alias  (covers override + learning; §5.3)
--
-- New in v2:
--   shop_item_barcode         (shop-printed labels; §5.4)
--   supplier_item_unit_cost   (per-supplier per-packaging last cost; §5.5)

-- ---------------------------------------------------------------------------
-- shop_item
-- ---------------------------------------------------------------------------
--
-- A shop_item is one row per item the shop carries. Three shapes:
--   (1) activated from the global catalog: item_id set
--   (2) shop-only (cashier added it):      item_id null
--
-- Structural fields (base_unit_code, category_id) are SNAPSHOTTED at
-- activation/creation; they don't live-reference the global row. See
-- critique #4 in data-model-v2.md.
--
-- Display name lives in shop_item_alias (is_display=true), with a
-- fallback chain to global item_alias.

create table public.shop_item (
  id                   uuid primary key default extensions.gen_random_uuid(),
  shop_id              uuid not null references public.shop(id) on delete cascade,

  -- provenance (informational): null = shop-only, not-null = activated
  item_id              uuid references public.item(id) on delete restrict,

  -- structural snapshot (always set; copied from global at activation)
  base_unit_code       text not null references public.unit(code) on delete restrict,
  category_id          uuid references public.category(id) on delete restrict,

  -- inventory state (written only by posting / adjustment RPCs)
  current_stock        numeric(14, 3) not null default 0,
  avg_cost             numeric(14, 4) not null default 0 check (avg_cost >= 0),
  reorder_threshold    numeric(14, 3) check (reorder_threshold is null or reorder_threshold >= 0),

  is_active            boolean not null default true,
  created_by           uuid references auth.users(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (shop_id, id),
  -- One activation per global item per shop. Shop-only rows skip this
  -- via the partial index `where item_id is not null`.
  constraint shop_item_unique_activation unique (shop_id, item_id)
);

create trigger set_shop_item_updated_at
before update on public.shop_item
for each row execute function public.set_updated_at();

comment on column public.shop_item.current_stock is
  'Cached projection in base units. Writers: post_sale, post_receive, void_sale, void_receive, inventory_adjustment. Negative values allowed (warning toast at posting time).';
comment on column public.shop_item.avg_cost is
  'Weighted-average per base unit. Writers: post_receive, void_receive, inventory_adjustment. Sale COGS snapshot reads this at posting time.';
comment on column public.shop_item.reorder_threshold is
  'Stored in base units. UI displays in the shop''s default sale packaging.';

-- ---------------------------------------------------------------------------
-- shop_item_unit
-- ---------------------------------------------------------------------------
--
-- One row per packaging the shop uses. Structural fields (unit_code,
-- conversion_to_base) are SNAPSHOTTED at activation/creation —
-- platform-side changes to the global item_unit don't retroactively
-- alter the shop's stock math. is_default_sale/is_default_receive are
-- initialized from the global flags at activation but the shop owns
-- them after that (critique #5).

create table public.shop_item_unit (
  id                   uuid primary key default extensions.gen_random_uuid(),
  shop_id              uuid not null references public.shop(id) on delete cascade,
  shop_item_id         uuid not null,

  -- provenance (informational): null = shop-only packaging
  item_unit_id         uuid references public.item_unit(id) on delete restrict,

  -- structural snapshot
  unit_code            text not null references public.unit(code) on delete restrict,
  conversion_to_base   numeric(14, 6) not null check (conversion_to_base > 0),

  -- money (cashier-facing, mutable via posting/price RPCs)
  sale_price           numeric(14, 2) check (sale_price is null or sale_price >= 0),
  last_cost            numeric(14, 4) check (last_cost is null or last_cost >= 0),

  -- shop-owned defaults
  is_default_sale      boolean not null default false,
  is_default_receive   boolean not null default false,

  sort_order           integer not null default 0,
  is_active            boolean not null default true,
  created_by           uuid references auth.users(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (shop_id, id),
  foreign key (shop_id, shop_item_id) references public.shop_item(shop_id, id) on delete cascade
);

create trigger set_shop_item_unit_updated_at
before update on public.shop_item_unit
for each row execute function public.set_updated_at();

-- One row per (shop_item, packaging) when activated from the global
-- catalog. Shop-only rows (item_unit_id null) can coexist freely.
create unique index shop_item_unit_activation_idx
  on public.shop_item_unit (shop_id, shop_item_id, item_unit_id)
  where item_unit_id is not null;

-- Exactly one base-unit row per shop_item.
create unique index shop_item_unit_base_idx
  on public.shop_item_unit (shop_id, shop_item_id)
  where conversion_to_base = 1;

-- At most one default sale / receive packaging per shop_item.
create unique index shop_item_unit_default_sale_idx
  on public.shop_item_unit (shop_id, shop_item_id)
  where is_default_sale;
create unique index shop_item_unit_default_receive_idx
  on public.shop_item_unit (shop_id, shop_item_id)
  where is_default_receive;

create index shop_item_unit_shop_item_sort_idx
  on public.shop_item_unit (shop_id, shop_item_id, sort_order, unit_code);

-- Base-unit guard (mirrors the one on global item_unit; critique #4).
-- The conversion=1 row's unit_code MUST equal shop_item.base_unit_code.
create or replace function public.check_shop_item_unit_base_consistency()
returns trigger
language plpgsql
as $$
declare
  v_base_unit_code text;
begin
  if new.conversion_to_base = 1 then
    select base_unit_code into v_base_unit_code
    from public.shop_item
    where id = new.shop_item_id and shop_id = new.shop_id;
    if v_base_unit_code is null then
      raise exception
        'shop_item_unit insert/update: referenced shop_item % not found in shop %',
        new.shop_item_id, new.shop_id;
    end if;
    if new.unit_code <> v_base_unit_code then
      raise exception
        'shop_item_unit base-unit guard: conversion=1 row must use shop_item.base_unit_code (%) but got %',
        v_base_unit_code, new.unit_code;
    end if;
  end if;
  return new;
end;
$$;

create trigger check_shop_item_unit_base_consistency_trg
before insert or update on public.shop_item_unit
for each row execute function public.check_shop_item_unit_base_consistency();

comment on column public.shop_item_unit.sale_price is
  'NULL is meaningful: cashier has not priced this packaging yet; priceRequired editor fires on first use. Writers: post_sale (cashier override), set_shop_item_unit_sale_price.';
comment on column public.shop_item_unit.last_cost is
  'Per-packaging unit cost from the most recent receive. NULL = no receive yet. Writers: post_receive, void_receive.';

-- ---------------------------------------------------------------------------
-- shop_item_alias
-- ---------------------------------------------------------------------------
--
-- Display-name overrides + shop-learned search variants. The alias
-- chain (critique #1 + §8.1): shop_item_alias > item_alias, locale
-- match > any-language. alias_text_norm is a generated column so the
-- uniqueness constraint and prefix index are case + whitespace-insensitive.

create table public.shop_item_alias (
  id              uuid primary key default extensions.gen_random_uuid(),
  shop_id         uuid not null references public.shop(id) on delete cascade,
  shop_item_id    uuid not null,
  alias_text      text not null check (length(btrim(alias_text)) > 0),
  alias_text_norm text generated always as (lower(btrim(alias_text))) stored,
  language_code   text references public.language(code) on delete restrict,
  is_display      boolean not null default false,
  source          text not null default 'manual'
    check (source in ('manual', 'ocr_correction', 'learned')),
  weight          integer not null default 0,
  is_active       boolean not null default true,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (shop_id, id),
  unique (shop_id, shop_item_id, language_code, alias_text_norm),
  foreign key (shop_id, shop_item_id) references public.shop_item(shop_id, id) on delete cascade
);

create trigger set_shop_item_alias_updated_at
before update on public.shop_item_alias
for each row execute function public.set_updated_at();

create unique index shop_item_alias_display_idx
  on public.shop_item_alias (shop_id, shop_item_id, language_code)
  where is_display;

create index shop_item_alias_norm_prefix_idx
  on public.shop_item_alias (shop_id, alias_text_norm text_pattern_ops)
  where is_active;

create index shop_item_alias_norm_trgm_idx
  on public.shop_item_alias using gin (alias_text_norm extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- shop_item_barcode
-- ---------------------------------------------------------------------------
--
-- Per-shop printed labels (repacks, custom packs). Scan lookup walks
-- shop_item_barcode first, then global item_barcode. Soft (non-unique)
-- index on barcode for fast scans.

create table public.shop_item_barcode (
  id                  uuid primary key default extensions.gen_random_uuid(),
  shop_id             uuid not null references public.shop(id) on delete cascade,
  shop_item_unit_id   uuid not null,
  barcode             text not null check (length(btrim(barcode)) > 0),
  symbology           text,
  is_primary          boolean not null default false,
  is_active           boolean not null default true,
  created_by          uuid references auth.users(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (shop_id, id),
  unique (shop_id, shop_item_unit_id, barcode),
  foreign key (shop_id, shop_item_unit_id) references public.shop_item_unit(shop_id, id) on delete cascade
);

create trigger set_shop_item_barcode_updated_at
before update on public.shop_item_barcode
for each row execute function public.set_updated_at();

create unique index shop_item_barcode_primary_idx
  on public.shop_item_barcode (shop_id, shop_item_unit_id)
  where is_primary and is_active;

create index shop_item_barcode_lookup_idx
  on public.shop_item_barcode (shop_id, barcode)
  where is_active;

-- ---------------------------------------------------------------------------
-- supplier_item_unit_cost
-- ---------------------------------------------------------------------------
--
-- Replaces the old `learned_supplier_item_cost` (which was keyed on
-- item). Now keyed on the packaging — suppliers deliver in bags /
-- cartons, not abstract base units, so per-packaging is the right
-- granularity. Drives Receive screen pre-fill when the supplier is
-- known.

create table public.supplier_item_unit_cost (
  id                  uuid primary key default extensions.gen_random_uuid(),
  shop_id             uuid not null references public.shop(id) on delete cascade,
  party_id            uuid not null,
  shop_item_unit_id   uuid not null,
  last_unit_cost      numeric(14, 4) check (last_unit_cost is null or last_unit_cost >= 0),
  last_received_at    timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (shop_id, id),
  unique (shop_id, party_id, shop_item_unit_id),
  foreign key (shop_id, shop_item_unit_id)
    references public.shop_item_unit(shop_id, id) on delete cascade
  -- party_id FK is added below after party table is created.
);

create trigger set_supplier_item_unit_cost_updated_at
before update on public.supplier_item_unit_cost
for each row execute function public.set_updated_at();

create index supplier_item_unit_cost_lookup_idx
  on public.supplier_item_unit_cost
  (shop_id, shop_item_unit_id, last_received_at desc);

comment on column public.supplier_item_unit_cost.last_unit_cost is
  'Per-packaging unit cost from this supplier''s most recent receive. Writers: post_receive, void_receive.';

-- ---------------------------------------------------------------------------
-- supplier_type, party, party_alias
-- ---------------------------------------------------------------------------

create table public.supplier_type (
  id              uuid primary key default extensions.gen_random_uuid(),
  shop_id         uuid not null references public.shop(id) on delete cascade,
  code            text not null
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  label           text not null check (length(btrim(label)) > 0),
  label_translations jsonb not null default '{}'::jsonb,
  sort_order      integer not null default 0,
  is_active       boolean not null default true,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (shop_id, code),
  unique (shop_id, id)
);

create trigger set_supplier_type_updated_at
before update on public.supplier_type
for each row execute function public.set_updated_at();

create table public.party (
  id                uuid primary key default extensions.gen_random_uuid(),
  shop_id           uuid not null references public.shop(id) on delete cascade,
  name              text not null check (length(btrim(name)) > 0),
  phone             text,
  type_id           uuid not null references public.party_type(id) on delete restrict,
  supplier_type_id  uuid,
  receivable        numeric(14, 2) not null default 0 check (receivable >= 0),
  payable           numeric(14, 2) not null default 0 check (payable >= 0),
  notes             text,
  is_active         boolean not null default true,
  created_by        uuid references auth.users(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (shop_id, id),
  foreign key (shop_id, supplier_type_id)
    references public.supplier_type(shop_id, id) on delete set null
);

create trigger set_party_updated_at
before update on public.party
for each row execute function public.set_updated_at();

-- Now that party exists, complete the supplier_item_unit_cost composite FK.
alter table public.supplier_item_unit_cost
  add constraint supplier_item_unit_cost_party_fk
  foreign key (shop_id, party_id)
  references public.party(shop_id, id) on delete cascade;

create table public.party_alias (
  id              uuid primary key default extensions.gen_random_uuid(),
  shop_id         uuid not null references public.shop(id) on delete cascade,
  party_id        uuid not null,
  alias_text      text not null check (length(btrim(alias_text)) > 0),
  alias_text_norm text generated always as (lower(btrim(alias_text))) stored,
  language_code   text references public.language(code) on delete restrict,
  source          text not null
    check (source in ('template', 'manual', 'ocr_correction', 'learned')),
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (shop_id, id),
  unique (shop_id, party_id, language_code, alias_text_norm),
  foreign key (shop_id, party_id)
    references public.party(shop_id, id) on delete cascade
);

create trigger set_party_alias_updated_at
before update on public.party_alias
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index shop_item_shop_active_idx
  on public.shop_item (shop_id, is_active);
create index shop_item_item_id_idx
  on public.shop_item (item_id) where item_id is not null;
create index shop_item_category_idx
  on public.shop_item (shop_id, category_id) where is_active;

create index supplier_type_shop_id_active_idx
  on public.supplier_type (shop_id, is_active, sort_order);
create index party_shop_id_type_id_active_idx
  on public.party (shop_id, type_id, is_active);
create index party_alias_norm_prefix_idx
  on public.party_alias (shop_id, alias_text_norm text_pattern_ops);
create index party_alias_norm_trgm_idx
  on public.party_alias using gin (alias_text_norm extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Grants + RLS
-- ---------------------------------------------------------------------------
--
-- All shop-overlay tables: shop members + platform staff can SELECT;
-- direct table writes restricted to setup-managers. Posting RPCs use
-- SECURITY DEFINER and check auth_can_post_shop so cashiers can create
-- party / shop_item / shop_item_unit via RPC without table-level INSERT.

grant select, insert, update on
  public.shop_item,
  public.shop_item_unit,
  public.shop_item_alias,
  public.shop_item_barcode,
  public.supplier_item_unit_cost,
  public.supplier_type,
  public.party,
  public.party_alias
to authenticated;

alter table public.shop_item enable row level security;
alter table public.shop_item_unit enable row level security;
alter table public.shop_item_alias enable row level security;
alter table public.shop_item_barcode enable row level security;
alter table public.supplier_item_unit_cost enable row level security;
alter table public.supplier_type enable row level security;
alter table public.party enable row level security;
alter table public.party_alias enable row level security;

create policy shop_item_select on public.shop_item
  for select using (public.auth_can_access_shop(shop_id) or public.auth_is_platform_staff(null));
create policy shop_item_insert on public.shop_item
  for insert with check (public.auth_can_manage_shop_setup(shop_id));
create policy shop_item_update on public.shop_item
  for update using (public.auth_can_manage_shop_setup(shop_id))
  with check (public.auth_can_manage_shop_setup(shop_id));

create policy shop_item_unit_select on public.shop_item_unit
  for select using (public.auth_can_access_shop(shop_id) or public.auth_is_platform_staff(null));
create policy shop_item_unit_insert on public.shop_item_unit
  for insert with check (public.auth_can_manage_shop_setup(shop_id));
create policy shop_item_unit_update on public.shop_item_unit
  for update using (public.auth_can_manage_shop_setup(shop_id))
  with check (public.auth_can_manage_shop_setup(shop_id));

create policy shop_item_alias_select on public.shop_item_alias
  for select using (public.auth_can_access_shop(shop_id) or public.auth_is_platform_staff(null));
create policy shop_item_alias_insert on public.shop_item_alias
  for insert with check (public.auth_can_manage_shop_setup(shop_id));
create policy shop_item_alias_update on public.shop_item_alias
  for update using (public.auth_can_manage_shop_setup(shop_id))
  with check (public.auth_can_manage_shop_setup(shop_id));

create policy shop_item_barcode_select on public.shop_item_barcode
  for select using (public.auth_can_access_shop(shop_id) or public.auth_is_platform_staff(null));
create policy shop_item_barcode_insert on public.shop_item_barcode
  for insert with check (public.auth_can_manage_shop_setup(shop_id));
create policy shop_item_barcode_update on public.shop_item_barcode
  for update using (public.auth_can_manage_shop_setup(shop_id))
  with check (public.auth_can_manage_shop_setup(shop_id));

create policy supplier_item_unit_cost_select on public.supplier_item_unit_cost
  for select using (public.auth_can_access_shop(shop_id) or public.auth_is_platform_staff(null));
create policy supplier_item_unit_cost_insert on public.supplier_item_unit_cost
  for insert with check (public.auth_can_manage_shop_setup(shop_id));
create policy supplier_item_unit_cost_update on public.supplier_item_unit_cost
  for update using (public.auth_can_manage_shop_setup(shop_id))
  with check (public.auth_can_manage_shop_setup(shop_id));

create policy supplier_type_select on public.supplier_type
  for select using (public.auth_can_access_shop(shop_id) or public.auth_is_platform_staff(null));
create policy supplier_type_insert on public.supplier_type
  for insert with check (public.auth_can_manage_shop_setup(shop_id));
create policy supplier_type_update on public.supplier_type
  for update using (public.auth_can_manage_shop_setup(shop_id))
  with check (public.auth_can_manage_shop_setup(shop_id));

create policy party_select on public.party
  for select using (public.auth_can_access_shop(shop_id) or public.auth_is_platform_staff(null));
create policy party_insert on public.party
  for insert with check (public.auth_can_manage_shop_setup(shop_id));
create policy party_update on public.party
  for update using (public.auth_can_manage_shop_setup(shop_id))
  with check (public.auth_can_manage_shop_setup(shop_id));

create policy party_alias_select on public.party_alias
  for select using (public.auth_can_access_shop(shop_id) or public.auth_is_platform_staff(null));
create policy party_alias_insert on public.party_alias
  for insert with check (public.auth_can_manage_shop_setup(shop_id));
create policy party_alias_update on public.party_alias
  for update using (public.auth_can_manage_shop_setup(shop_id))
  with check (public.auth_can_manage_shop_setup(shop_id));
