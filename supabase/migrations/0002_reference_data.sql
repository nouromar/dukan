-- Reference data (global, platform-curated).
--
-- Translations are stored inline as jsonb on each table that has a
-- user-facing label. The polymorphic ref_translation table that lived
-- here previously has been removed (data-model-v2 §3 + §6) — jsonb
-- columns are type-safer per entity, cheaper to query, and don't
-- accumulate item rows alongside reference rows.
--
-- The companion helper `public.tr(fallback, translations, locale)`
-- resolves a translation with a sensible fallback chain
--   locale → 'en' → fallback
-- so call sites stay one line.

create table public.language (
  code text primary key
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  name text not null,
  name_translations jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_language_updated_at
before update on public.language
for each row execute function public.set_updated_at();

create table public.currency (
  code text primary key
    check (code = upper(code) and code ~ '^[A-Z][A-Z0-9_]*$'),
  symbol text not null,
  decimals integer not null default 2 check (decimals between 0 and 4),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_currency_updated_at
before update on public.currency
for each row execute function public.set_updated_at();

create table public.unit (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  default_label text not null,
  label_translations jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_unit_updated_at
before update on public.unit
for each row execute function public.set_updated_at();

create table public.transaction_type (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  label text not null,
  label_translations jsonb not null default '{}'::jsonb,
  stock_effect integer not null check (stock_effect in (-1, 0, 1)),
  party_balance_effect text not null
    check (party_balance_effect in ('none', 'receivable', 'payable')),
  requires_party boolean not null default false,
  requires_items boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_transaction_type_updated_at
before update on public.transaction_type
for each row execute function public.set_updated_at();

create table public.transaction_status (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  label text not null,
  label_translations jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_transaction_status_updated_at
before update on public.transaction_status
for each row execute function public.set_updated_at();

create table public.payment_method (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  label text not null,
  label_translations jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_payment_method_updated_at
before update on public.payment_method
for each row execute function public.set_updated_at();

create table public.party_type (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  label text not null,
  label_translations jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_party_type_updated_at
before update on public.party_type
for each row execute function public.set_updated_at();

create table public.document_type (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  label text not null,
  label_translations jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_document_type_updated_at
before update on public.document_type
for each row execute function public.set_updated_at();

create table public.ocr_status (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_ocr_status_updated_at
before update on public.ocr_status
for each row execute function public.set_updated_at();

create table public.organization_role (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  label text not null,
  label_translations jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_organization_role_updated_at
before update on public.organization_role
for each row execute function public.set_updated_at();

create table public.shop_role (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  label text not null,
  label_translations jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_shop_role_updated_at
before update on public.shop_role
for each row execute function public.set_updated_at();

create table public.adjustment_reason (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  label text not null,
  label_translations jsonb not null default '{}'::jsonb,
  is_increase boolean,
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_adjustment_reason_updated_at
before update on public.adjustment_reason
for each row execute function public.set_updated_at();

create table public.location_kind (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_location_kind_updated_at
before update on public.location_kind
for each row execute function public.set_updated_at();

-- Translation resolver. Picks the locale-specific value from the
-- jsonb, falls back to English, then to the supplied fallback (usually
-- the row's canonical label column). Immutable so it can be used in
-- generated columns / functional indexes later if needed.
create or replace function public.tr(
  fallback text,
  translations jsonb,
  locale text
)
returns text
language sql
immutable
parallel safe
as $$
  select coalesce(
    nullif(translations ->> locale, ''),
    nullif(translations ->> 'en', ''),
    fallback
  )
$$;

-- Seed data --------------------------------------------------------------

insert into public.language (code, name, name_translations, is_active) values
  ('en', 'English', '{"en": "English", "so": "Ingiriis"}'::jsonb, true),
  ('so', 'Somali',  '{"en": "Somali",  "so": "Soomaali"}'::jsonb, true)
on conflict (code) do update set
  name = excluded.name,
  name_translations = excluded.name_translations,
  is_active = excluded.is_active;

insert into public.currency (code, symbol, decimals, is_active) values
  ('USD',  '$',    2, true),
  ('SLSH', 'SLSH', 0, true)
on conflict (code) do update set
  symbol = excluded.symbol,
  decimals = excluded.decimals,
  is_active = excluded.is_active;

insert into public.unit (code, default_label, label_translations, is_active) values
  ('piece',  'Piece',  '{"so": "Mid"}'::jsonb,         true),
  ('bag',    'Bag',    '{"so": "Jaakad"}'::jsonb,      true),
  ('carton', 'Carton', '{"so": "Kaartoon"}'::jsonb,    true),
  ('box',    'Box',    '{"so": "Sanduuq"}'::jsonb,     true),
  ('bottle', 'Bottle', '{"so": "Dhalo"}'::jsonb,       true),
  ('packet', 'Packet', '{"so": "Baakad"}'::jsonb,      true),
  ('sack',   'Sack',   '{"so": "Kiis"}'::jsonb,        true),
  ('kg',     'Kg',     '{"so": "Kiilo"}'::jsonb,       true),
  ('gram',   'Gram',   '{"so": "Garaam"}'::jsonb,      true),
  ('litre',  'Litre',  '{"so": "Liitir"}'::jsonb,      true),
  ('ml',     'ml',     '{"so": "ml"}'::jsonb,          true),
  ('dozen',  'Dozen',  '{"so": "Dejen"}'::jsonb,       true)
on conflict (code) do update set
  default_label = excluded.default_label,
  label_translations = excluded.label_translations,
  is_active = excluded.is_active;

insert into public.transaction_type (
  code, label, label_translations,
  stock_effect, party_balance_effect, requires_party, requires_items, is_active
) values
  ('sale',    'Sale',    '{"so": "Iibin"}'::jsonb,        -1, 'receivable', false, true,  true),
  ('receive', 'Receive', '{"so": "Alaab dajin"}'::jsonb,   1, 'payable',    true,  true,  true),
  ('expense', 'Expense', '{"so": "Qarashaad"}'::jsonb,     0, 'none',       false, false, true)
on conflict (code) do update set
  label = excluded.label,
  label_translations = excluded.label_translations,
  stock_effect = excluded.stock_effect,
  party_balance_effect = excluded.party_balance_effect,
  requires_party = excluded.requires_party,
  requires_items = excluded.requires_items,
  is_active = excluded.is_active;

insert into public.transaction_status (code, label, label_translations, is_active) values
  ('draft',  'Draft',  '{"so": "Qabyo"}'::jsonb,    true),
  ('posted', 'Posted', '{"so": "La keydiyay"}'::jsonb, true),
  ('void',   'Void',   '{"so": "Tirtiran"}'::jsonb, true)
on conflict (code) do update set
  label = excluded.label,
  label_translations = excluded.label_translations,
  is_active = excluded.is_active;

insert into public.payment_method (code, label, label_translations, is_active) values
  ('cash',         'Cash',         '{"so": "Kaash"}'::jsonb,         true),
  ('mobile_money', 'Mobile money', '{"so": "Lacag mobile"}'::jsonb,  true),
  ('bank',         'Bank',         '{"so": "Bangiga"}'::jsonb,       true)
on conflict (code) do update set
  label = excluded.label,
  label_translations = excluded.label_translations,
  is_active = excluded.is_active;

insert into public.party_type (code, label, label_translations, is_active) values
  ('supplier', 'Supplier',              '{"so": "Alaab keene"}'::jsonb,             true),
  ('customer', 'Customer',              '{"so": "Macmiil"}'::jsonb,                 true),
  ('both',     'Supplier and customer', '{"so": "Alaab keene iyo macmiil"}'::jsonb, true)
on conflict (code) do update set
  label = excluded.label,
  label_translations = excluded.label_translations,
  is_active = excluded.is_active;

insert into public.document_type (code, label, label_translations, is_active) values
  ('bono',            'Bono',            '{"so": "Bono"}'::jsonb,             true),
  ('sale_receipt',    'Sale receipt',    '{"so": "Risiidh iib"}'::jsonb,      true),
  ('expense_receipt', 'Expense receipt', '{"so": "Risiidh kharash"}'::jsonb,  true),
  ('opening_stock',   'Opening stock',   '{"so": "Kayd-furid"}'::jsonb,       true)
on conflict (code) do update set
  label = excluded.label,
  label_translations = excluded.label_translations,
  is_active = excluded.is_active;

insert into public.ocr_status (code, is_active) values
  ('pending',    true),
  ('processing', true),
  ('success',    true),
  ('failed',     true),
  ('manual',     true)
on conflict (code) do update set is_active = excluded.is_active;

insert into public.organization_role (code, label, label_translations, is_active) values
  ('org_owner', 'Organization owner', '{"so": "Milkiilaha ganacsiga"}'::jsonb, true),
  ('org_admin', 'Organization admin', '{"so": "Maamulaha ganacsiga"}'::jsonb,  true)
on conflict (code) do update set
  label = excluded.label,
  label_translations = excluded.label_translations,
  is_active = excluded.is_active;

insert into public.shop_role (code, label, label_translations, is_active) values
  ('owner',   'Owner',   '{"so": "Milkiile"}'::jsonb, true),
  ('cashier', 'Cashier', '{"so": "Khasnaji"}'::jsonb, true)
on conflict (code) do update set
  label = excluded.label,
  label_translations = excluded.label_translations,
  is_active = excluded.is_active;

insert into public.adjustment_reason (code, label, label_translations, is_increase, is_system, is_active) values
  ('opening',    'Opening',    '{"so": "Furitaan"}'::jsonb,    true,  true, true),
  ('spoilage',   'Spoilage',   '{"so": "Burburin"}'::jsonb,    false, true, true),
  ('correction', 'Correction', '{"so": "Saxitaan"}'::jsonb,    null,  true, true)
on conflict (code) do update set
  label = excluded.label,
  label_translations = excluded.label_translations,
  is_increase = excluded.is_increase,
  is_system = excluded.is_system,
  is_active = excluded.is_active;

insert into public.location_kind (code, is_active) values
  ('default', true)
on conflict (code) do update set is_active = excluded.is_active;
