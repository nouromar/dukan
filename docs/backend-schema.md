# Dukan backend schema draft

This document is the working Supabase/Postgres backend plan for v1. It turns the product, UX, template, and architecture decisions into a migration-ready schema outline.

The goal is not to build an ERP. The goal is a small, correct accounting/inventory core that makes Sale, Receive, Payment, Expense, opening stock, templates, OCR drafts, and reports safe from day one.

## 1. Backend principles

1. **Shared database, shop isolation by row.** One Supabase project/database for v1; every business row has `shop_id`; RLS checks direct shop membership or org-level access.
2. **No trusted shop claim in JWT.** The app can keep `current_shop_id` for UX, but authorization always looks up `shop_membership` / `organization_membership` by `auth.uid()`.
3. **Composite tenant foreign keys.** RLS is not enough. Child rows carry `shop_id` and reference parents through `(shop_id, id)`.
4. **Reference rows over Postgres enums.** User-visible types/statuses/methods/roles are tables with translations.
5. **Internal technical enums are allowed.** `payment.direction` and similar implementation fields may use CHECK constraints because users should not extend them. `stock_movement` uses typed nullable source FKs instead of a string discriminator so the database can enforce parent integrity.
6. **Posted records are immutable.** Corrections use reversing rows, not edits.
7. **Cached balances are projections.** `item.current_stock`, `item.avg_cost`, `party.receivable`, and `party.payable` are maintained only by posting procedures and checked by reconciliation views.
8. **Only two writers to stock.** `transaction_line` posting and `inventory_adjustment_line` posting are the only paths that create `stock_movement`.
9. **Setup gates daily flows.** Sale, Receive, Payment, Expense, and inventory adjustment posting require `shop.setup_status = 'ready'`, except the opening stock step during setup.
10. **Support is setup-only.** V1 uses WhatsApp/email help. Internal support/admin tools must not post sales, receives, payments, expenses, stock adjustments, voids, or refunds.

## 2. Supabase project layout

Recommended migration groups:

| Migration | Contains |
|---|---|
| `0001_extensions` | `pgcrypto`, `pg_trgm` |
| `0002_reference_data` | languages, currencies, units, type/status/method tables, translations |
| `0003_tenancy` | organization, shop, organization membership, shop membership, platform staff roles |
| `0004_auth_helpers` | helper functions that depend on membership and platform tables |
| `0005_shop_setup` | locations, shop settings, help channels, expense categories |
| `0006_catalog_templates` | catalog concept/item/revision tables and modular template tables |
| `0007_items_parties` | shop items, item units, aliases, parties, supplier types |
| `0008_documents_ocr` | documents, OCR jobs, OCR results/corrections |
| `0009_transactions_stock_payments` | transactions, lines, payments, allocations, stock movements, inventory adjustments |
| `0010_posting_rpcs` | posting RPCs for sale, receive, payment, expense, inventory adjustment |
| `0011_catalog_activation` | safe catalog-item activation into shop-owned operational items |
| `0012_apply_template` | idempotent template application into shop setup |
| `0013_reports_reconciliation` | reconciliation, sales/receive/expense/payment, daily, and monthly report views |
| `0014_learning_profiles` | shop-scoped usage counters, learned defaults, and precomputed suggestions |
| `0015_rls_storage` | Supabase Storage bucket, object policies, and document deletion rules |

Use Supabase Edge Functions for OCR, imports, and external integrations. Use Postgres functions for posting truth.

## 3. Extensions and helper functions

```sql
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
```

Create authorization helpers after `shop_membership`, `organization_membership`, role tables, and `platform_membership` exist:

```sql
create function auth_can_access_shop(p_shop_id uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from shop_membership sm
    where sm.shop_id = p_shop_id
      and sm.user_id = auth.uid()
      and sm.is_active
  )
  or exists (
    select 1
    from shop s
    join organization_membership om on om.organization_id = s.organization_id
    join organization_role r on r.id = om.role_id
    where s.id = p_shop_id
      and om.user_id = auth.uid()
      and om.is_active
      and r.code in ('org_owner', 'org_admin')
  );
$$;

create function auth_has_shop_role(p_shop_id uuid, p_role_code text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from shop_membership sm
    join shop_role r on r.id = sm.role_id
    where sm.shop_id = p_shop_id
      and sm.user_id = auth.uid()
      and sm.is_active
      and r.code = p_role_code
  )
  or (
    p_role_code = 'owner'
    and exists (
      select 1
      from shop s
      join organization_membership om on om.organization_id = s.organization_id
      join organization_role r on r.id = om.role_id
      where s.id = p_shop_id
        and om.user_id = auth.uid()
        and om.is_active
        and r.code = 'org_owner'
    )
  );
$$;

create function auth_is_platform_staff(p_role_code text default null)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from platform_membership pm
    where pm.user_id = auth.uid()
      and pm.is_active
      and (p_role_code is null or pm.role_code = p_role_code)
  );
$$;
```

All SECURITY DEFINER posting functions must re-check shop access and role explicitly. Do not rely on caller-supplied `shop_id`.

