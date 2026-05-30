create table public.language (
  code text primary key
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$'),
  name text not null,
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

create table public.ref_translation (
  ref_table text not null check (
    ref_table in (
      'language',
      'currency',
      'unit',
      'transaction_type',
      'transaction_status',
      'payment_method',
      'party_type',
      'document_type',
      'ocr_status',
      'organization_role',
      'shop_role',
      'adjustment_reason',
      'location_kind'
    )
  ),
  ref_code text not null,
  language_code text not null references public.language(code),
  label text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (ref_table, ref_code, language_code)
);

create trigger set_ref_translation_updated_at
before update on public.ref_translation
for each row execute function public.set_updated_at();

insert into public.language (code, name, is_active) values
  ('en', 'English', true),
  ('so', 'Somali', true)
on conflict (code) do update set
  name = excluded.name,
  is_active = excluded.is_active;

insert into public.currency (code, symbol, decimals, is_active) values
  ('USD', '$', 2, true),
  ('SLSH', 'SLSH', 0, true)
on conflict (code) do update set
  symbol = excluded.symbol,
  decimals = excluded.decimals,
  is_active = excluded.is_active;

insert into public.unit (code, default_label, is_active) values
  ('piece', 'Piece', true),
  ('bag', 'Bag', true),
  ('carton', 'Carton', true),
  ('box', 'Box', true),
  ('bottle', 'Bottle', true),
  ('packet', 'Packet', true),
  ('sack', 'Sack', true),
  ('kg', 'Kg', true),
  ('gram', 'Gram', true),
  ('litre', 'Litre', true),
  ('ml', 'ml', true),
  ('dozen', 'Dozen', true)
on conflict (code) do update set
  default_label = excluded.default_label,
  is_active = excluded.is_active;

insert into public.transaction_type (
  code,
  stock_effect,
  party_balance_effect,
  requires_party,
  requires_items,
  is_active
) values
  ('sale', -1, 'receivable', false, true, true),
  ('receive', 1, 'payable', true, true, true),
  ('expense', 0, 'none', false, false, true)
on conflict (code) do update set
  stock_effect = excluded.stock_effect,
  party_balance_effect = excluded.party_balance_effect,
  requires_party = excluded.requires_party,
  requires_items = excluded.requires_items,
  is_active = excluded.is_active;

insert into public.transaction_status (code, is_active) values
  ('draft', true),
  ('posted', true),
  ('void', true)
on conflict (code) do update set is_active = excluded.is_active;

insert into public.payment_method (code, is_active) values
  ('cash', true),
  ('mobile_money', true),
  ('bank', true)
on conflict (code) do update set is_active = excluded.is_active;

insert into public.party_type (code, is_active) values
  ('supplier', true),
  ('customer', true),
  ('both', true)
on conflict (code) do update set is_active = excluded.is_active;

insert into public.document_type (code, is_active) values
  ('bono', true),
  ('sale_receipt', true),
  ('expense_receipt', true),
  ('opening_stock', true)
on conflict (code) do update set is_active = excluded.is_active;

insert into public.ocr_status (code, is_active) values
  ('pending', true),
  ('processing', true),
  ('success', true),
  ('failed', true),
  ('manual', true)
on conflict (code) do update set is_active = excluded.is_active;

insert into public.organization_role (code, is_active) values
  ('org_owner', true),
  ('org_admin', true)
on conflict (code) do update set is_active = excluded.is_active;

insert into public.shop_role (code, is_active) values
  ('owner', true),
  ('cashier', true)
on conflict (code) do update set is_active = excluded.is_active;

insert into public.adjustment_reason (code, is_increase, is_system, is_active) values
  ('opening', true, true, true),
  ('spoilage', false, true, true),
  ('correction', null, true, true)
on conflict (code) do update set
  is_increase = excluded.is_increase,
  is_system = excluded.is_system,
  is_active = excluded.is_active;

insert into public.location_kind (code, is_active) values
  ('default', true)
on conflict (code) do update set is_active = excluded.is_active;

insert into public.ref_translation (ref_table, ref_code, language_code, label) values
  ('transaction_type', 'sale', 'en', 'Sale'),
  ('transaction_type', 'sale', 'so', 'Iib'),
  ('transaction_type', 'receive', 'en', 'Receive'),
  ('transaction_type', 'receive', 'so', 'Alaab keenid'),
  ('transaction_type', 'expense', 'en', 'Expense'),
  ('transaction_type', 'expense', 'so', 'Kharash'),
  ('payment_method', 'cash', 'en', 'Cash'),
  ('payment_method', 'cash', 'so', 'Kaash'),
  ('payment_method', 'mobile_money', 'en', 'Mobile money'),
  ('payment_method', 'mobile_money', 'so', 'Lacag mobile'),
  ('payment_method', 'bank', 'en', 'Bank'),
  ('payment_method', 'bank', 'so', 'Bangiga'),
  ('party_type', 'supplier', 'en', 'Supplier'),
  ('party_type', 'supplier', 'so', 'Alaab-qeybiye'),
  ('party_type', 'customer', 'en', 'Customer'),
  ('party_type', 'customer', 'so', 'Macmiil'),
  ('party_type', 'both', 'en', 'Supplier and customer'),
  ('party_type', 'both', 'so', 'Alaab-qeybiye iyo macmiil'),
  ('shop_role', 'owner', 'en', 'Owner'),
  ('shop_role', 'owner', 'so', 'Milkiile'),
  ('shop_role', 'cashier', 'en', 'Cashier'),
  ('shop_role', 'cashier', 'so', 'Khasnaji'),
  ('organization_role', 'org_owner', 'en', 'Organization owner'),
  ('organization_role', 'org_owner', 'so', 'Milkiilaha ganacsiga'),
  ('organization_role', 'org_admin', 'en', 'Organization admin'),
  ('organization_role', 'org_admin', 'so', 'Maamulaha ganacsiga')
on conflict (ref_table, ref_code, language_code) do update set
  label = excluded.label;