## 4. Reference data

Reference tables are global unless marked shop-scoped.

```text
language(
  code pk,                 -- en, so
  name,
  is_active
)

currency(
  code pk,                 -- USD, SLSH, SOS later if needed
  symbol,
  decimals,
  is_active
)

unit(
  id pk,
  code unique,             -- piece, kg, gram, litre, bottle, bag, carton
  default_label,
  is_active
)

transaction_type(
  id pk,
  code unique,             -- sale, receive, expense
  stock_effect int,        -- sale=-1, receive=+1, expense=0
  party_balance_effect text,
  requires_party bool,
  requires_items bool,
  is_active
)

transaction_status(
  id pk,
  code unique              -- draft, posted, void
)

payment_method(
  id pk,
  code unique,             -- cash, mobile_money, bank
  is_active
)

party_type(
  id pk,
  code unique              -- supplier, customer, both
)

document_type(
  id pk,
  code unique              -- bono, sale_receipt, expense_receipt, opening_stock
)

ocr_status(
  id pk,
  code unique              -- pending, processing, success, failed, manual
)

organization_role(
  id pk,
  code unique              -- org_owner, org_admin; accountant/viewer can be added later
)

shop_role(
  id pk,
  code unique              -- owner, cashier; manager/viewer can be added later
)

adjustment_reason(
  id pk,
  code unique,             -- opening, spoilage, correction
  is_increase bool null,
  is_system bool default false
)

location_kind(
  id pk,
  code unique              -- default in v1
)

ref_translation(
  table_name,
  row_id,
  locale references language(code),
  label,
  primary key(table_name, row_id, locale)
)
```

Seed minimum rows:

- Languages: `en`, `so`.
- Currencies: `USD`, `SLSH`; keep one currency per shop.
- Transaction types: `sale`, `receive`, `expense`.
- Organization roles: `org_owner`, `org_admin`.
- Shop roles: `owner`, `cashier`.
- Adjustment reasons: `opening`, `spoilage`, `correction`.

## 5. Tenancy and platform staff

```text
organization(
  id pk,
  name,
  plan_code null,
  created_at
)

organization_membership(
  id pk,
  organization_id references organization(id),
  user_id references auth.users(id),
  role_id references organization_role(id),
  is_active bool default true,
  created_at,
  unique(organization_id, user_id),
  unique(organization_id, id)
)

shop(
  id pk,
  organization_id references organization(id),
  name,
  currency_code references currency(code),
  timezone,
  default_language_code references language(code),
  setup_status text default 'not_started',
  setup_completed_at timestamptz null,
  created_at,
  updated_at
)

shop_membership(
  id pk,
  shop_id references shop(id),
  user_id references auth.users(id),
  role_id references shop_role(id),
  is_active bool default true,
  created_at,
  unique(shop_id, user_id),
  unique(shop_id, id)
)

platform_membership(
  id pk,
  user_id references auth.users(id),
  role_code text check (role_code in ('platform_admin', 'support_agent')),
  is_active bool default true,
  created_at,
  unique(user_id, role_code)
)
```

`organization_membership` represents top business owners/admins across all shops in the organization. `shop_membership` represents users assigned to one shop, especially cashiers and shop-level owners.

Org owners/admins can manage organization setup, create shops, invite shop users, and view cross-shop reports in the web admin portal. Daily financial operations still post to exactly one selected `shop_id`; there is no org-level stock or org-level sale.

`platform_membership` is for Dukan staff and the admin portal. Platform staff may manage templates and setup data according to RLS/policies, but posting functions must deny them unless they also have a real shop or org membership with an allowed role.

## 6. Catalog and modular templates

The central catalog is an inherited reference layer. Daily transactions never post against central catalog rows; they post against shop-owned `item` rows. Activating a catalog item creates a small shop-owned operational projection (`item` + `item_unit`) for stock, price, and local overrides, while shared product identity and defaults remain centralized as immutable catalog revisions.

```text
catalog_product_concept(
  id pk,
  code unique,             -- sugar, rice, cooking_oil
  name_en,
  description_en null,
  is_active
)

catalog_product_translation(
  concept_id references catalog_product_concept(id),
  locale references language(code),
  name,
  description null,
  primary key(concept_id, locale)
)

catalog_item(
  id pk,
  concept_id references catalog_product_concept(id),
  code unique,
  current_revision_id references catalog_item_revision(id) null,
  is_active
)

catalog_item_revision(
  id pk,
  catalog_item_id references catalog_item(id),
  revision_number int,
  name,
  brand_name null,
  package_quantity numeric(14,3) null,
  package_unit_code text null,
  variant null,
  category_code,
  base_unit_code,
  default_sale_unit_code,
  default_receive_unit_code,
  suggested_sale_price numeric(14,2) null,
  reorder_threshold numeric(14,3) null,
  effective_from,
  unique(catalog_item_id, revision_number),
  unique(catalog_item_id, id)
)

catalog_item_unit(
  id pk,
  catalog_item_id,
  revision_id,
  unit_code references unit(code),
  conversion_to_base numeric(14,6),
  is_base_unit bool,
  allow_sale bool,
  allow_receive bool,
  unique(catalog_item_id, revision_id, unit_code)
)

catalog_item_alias(
  id pk,
  catalog_item_id references catalog_item(id),
  language_code references language(code) null,
  alias_text,
  source
)
```

Translate only product concept and description. Brand, quantity, size, package, and unit remain structured fields.

Template metadata and packs:

```text
template(
  id pk,
  code unique,             -- grocery_v1
  kind,                    -- shop_starter
  name,
  locale_default,
  currency_default,
  version int,
  is_active,
  created_at
)

template_pack(
  id pk,
  template_id references template(id),
  code,                    -- catalog, settings, quick_actions, supplier_mappings...
  version int,
  is_required bool,
  file_path,
  checksum null,
  unique(template_id, code, version)
)

template_unit(
  id pk,
  template_id references template(id),
  unit_code,
  label jsonb,
  sort_order int
)

template_item(
  id pk,
  template_id references template(id),
  item_code,
  catalog_item_id references catalog_item(id) null,
  catalog_revision_id references catalog_item_revision(id) null,
  custom_name null,                         -- required only for custom/non-catalog template rows
  name_override null,
  base_unit_code_override null,
  default_sale_unit_code_override null,
  default_receive_unit_code_override null,
  suggested_sale_price_override numeric(14,2) null,
  reorder_threshold_override numeric(14,3) null,
  sort_order int,
  unique(template_id, item_code)
)

template_item_unit(
  id pk,
  template_id references template(id),
  item_code,
  unit_code,
  conversion_to_base numeric(14,6),
  allow_sale bool,
  allow_receive bool,
  sort_order int,
  unique(template_id, item_code, unit_code)
)

template_supplier_type(
  id pk,
  template_id references template(id),
  supplier_type_code,
  label jsonb,
  sort_order int,
  unique(template_id, supplier_type_code)
)

template_supplier_item(
  id pk,
  template_id references template(id),
  supplier_type_code,
  item_code,
  usual_unit_code null,
  cost_entry_mode text null check (cost_entry_mode in ('unit_cost', 'line_total')),
  sort_order int,
  unique(template_id, supplier_type_code, item_code)
)

template_quantity_suggestion(
  id pk,
  template_id references template(id),
  item_code null,
  category_code null,
  context text check (context in ('sale', 'receive')),
  quantity numeric(14,3),
  unit_code,
  sort_order int
)

template_quick_action(
  id pk,
  template_id references template(id),
  screen text,             -- sale, expense, receive
  position int,
  item_code null,
  expense_category_code null,
  label jsonb null,
  unique(template_id, screen, position)
)

template_item_alias(
  id pk,
  template_id references template(id),
  item_code,
  locale,
  alias_text,
  source text default 'template'
)

template_party_alias(
  id pk,
  template_id references template(id),
  party_code,
  locale,
  alias_text,
  source text default 'template'
)

template_expense_category(
  id pk,
  template_id references template(id),
  code,
  name,
  name_translations jsonb,
  sort_order int,
  unique(template_id, code)
)

template_setting(
  id pk,
  template_id references template(id),
  key,
  value jsonb,
  unique(template_id, key)
)
```

Application trace:

```text
template_application(
  id pk,
  shop_id references shop(id),
  template_id references template(id),
  template_version int,
  applied_by references auth.users(id),
  applied_at,
  merge_strategy text,     -- first_apply, merge_update
  unique(shop_id, template_id, template_version)
)

template_pack_application(
  id pk,
  template_application_id references template_application(id),
  pack_code,
  pack_version int,
  applied_at,
  status text,
  unique(template_application_id, pack_code)
)
```

`apply_template()` must be idempotent. It inserts missing shop rows and never overwrites rows the shop has edited.

## 7. Shop setup tables

```text
location(
  id pk,
  shop_id references shop(id),
  name,
  kind_id references location_kind(id),
  is_active bool default true,
  created_at,
  unique(shop_id, id)
)

shop_setting(
  id pk,
  shop_id references shop(id),
  key,
  value jsonb,
  source text,             -- template, manual, learned
  updated_at,
  unique(shop_id, key),
  unique(shop_id, id)
)

help_channel(
  id pk,
  shop_id references shop(id) null,
  channel text check (channel in ('whatsapp', 'email')),
  value,
  is_active bool default true,
  sort_order int
)

expense_category(
  id pk,
  shop_id references shop(id),
  code,
  name,
  name_translations jsonb null,
  is_active bool default true,
  source_template_item_id uuid null,
  created_at,
  updated_at,
  unique(shop_id, code),
  unique(shop_id, id)
)
```

V1 setup status:

```text
not_started -> template_applied -> opening_stock_done -> ready
```

Daily posting functions must block unless the shop is `ready`. The only exception is posting the mandatory opening stock adjustment while moving from `template_applied` to `opening_stock_done`.

After opening stock is confirmed, `complete_shop_setup(p_shop_id)` performs final validation, sets `shop.setup_status = 'ready'`, and stamps `shop.setup_completed_at`. Daily Sale/Receive/Payment/Expense flows should not appear in the app until this step succeeds.

## 8. Items, units, parties, and aliases

```text
item(
  id pk,
  shop_id references shop(id),
  code null,
  catalog_item_id references catalog_item(id) null,
  catalog_revision_id references catalog_item_revision(id) null,
  source_template_item_id uuid null,
  name,                       -- denormalized inherited/effective name for resilient posting
  name_override null,         -- shop-local wording; v_item_effective uses this first
  base_unit_id references unit(id),
  default_sale_unit_id references unit(id),
  default_receive_unit_id references unit(id),
  sale_price numeric(14,2) null,
  last_cost numeric(14,4) null,
  avg_cost numeric(14,4) default 0,
  current_stock numeric(14,3) default 0,
  reorder_threshold numeric(14,3) null,
  barcode text null,
  is_active bool default true,
  created_at,
  updated_at,
  unique(shop_id, code),
  unique(shop_id, id)
)

item_unit(
  id pk,
  shop_id references shop(id),
  item_id,
  unit_id references unit(id),
  source_catalog_item_unit_id references catalog_item_unit(id) null,
  source text,                -- catalog/template/manual/override
  conversion_to_base numeric(14,6), -- 1 entered unit = N base units
  is_base_unit bool default false,
  allow_sale bool default true,
  allow_receive bool default true,
  sort_order int,
  unique(shop_id, item_id, unit_id),
  unique(shop_id, id),
  foreign key (shop_id, item_id) references item(shop_id, id)
)

item_alias(
  id pk,
  shop_id references shop(id),
  item_id,
  alias_text,
  locale null,
  source text,             -- template, manual, ocr_correction
  created_at,
  unique(shop_id, alias_text, item_id),
  unique(shop_id, id),
  foreign key (shop_id, item_id) references item(shop_id, id)
)

supplier_type(
  id pk,
  shop_id references shop(id),
  code,
  label,
  sort_order int,
  unique(shop_id, code),
  unique(shop_id, id)
)

party(
  id pk,
  shop_id references shop(id),
  name,
  phone null,
  type_id references party_type(id),
  supplier_type_id null,
  receivable numeric(14,2) default 0,
  payable numeric(14,2) default 0,
  notes null,
  is_active bool default true,
  created_at,
  updated_at,
  unique(shop_id, id),
  foreign key (shop_id, supplier_type_id) references supplier_type(shop_id, id)
)

party_alias(
  id pk,
  shop_id references shop(id),
  party_id,
  alias_text,
  locale null,
  source text,
  created_at,
  unique(shop_id, alias_text, party_id),
  unique(shop_id, id),
  foreign key (shop_id, party_id) references party(shop_id, id)
)
```

`activate_catalog_item(shop_id, catalog_item_id, catalog_revision_id default null, ...)` is the safe copy-on-write boundary. It resolves the current catalog revision, creates the shop `item`, copies only the unit projection needed for posting, and leaves stock/cost/price as shop-owned data. `v_item_effective` is the app read model for resolved display name and unit codes.

Split-package rule:

- If an item is sold only as the package, base unit can be the package unit.
- If a received package is split for sale, base unit is the smallest unit sold.
- All `stock_movement.quantity_delta`, `item.current_stock`, and `item.avg_cost` are in base unit.

Example: candy received by bag and sold by piece:

```text
item.base_unit = piece
item_unit(piece).conversion_to_base = 1
item_unit(bag).conversion_to_base = 100
Receive 10 bags -> +1000 pieces
Sale 3 pieces -> -3 pieces
```

## 9. Documents and OCR

```text
document(
  id pk,
  shop_id references shop(id),
  type_id references document_type(id),
  storage_bucket,
  storage_path,
  mime_type,
  size_bytes,
  ocr_status_id references ocr_status(id),
  ocr_result jsonb null,
  uploaded_by references auth.users(id),
  created_at,
  updated_at,
  unique(shop_id, id)
)

ocr_job(
  id pk,
  shop_id references shop(id),
  document_id,
  status text check (status in ('queued', 'processing', 'success', 'failed')),
  attempts int default 0,
  locked_at timestamptz null,
  last_error text null,
  created_at,
  updated_at,
  unique(document_id),
  foreign key (shop_id, document_id) references document(shop_id, id)
)

ocr_correction(
  id pk,
  shop_id references shop(id),
  document_id,
  raw_text,
  accepted_entity_table text,
  accepted_entity_id uuid,
  confidence numeric(5,4) null,
  created_at,
  foreign key (shop_id, document_id) references document(shop_id, id)
)
```

Storage:

```text
Bucket: shop-documents
Path: {shop_id}/documents/{document_id}/image.(jpg|jpeg|png|webp)
Allowed MIME: image/jpeg, image/png, image/webp
Max size: 8 MB
```

OCR never posts a transaction. It writes a draft/candidate result. The user confirms, edits, or rejects it.

## 10. Transactions, payments, and stock

The logical docs call this the money spine plus quantity spine.

```text
txn( -- physical table name avoids the SQL keyword "transaction"
  id pk,
  shop_id references shop(id),
  type_id references transaction_type(id),
  status_id references transaction_status(id),
  party_id null,
  occurred_at timestamptz,
  posted_at timestamptz null,
  total_amount numeric(14,2),
  paid_amount numeric(14,2) default 0,
  payment_method_id references payment_method(id) null,
  document_id null,
  reverses_transaction_id null,
  client_op_id text null,
  notes null,
  created_by references auth.users(id),
  created_at,
  unique(shop_id, client_op_id),
  unique(shop_id, id),
  foreign key (shop_id, party_id) references party(shop_id, id),
  foreign key (shop_id, document_id) references document(shop_id, id),
  foreign key (shop_id, reverses_transaction_id) references txn(shop_id, id)
)

transaction_line(
  id pk,
  shop_id references shop(id),
  transaction_id,
  line_no int,
  item_id null,
  expense_category_id null,
  quantity numeric(14,3) null,
  unit_id references unit(id) null,
  base_quantity numeric(14,3) null,
  unit_amount numeric(14,4) null,
  item_name_snapshot text null,
  unit_code_snapshot text null,
  unit_conversion_to_base_snapshot numeric(14,6) null,
  catalog_revision_id references catalog_item_revision(id) null,
  line_total numeric(14,2),
  cogs_unit_cost numeric(14,4) null,
  cogs_total numeric(14,2) null,
  created_at,
  unique(shop_id, id),
  unique(shop_id, transaction_id, line_no),
  foreign key (shop_id, transaction_id) references txn(shop_id, id),
  foreign key (shop_id, item_id) references item(shop_id, id),
  foreign key (shop_id, expense_category_id) references expense_category(shop_id, id)
)

payment(
  id pk,
  shop_id references shop(id),
  party_id null,
  direction char(1) check (direction in ('I','O')), -- I=in from customer, O=out to supplier
  amount numeric(14,2),
  method_id references payment_method(id),
  occurred_at timestamptz,
  document_id null,
  client_op_id text null,
  notes null,
  created_by references auth.users(id),
  created_at,
  unique(shop_id, client_op_id),
  unique(shop_id, id),
  foreign key (shop_id, party_id) references party(shop_id, id),
  foreign key (shop_id, document_id) references document(shop_id, id)
)

payment_allocation(
  id pk,
  shop_id references shop(id),
  payment_id,
  transaction_id,
  amount numeric(14,2),
  created_at,
  unique(payment_id, transaction_id),
  unique(shop_id, id),
  foreign key (shop_id, payment_id) references payment(shop_id, id),
  foreign key (shop_id, transaction_id) references txn(shop_id, id)
)

stock_movement(
  id pk,
  shop_id references shop(id),
  item_id,
  location_id null,
  transaction_line_id null,
  inventory_adjustment_line_id null,
  quantity_delta numeric(14,3), -- base unit
  unit_cost numeric(14,4) null, -- cost per base unit
  occurred_at timestamptz,
  created_at,
  unique(shop_id, id),
  foreign key (shop_id, item_id) references item(shop_id, id),
  foreign key (shop_id, location_id) references location(shop_id, id),
  foreign key (shop_id, transaction_line_id) references transaction_line(shop_id, id),
  foreign key (shop_id, inventory_adjustment_line_id) references inventory_adjustment_line(shop_id, id)
)

inventory_adjustment(
  id pk,
  shop_id references shop(id),
  reason_id references adjustment_reason(id),
  status_id references transaction_status(id),
  occurred_at timestamptz,
  posted_at timestamptz null,
  document_id null,
  notes null,
  approved_by references auth.users(id) null,
  created_by references auth.users(id),
  created_at,
  unique(shop_id, id),
  foreign key (shop_id, document_id) references document(shop_id, id)
)

inventory_adjustment_line(
  id pk,
  shop_id references shop(id),
  adjustment_id,
  item_id,
  quantity_delta numeric(14,3), -- base unit
  unit_cost numeric(14,4) null,
  created_at,
  unique(shop_id, id),
  foreign key (shop_id, adjustment_id) references inventory_adjustment(shop_id, id),
  foreign key (shop_id, item_id) references item(shop_id, id)
)
```

Important note: the logical model still says "transaction", but the physical Postgres table is `txn` to avoid reserved-word quoting. Anonymous cash sales also create a `payment` row with `party_id = null` so cash reporting can read a single payment stream; only party settlement requires `payment_allocation`.

## 11. Shop learning and fast-entry profiles

These tables improve UX only. They are not accounting truth.

```text
shop_item_usage(
  shop_id references shop(id),
  item_id,
  sale_count int default 0,
  receive_count int default 0,
  total_sale_base_quantity numeric(14,3) default 0,
  total_receive_base_quantity numeric(14,3) default 0,
  last_sale_at timestamptz null,
  last_receive_at timestamptz null,
  unique(shop_id, item_id),
  foreign key (shop_id, item_id) references item(shop_id, id)
)

shop_item_entry_profile(
  shop_id references shop(id),
  item_id,
  context text,                -- sale or receive
  unit_id references unit(id),
  quantity numeric(14,3),
  usage_count int default 0,
  last_unit_amount numeric(14,4) null,
  last_used_at timestamptz null,
  unique(shop_id, item_id, context, unit_id, quantity),
  foreign key (shop_id, item_id) references item(shop_id, id)
)

shop_supplier_item_profile(
  shop_id references shop(id),
  supplier_id,
  item_id,
  unit_id references unit(id),
  receive_count int default 0,
  total_base_quantity numeric(14,3) default 0,
  last_unit_cost numeric(14,4) null,
  last_received_at timestamptz null,
  unique(shop_id, supplier_id, item_id, unit_id),
  foreign key (shop_id, supplier_id) references party(shop_id, id),
  foreign key (shop_id, item_id) references item(shop_id, id)
)

shop_party_usage(
  shop_id references shop(id),
  party_id,
  sale_count int default 0,
  receive_count int default 0,
  payment_count int default 0,
  last_sale_at timestamptz null,
  last_receive_at timestamptz null,
  last_payment_at timestamptz null,
  unique(shop_id, party_id),
  foreign key (shop_id, party_id) references party(shop_id, id)
)

shop_quick_action(
  id pk,
  shop_id references shop(id),
  screen text,
  position int,
  item_id null,
  expense_category_id null,
  source text,             -- template, learned, manual
  unique(shop_id, screen, position),
  unique(shop_id, id),
  foreign key (shop_id, item_id) references item(shop_id, id),
  foreign key (shop_id, expense_category_id) references expense_category(shop_id, id)
)

shop_suggestion(
  id pk,
  shop_id references shop(id),
  screen text not null,        -- sale, receive, payment, expense, dashboard
  context_key text not null default 'global', -- optional context such as supplier:{party_id}
  suggestion_type text not null, -- item, quantity, supplier_item, customer, supplier, expense_category, payment_method
  target_key text not null,
  item_id uuid null,
  party_id uuid null,
  expense_category_id uuid null,
  payment_method_id uuid null references payment_method(id),
  unit_id uuid null references unit(id),
  quantity numeric(14,3) null,
  value_text text null,
  source text not null check (source in ('template', 'setup', 'learned', 'manual')),
  rank int not null,
  is_active boolean not null default true,
  usage_count int not null default 0,
  last_used_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(shop_id, screen, context_key, suggestion_type, target_key, source),
  unique(shop_id, id),
  foreign key (shop_id, item_id) references item(shop_id, id),
  foreign key (shop_id, party_id) references party(shop_id, id),
  foreign key (shop_id, expense_category_id) references expense_category(shop_id, id)
)
```

Triggers update these profiles after confirmed transaction/payment rows and maintain `shop_suggestion` rows where practical. Template application seeds template suggestions through `rebuild_shop_suggestions(shop_id)`. The mobile app should read active rows from `v_shop_suggestions` ordered by `rank`, not recompute thresholds on every screen load. Learned values should be used as suggestions, not as hidden automatic choices that affect money or stock.

## 12. Posting functions

The app should not directly assemble accounting effects. It should call RPC functions that validate input, post rows, update cached projections, and return the saved result.

### 12.1 `apply_template(p_shop_id, p_template_id, p_pack_codes text[] default null)`

Responsibilities:

1. Verify caller is shop owner or permitted platform setup staff.
2. Insert the default location.
3. Insert template settings, expense categories, supplier types, and a default location.
4. Create missing shop-owned `item`, `item_unit`, and `item_alias` rows using `activate_catalog_item()` for catalog-backed template items.
5. Record `template_application` and `template_pack_application`.
6. Move `shop.setup_status` to `template_applied`.

Rules:

- Idempotent.
- Match existing rows by stable shop row codes and skip conflicts.
- Do not overwrite rows with manual edits; applying a template creates product shells only. `current_stock`, `avg_cost`, and `last_cost` remain shop-owned operational truth populated by opening stock or Receive posting.
- Do not post stock, payments, expenses, sales, or receives.

### 12.2 `post_sale(...)`

Inputs should include `shop_id`, optional `party_id`, lines, payment mode, paid amount, optional receipt document, `client_op_id`, and occurred date.

Responsibilities:

1. Verify setup is ready.
2. Verify caller has a posting role (`owner` or `cashier`).
3. Validate customer requirement for debt sales.
4. Convert each entered quantity to item base unit through `item_unit`.
5. Compute totals on the server.
6. Snapshot COGS from `item.avg_cost` on each line.
7. Insert `txn(type=sale)` and `transaction_line`.
8. Insert negative `stock_movement` rows.
9. Update `item.current_stock`.
10. Increase `party.receivable` by unpaid amount if debt/partial.
11. If paid, create inbound `payment`; create `payment_allocation` when a party balance is involved.
12. Update usage/learning profiles.

Negative stock policy comes from `shop_setting`. V1 should likely warn or block per shop template setting, but server must enforce the chosen policy.

### 12.3 `post_receive(...)`

Inputs should include `shop_id`, supplier `party_id`, lines, cost entry mode per line, paid amount, optional bono document, `client_op_id`, and occurred date.

Responsibilities:

1. Verify setup is ready.
2. Require supplier/both party.
3. Convert entered quantities to base unit.
4. Compute line totals and total amount on the server.
5. Insert `txn(type=receive)` and lines.
6. Insert positive `stock_movement` rows.
7. Recompute weighted-average `item.avg_cost`; update `item.last_cost` and `item.current_stock`.
8. Increase `party.payable` by unpaid amount.
9. If paid now, create outbound `payment` and `payment_allocation`.
10. Update supplier-item learning profiles.

Weighted average should be based on old stock quantity/value plus received base quantity/value. Do not recompute old sale COGS.

### 12.4 `post_payment(...)`

Inputs: `shop_id`, `party_id`, direction, amount, method, optional allocation list, optional document, `client_op_id`.

Responsibilities:

1. Verify setup is ready.
2. Verify party type matches direction (`I` for customer receivable, `O` for supplier payable; `both` allowed).
3. Insert payment.
4. V1 standalone payments reduce cached `party.receivable` or `party.payable` directly and block overpayment; transaction-level allocations can be expanded later.

Overpayment is blocked in v1.

### 12.5 `post_expense(...)`

Inputs: `shop_id`, expense category, amount, method label if needed, optional document, note, `client_op_id`.

Responsibilities:

1. Verify setup is ready.
2. Insert `txn(type=expense)` with one expense line.
3. No stock movement.
4. No party balance by default.

Expenses affect profit reports directly from the expense transaction lines.

### 12.6 `post_inventory_adjustment(...)`

Inputs: `shop_id`, reason, lines in base units, optional document, notes.

Responsibilities:

1. For opening stock, allow while `shop.setup_status = 'template_applied'`.
2. For non-opening adjustments, require setup ready and owner role.
3. Insert `inventory_adjustment` and lines.
4. Insert `stock_movement` rows.
5. Update `item.current_stock`; for opening/positive adjustments with cost, update average cost; for negative adjustments, snapshot current average cost.
6. Move `shop.setup_status` to `opening_stock_done` when the opening stock adjustment is posted.

Only owner-controlled flows should call this. Support/admin can prepare import data but must not post it.

### 12.7 `complete_shop_setup(p_shop_id)`

Responsibilities:

1. Require owner role.
2. Verify template has been applied.
3. Verify opening stock was completed or explicitly skipped with an owner acknowledgement if that policy is allowed later.
4. Set `shop.setup_status = 'ready'` and `shop.setup_completed_at = now()`.

### 12.8 `void_transaction(p_shop_id, p_transaction_id, p_reason)`

Responsibilities:

1. Require owner role.
2. Verify original transaction is posted and not already reversed.
3. Insert a reversing transaction with `reverses_transaction_id`.
4. Insert reversing transaction lines; normal posting creates reversing stock movements through `transaction_line`.
5. Reverse related payment allocations by creating opposite payment/allocation rows where needed.

V1 can limit voids to a configured window, e.g. 7 days.

## 13. RLS policy plan

Default:

```sql
alter table <table> enable row level security;
```

Business table template:

```sql
create policy <table>_shop_select
on <table>
for select
using (auth_can_access_shop(shop_id));

create policy <table>_shop_insert
on <table>
for insert
with check (auth_can_access_shop(shop_id));

create policy <table>_shop_update
on <table>
for update
using (auth_can_access_shop(shop_id))
with check (auth_can_access_shop(shop_id));
```

For immutable accounting tables, direct insert/update/delete should be more restrictive:

- `txn`, `transaction_line`, `payment`, `payment_allocation`, `stock_movement`, `inventory_adjustment`, and `inventory_adjustment_line` should generally deny direct client writes.
- Writes happen through RPC posting functions.
- Policies may allow select by direct shop membership or org-level access only.

Platform/template table policy:

- Platform admin can insert/update templates.
- Authenticated shop users can read active templates.
- Support agent can read templates and setup data.

Support policy:

- Platform support can write setup-scoped tables only when explicitly allowed.
- Platform support cannot execute posting RPCs unless they are also a shop/org member with an allowed operational role, which should not be the normal support model.
- No v1 support-session RLS is needed because support codes are disabled.

## 14. Storage policy

Documents live in one bucket:

```text
shop-documents
```

Object names must match:

```text
{shop_id}/documents/{document_id}/image.(jpg|jpeg|png|webp)
```

The `document_id` segment is intentionally a directory prefix so future files for the same document can live together, for example OCR JSON output or derived thumbnails, without changing the document-level organization.

Implemented in `0015_rls_storage`:

- Bucket `shop-documents` is private, limited to 8 MB images (`image/jpeg`, `image/png`, `image/webp`).
- `document.storage_path` is constrained to match the object path and include the same `shop_id` and `document.id`.
- Read: authenticated users can read objects only when the path matches an existing `document` row for a shop they can access.
- Upload/replace: authenticated users can write only when the path matches an existing `document` row for a shop they can access and they are the uploader or shop owner.
- Direct Storage object delete by app users is not granted. Owners delete unattached `document` rows instead; an `after delete` trigger removes the matching Storage object.
- Document metadata delete is owner-only and blocked once the document is attached to a transaction, payment, or inventory adjustment.
- OCR Edge Function uses service role, but must verify `document.shop_id` and quota before calling Google Vision.

## 15. Indexes and constraints

Required indexes:

```text
organization_membership(user_id, organization_id) where is_active
shop_membership(user_id, shop_id) where is_active
platform_membership(user_id) where is_active
shop(organization_id)
item(shop_id, is_active)
item(shop_id, code)
item_alias using gin(alias_text gin_trgm_ops)
party(shop_id, type_id, is_active)
party_alias using gin(alias_text gin_trgm_ops)
txn(shop_id, occurred_at desc)
txn(shop_id, type_id, status_id, occurred_at desc)
txn(shop_id, party_id, occurred_at desc)
transaction_line(shop_id, transaction_id)
payment(shop_id, party_id, occurred_at desc)
payment_allocation(shop_id, transaction_id)
stock_movement(shop_id, item_id, occurred_at desc)
document(shop_id, type_id, created_at desc)
ocr_job(status, locked_at)
```

Required unique constraints:

- Every parent business table needs `unique(shop_id, id)` for composite FKs.
- `txn(shop_id, client_op_id)`, `payment(shop_id, client_op_id)`, and `inventory_adjustment(shop_id, client_op_id)` for idempotency.
- `item(shop_id, code)` for template/merge identity.
- `expense_category(shop_id, code)`.
- `supplier_type(shop_id, code)`.
- `template(code, version)` or equivalent versioning key if multiple versions are retained.

## 16. Report and reconciliation views

Implemented v1 views:

```text
v_item_stock_truth(shop_id, item_id, cached_stock, ledger_stock, stock_variance, movement_count)
v_party_balance_truth(shop_id, party_id, cached_receivable, ledger_receivable, receivable_variance, cached_payable, ledger_payable, payable_variance)
v_sales_report(shop_id, transaction_id, local_date, local_month, customer_id, revenue, paid_amount, unpaid_amount, cogs_total, gross_profit)
v_receive_report(shop_id, transaction_id, local_date, local_month, supplier_id, total_amount, paid_amount, unpaid_amount)
v_expense_report(shop_id, transaction_id, local_date, local_month, expense_category_id, amount)
v_payment_report(shop_id, payment_id, party_id, direction, amount, local_date, local_month)
v_daily_profit(shop_id, local_date, revenue, cogs_total, gross_profit, expense_total, net_profit)
v_monthly_profit(shop_id, local_month, revenue, cogs_total, gross_profit, expense_total, net_profit)
v_monthly_sales(shop_id, local_month, sale_count, revenue, paid_amount, unpaid_amount, cogs_total, gross_profit)
v_monthly_expenses(shop_id, local_month, expense_category_id, expense_total)
```

All report views use `security_invoker = true` so underlying RLS still controls tenant visibility. Base report views cover all dates and the app filters by date range; daily and monthly views are rollups only. Weekly rollups are intentionally not included for v1. Profit uses sale line COGS snapshots, not live item average cost.

## 17. Edge Functions

Recommended v1/v1.5 functions:

| Function | Purpose |
|---|---|
| `ocr-document` | Fetch image, call Google Vision, parse/match, write OCR result |
| `retry-ocr-document` | Requeue failed OCR job with quota checks |
| `import-template-pack` | Admin-only validation/import of modular JSON packs |
| `opening-stock-import-preview` | Parse CSV/paste grid and produce a reviewable draft |
| `nightly-reconciliation` | Compare cached projections against truth views |
| `rebuild-shop-suggestions` | Recompute shop suggestion rows from template/setup defaults and learning profiles |

Posting truth stays in Postgres RPC functions, not Edge Functions, because it must be transactional with the database.

## 18. Open backend decisions before migration

1. Confirm v1 roles: organization roles `org_owner`/`org_admin`; shop roles likely `owner`/`cashier`; add `manager`, `accountant`, or `viewer` only if needed for pilot.
2. Auth method is decided: phone OTP for shop users on mobile and web; prefer WhatsApp OTP delivery through existing Meta/Facebook WhatsApp API access, with SMS fallback after testing.
3. Confirm Supabase region after a Somalia real-device latency test.
4. Confirm negative stock default for pilot UX. Current backend-safe default is `warn`.
5. Confirm whether void window is fixed at 7 days for owner self-service.
6. Overpayments are blocked in v1 posting RPCs; revisit only if unapplied credits become a product requirement.

## 19. Recommended next implementation order

1. Continue wiring Flutter to Supabase data: template-applied items, Sale, Receive, Payment, and Expense.
2. Replace the current Flutter owner-onboarding placeholder with the full setup flow: language, currency, template selection, opening stock, and worker invites.
3. Add OCR Edge Function flow for uploaded document images when ready for image-to-draft.
