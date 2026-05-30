# Architecture — Shop Management SaaS

## 1. High-level
```
   ┌─────────────────────┐         ┌──────────────────────────────┐
   │  Flutter app        │  HTTPS  │  Supabase (managed)          │
   │  (Android/iOS/Web)  │ ───────▶│  • Postgres (schema + RLS)   │
   │                     │         │  • Auth (phone OTP; staff SSO)│
   │  • i18n: en, so     │ Realtime│  • Storage (images)          │
   │  • Local cache      │ ◀───────│  • Edge Functions (OCR glue) │
   │  • Write queue      │         └──────────────┬───────────────┘
   └─────────────────────┘                        │
                                                  │ HTTPS
                                                  ▼
                                       ┌──────────────────────┐
                                       │ Google Cloud Vision  │
                                       │ (OCR; key in Edge    │
                                       │  Function env only)  │
                                       └──────────────────────┘
```

- Device never holds the Google Vision API key. It only talks to Supabase.
- All writes go through PostgREST/Supabase client → RLS enforces tenant isolation.
- Image uploads go to Storage; a Storage webhook (or a triggered Edge Function on document insert) kicks the OCR pipeline.

### Authentication and onboarding

Shop users authenticate with **phone OTP** on both mobile and web. The phone number is the login identity, but business rows reference the stable Supabase `auth.users.id`.

OTP delivery should prefer Dukan's existing Meta/Facebook WhatsApp API access where feasible, with Supabase Auth remaining the identity/session source of truth. SMS providers such as Twilio or Africa's Talking are fallback delivery channels, not the default assumption.

The Flutter app reads Supabase configuration from `--dart-define` values (`SUPABASE_URL`, `SUPABASE_ANON_KEY`). If either value is missing, the app shows a setup screen and does not initialize or touch the Supabase client. Phone input is normalized to E.164 (defaulting local numbers to Somalia `+252`). After login, the app lists shops by querying `public.shop` through RLS so both direct shop members and organization owners/admins see their authorized shops.

For mass adoption, the default owner path is self-serve:

1. Owner enters phone number and verifies OTP.
2. Dukan creates an organization, first shop, and owner membership.
3. Owner chooses language, currency, and business template.
4. Template applies starter setup.
5. Owner completes setup checklist and invites workers.

Workers/cashiers are invited or added by an owner/admin using their phone number. They cannot self-join a shop. Internal Dukan staff use staff auth such as email/password or SSO with platform roles, not the shopkeeper phone-first flow.

Access changes are handled by memberships. If a worker leaves, disable their `shop_membership`; historical rows keep `created_by` for audit. If a user loses a phone, they re-verify the same phone on a new device and old sessions should be revoked where supported. Access is current; audit is permanent.

Simultaneous login is allowed but should be visible and controllable. Owners/admins may use mobile plus web; workers should have a smaller active-device limit later. Settings should show active devices/sessions, support revoking other sessions, and require recent re-auth for sensitive actions such as owner transfer, user removal, business-phone changes, or report export.

## 2. Multi-tenancy

### Hierarchy
```
organization (1) ──< organization_membership >── user
       │
       └──< shop (1) ──< shop_membership >── user
              │
              ├──< item ──< item_alias
              │      ▲
              │      └─ stock_movement ── (writers only:)
              │                            └─ transaction_line, inventory_adjustment_line
              ├──< party ──< party_alias
              ├──< txn (logical transaction) ──< transaction_line
              │       └─ document (bono / receipt)
              ├──< payment ──< payment_allocation >── txn
              ├──< inventory_adjustment ──< inventory_adjustment_line
              ├──< location (single 'Default' in v1)
              ├──< expense_category   (seeded from platform template)
              ├──< template_application >── template (platform-layer)
              ├──< support_session ── (future hook; disabled in v1)
              └──< audit_log
```

### RLS pattern
Every business table:
```sql
shop_id uuid not null references shop(id)
```
Helper:
```sql
create function auth_can_access_shop(p_shop uuid) returns boolean
language sql stable as $$
  select exists (
    select 1 from shop_membership sm
    where sm.user_id = auth.uid()
      and sm.shop_id = p_shop
      and sm.is_active
  )
  or exists (
    select 1
    from shop s
    join organization_membership om on om.organization_id = s.organization_id
    join organization_role r on r.id = om.role_id
    where s.id = p_shop
      and om.user_id = auth.uid()
      and om.is_active
      and r.code in ('org_owner', 'org_admin')
  );
$$;
```
Policy template (applied to every business table):
```sql
create policy shop_isolation on <table>
  using (auth_can_access_shop(shop_id))
  with check (auth_can_access_shop(shop_id));
```
Role-based action gating (e.g., only Owner can void in v1) is enforced by RPC checks and additional policies that check direct shop roles plus org-owner equivalence where appropriate.

## 3. Schema sketch (illustrative, not final DDL)

See `backend-schema.md` for the migration-ready Supabase/Postgres schema draft, RLS plan, Storage policies, posting RPCs, and recommended migration order. This section remains the higher-level ER sketch.

### Reference tables (seeded; extensible by data, not code)
```
language(code pk, name)                       -- en, so
currency(code pk, symbol, decimals)           -- USD, SOS, ...
unit(id pk, shop_id null, code, default_label)
transaction_type(id pk, code, stock_effect, party_balance_effect,
                 requires_party, requires_items)
transaction_status(id pk, code)               -- draft, posted, void
payment_method(id pk, code)                   -- cash, mobile_money, bank
party_type(id pk, code)                       -- supplier, customer, both
document_type(id pk, code)                    -- bono, sale_receipt, expense_receipt
ocr_status(id pk, code)                       -- pending, processing, success, failed, manual
organization_role(id pk, code)                 -- org_owner, org_admin (v1)
shop_role(id pk, code)                         -- owner, cashier (v1)
                                             --   (manager / viewer deferred; support is platform staff)
adjustment_reason(id pk, code, is_increase bool null, is_system bool default false)
                                              -- v1: opening, spoilage, correction
location_kind(id pk, code)                    -- default (v1); storefront/backroom/warehouse/vehicle (v2)

-- Per-shop list table (not a global reference; seeded from platform template at setup):
expense_category(id pk, shop_id fk, code, name, name_translations jsonb,
                 is_active bool default true)

ref_translation(table_name, row_id, locale, label, primary key(table_name,row_id,locale))
```

### Search aliases (also used by OCR matching)
```
item_alias(id pk, shop_id fk, item_id fk, alias_text, source text,
           unique(shop_id, alias_text, item_id))
   -- source: 'manual' | 'ocr_correction'
party_alias(id pk, shop_id fk, party_id fk, alias_text, source text,
            unique(shop_id, alias_text, party_id))
```
Used in v1 by the item/party type-ahead pickers; used in v1.5 (OCR Phase 7) for fuzzy supplier/item matching during draft generation. Corrections made on the OCR Draft screen auto-write an alias row, so accuracy improves per shop over time.

### Tenancy
```
organization(id pk, name, plan_id, created_at)
shop(id pk, org_id fk, name, currency_code fk, timezone, default_language fk, created_at)
organization_membership(id pk, user_id fk auth.users, organization_id fk, role_id fk, is_active, created_at)
shop_membership(id pk, user_id fk auth.users, shop_id fk, role_id fk, is_active, created_at)
```

### Inventory & parties
```
unit(id pk, code, name, name_translations jsonb)

item(id pk, shop_id fk, name, name_translations jsonb null,
     base_unit_id fk unit,                  -- smallest unit the shop sells/tracks
     default_sale_unit_id fk unit,
     default_receive_unit_id fk unit,
     sale_price numeric(14,2) null, last_cost numeric(14,2) null,
     avg_cost numeric(14,4) null, current_stock numeric(14,3) default 0,
     reorder_threshold numeric(14,3) null,
     barcode text null,                       -- v1 hook; no scanner UI yet
     is_active bool default true,
     created_at, updated_at)
-- Note: `current_stock`, `avg_cost`, `last_cost` are cached projections of
-- stock_movement in the item's base unit. Single location in v1; split into
-- item_stock(item,location) in v2 when multi-location is added.

item_unit(id pk, shop_id fk, item_id fk item, unit_id fk unit,
         conversion_to_base numeric(14,6), -- 1 entered unit = N base units
         is_base_unit bool default false,
         allow_sale bool default true,
         allow_receive bool default true,
         sort_order int,
         unique(shop_id, item_id, unit_id))
-- Example: Candy ABC has base unit=piece. item_unit rows:
--   piece conversion_to_base=1,   allow_sale=true,  allow_receive=false
--   bag   conversion_to_base=100, allow_sale=true,  allow_receive=true
-- Receive 10 bags => +1000 pieces. Sale 3 pieces => -3 pieces.

party(id pk, shop_id fk, name, phone, type_id fk party_type,
      receivable numeric(14,2) default 0,   -- they owe us
      payable    numeric(14,2) default 0,   -- we owe them
      notes, is_active, created_at, updated_at)
```

### Catalog naming and translation model

For shared catalog/template data, translate the **product concept** and description, not the full item string:

```
catalog_product_concept(id pk, code, name_en, description_en null)
catalog_product_translation(concept_id fk, locale, name, description null)
catalog_item(id pk, concept_id fk, code unique, current_revision_id fk null)
catalog_item_revision(id pk, catalog_item_id fk, revision_number int,
                      name text, brand_name text null,
                      package_quantity numeric(14,3) null,
                      package_unit_code text null, variant text null,
                      category_code text,
                      base_unit_code text, default_sale_unit_code text,
                      default_receive_unit_code text,
                      suggested_sale_price numeric(14,2) null)
catalog_item_unit(id pk, catalog_item_id fk, revision_id fk,
                  unit_code text, conversion_to_base numeric(14,6),
                  is_base_unit bool, allow_sale bool, allow_receive bool)
```

Examples:

- Concept `sugar` translates to `Sonkor`; package `1kg` and brand stay structured.
- Concept `rice` translates to `Bariis`; `25kg`, type/variant, and brand remain attributes.
- Concept `flour` translates to `Bur`; `wheat`, `5kg`, and brand remain attributes.

Shop items are activated from `catalog_item_revision` through `activate_catalog_item()`. The shop row stores only operational state plus a denormalized posting projection (`name`, base/default unit IDs, unit conversions); local wording lives in `name_override`. Daily transactions still use shop-scoped `item` rows and snapshot item/unit labels on each transaction line.

### Transactions (generic spine)
```
document(id pk, shop_id fk, type_id fk document_type, storage_path,
         ocr_status_id fk, ocr_result jsonb null, uploaded_by, created_at)

txn(id pk, shop_id fk, type_id fk transaction_type, -- logical transaction; avoids SQL keyword quoting
    status_id fk transaction_status,
    party_id fk party null,
    occurred_at timestamptz, posted_at timestamptz null,
    total_amount numeric(14,2), paid_amount numeric(14,2) default 0,
    payment_method_id fk payment_method null,
    document_id fk document null,
    client_op_id text null,
    notes, created_by, created_at)

transaction_line(id pk, transaction_id fk, line_no int,
                 item_id fk item null,          -- null for expense lines
                 expense_category_id fk null,   -- non-null for expense
                 quantity numeric(14,3) null,   -- entered quantity
                 unit_id fk unit null,          -- entered unit
                 base_quantity numeric(14,3) null, -- quantity converted to item base unit
                 unit_amount numeric(14,4) null, -- price/cost per entered unit
                 item_name_snapshot text null,  -- immutable item label at posting time
                 unit_code_snapshot text null,
                 unit_conversion_to_base_snapshot numeric(14,6) null,
                 catalog_revision_id fk catalog_item_revision null,
                 line_total numeric(14,2) not null,
                 cogs_unit_cost numeric(14,4) null,   -- per base unit at sale posting
                 cogs_total     numeric(14,2) null)   -- snapshot at sale posting
-- Per-type CHECK constraints (enforced in DB):
--   sale/receive: item_id, quantity, unit_id, base_quantity, unit_amount NOT NULL; expense_category_id NULL
--   expense:      expense_category_id NOT NULL; item_id, quantity NULL
-- Implemented via a single CHECK that switches on the parent transaction's type_id
-- (denormalize type_id onto the line, or enforce in posting RPCs + trigger).

payment(id pk, shop_id fk, party_id fk null, direction char(1) check (direction in ('I','O')),
        amount numeric(14,2), method_id fk payment_method,
        occurred_at, document_id fk document null, notes, created_by)
-- Many-to-many allocation: one payment can settle multiple transactions
-- (and one transaction can receive multiple payments). Unapplied = amount − Σ allocations.
payment_allocation(id pk, payment_id fk, transaction_id fk, amount numeric(14,2),
                   unique(payment_id, transaction_id))

stock_movement(id pk, shop_id fk, item_id fk,
               location_id fk location null,    -- v1 hook; seeded 'Default' per shop
               transaction_line_id fk transaction_line null,
               inventory_adjustment_line_id fk inventory_adjustment_line null,
               quantity_delta numeric(14,3),    -- in item base unit; + receive, - sale
               unit_cost numeric(14,4) null,    -- cost per base unit
               occurred_at, created_at)

-- Inventory adjustments (the human-facing "voucher" for non-money stock changes)
adjustment_reason(id pk, code, is_increase bool null)
  -- seeded v1: opening, spoilage, correction
inventory_adjustment(id pk, shop_id fk, reason_id fk adjustment_reason,
                     occurred_at, notes, document_id fk document null,
                     approved_by, created_by, created_at)
inventory_adjustment_line(id pk, adjustment_id fk, item_id fk,
                          quantity_delta numeric(14,3), -- in item base unit
                          unit_cost numeric(14,4) null)
-- Posting an adjustment writes stock_movement rows linked through
-- inventory_adjustment_line_id.
-- Outbound adjustments (spoilage, correction-) snapshot current avg_cost into
-- unit_cost so P&L stays honest.
-- Opening stock at onboarding is a mandatory inventory_adjustment with
-- reason=opening; without it, reports are wrong from day one.

-- Idempotency hooks (v1 hook for future offline-first sync)
-- txn.client_op_id                  text null unique per (shop_id, client_op_id)
-- payment.client_op_id              text null unique per (shop_id, client_op_id)
-- inventory_adjustment.client_op_id text null unique per (shop_id, client_op_id)

-- Location (v1 hook only — single 'Default' row per shop)
location(id pk, shop_id fk, name, kind, is_active, created_at)
  -- kind seeded: 'default'; future: 'storefront', 'backroom', 'warehouse', 'vehicle'

-- Voids / corrections:
txn.reverses_transaction_id uuid null references txn(id)
-- Invariants:
--   * Posted transactions are immutable (no edits to header or lines).
--   * Voiding = insert a new transaction with reverses_transaction_id set; posting
--     inverts stock_movements and party balance effects of the original.
--   * Reversing a Receive whose stock has already been sold is allowed but flagged
--     (stock can go negative; reconciliation report surfaces it).
--   * Payments are reversed by a refund Payment with opposite direction +
--     payment_allocation entries that undo prior allocations.
--   * Only shop role 'owner' may post voids/refunds in v1 (enforced by RPC/RLS).
```

### Cross-row tenant integrity
RLS alone does **not** prevent a user from attaching another shop's `party_id` or `item_id` to a transaction they own. Enforced via **composite foreign keys on `shop_id`**:
- `(shop_id, party_id) → party(shop_id, id)`
- `(shop_id, item_id) → item(shop_id, id)` on `transaction_line` and `stock_movement`
- Same pattern for `document_id`, `expense_category_id`, `transaction_id` on lines/payments/allocations.
This requires composite unique constraints `(shop_id, id)` on parent tables.

### RLS — no JWT shop claim
RLS policies check `shop_membership` and `organization_membership` directly via `auth.uid()` and the row's `shop_id`. The app may keep a `current_shop_id` in app state for UX, but it is **not** trusted for authorization. Avoids stale-claim risk when memberships change.

### Why one logical transaction table?
Sale, Receive, and Expense share 90% of fields (header + lines + document + payment). Splitting them would duplicate schema and code. The `transaction_type` reference row drives behaviour:
- `stock_effect = +1` (Receive) → insert positive `stock_movement` per line, update `avg_cost` & `last_cost`.
- `stock_effect = −1` (Sale) → insert negative `stock_movement` per line at current `avg_cost` (for COGS).
- `stock_effect = 0` (Expense) → no stock movement.
- `party_balance_effect` decides whether unpaid amount lands in `receivable` (sale) or `payable` (receive).
- `requires_items / requires_party` drive UI validation generically.

Posting is done through explicit RPCs such as `post_sale`, `post_receive`, `post_payment`, `post_expense`, and `post_inventory_adjustment`, backed by a shared posting engine that reads the type row and applies common effects (stock movement sign, party balance update, COGS snapshot on sale). **Honest scope of the "registration pattern":** common dimensions (stock effect, balance effect, validation flags) are pure data and adding a new type that fits those dimensions is data-only. Genuinely new behaviour (e.g., a future "Transfer between shops") will still need a small typed handler — this is a controlled registry of strategies, not "no code ever". `payment.direction` is deliberately an internal technical enum; `stock_movement` uses typed source FKs for integrity.

## 4. OCR pipeline

```
Flutter → upload image to Storage (path: shop_id/documents/uuid.jpg)
        → insert document row (ocr_status = pending)
Edge Function on document insert (idempotent via ocr_jobs):
  1. Fetch image from Storage
  2. Call Google Cloud Vision (DOCUMENT_TEXT_DETECTION)
  3. Light parser (heuristics: supplier line, item rows, totals)
  4. Match supplier text → party + party_alias (pg_trgm fuzzy match)
  5. Match each line's item text → item + item_alias (pg_trgm fuzzy match)
  6. Write enriched ocr_result JSON (raw text + parsed + matched candidates + confidences)
  7. Set ocr_status = success | failed
Flutter (Realtime subscription on the document):
  - On success: open "Review Draft" screen pre-filled with supplier + items;
                fields below confidence threshold are highlighted "review me"
  - User edits → confirm → creates transaction linked to this document
  - User corrections write item_alias / party_alias rows (learning loop)
  - On failure: fall back to manual entry, document is still attached
```

Notes:
- API key lives only in the Edge Function's environment variables.
- `ocr_jobs(document_id unique, status, attempts, locked_at, last_error)` provides idempotency, exponential backoff, and prevents duplicate Vision calls.
- Upload validation: max image size (e.g., 8 MB), allowed content types (`image/jpeg`, `image/png`, `image/webp`), per-shop daily OCR quota to cap cost.
- Raw Vision text stored separately from parsed JSON for debugging and parser improvement.
- Manual "Retry OCR" button on documents that failed.
- Matching thresholds: ≥ 0.85 → auto-select; 0.6–0.85 → suggestion chips; < 0.6 → "Create new" inline.
- Parser is intentionally conservative — **never auto-posts**; user always confirms.

## 5. i18n

- **UI strings:** Flutter `intl` + ARB files (`lib/l10n/app_en.arb`, `app_so.arb`).
- **Reference data:** single `ref_translation(table_name, row_id, locale, label)` table. Client queries `ref_translation` joined with the lookup, filtered by user's locale (fallback to English).
- **Catalog/template product names:** translate only the product concept and description (`Sugar` → `Sonkor`, `Rice` → `Bariis`). Brand, quantity, size, and package/unit attributes stay structured and are composed into the display name.
- **User content** (shop item names, party names): stored as entered; shop items may optionally point to a catalog item and/or override the display name.
- **Locale resolution:** user setting → shop default → app default (en).
- **Formatting:** numbers/currency/dates via `intl` with shop currency + timezone.

## 6. Offline / connectivity strategy (MVP-light)
- Read cache: last-seen items, parties, today's transactions stored locally (e.g., Drift or Isar).
- Write queue: mutations queued locally; replayed on reconnect with idempotency keys (`client_op_id` column on transactions/payments).
- Conflict policy: server is authoritative; on conflict, surface to user with both versions.
- Full offline-first deferred to post-pilot.

## 7. Security & ops
- **Auth:** shop users use phone OTP on mobile and web; OTP delivery prefers WhatsApp through existing Meta/Facebook WhatsApp API access, with SMS/provider fallback after real-device testing. Internal Dukan staff use email/password or SSO with platform roles.
- RLS on every business table; **deny by default**, allow via direct shop membership or org-level access. Future in-app support sessions may add setup-scoped support access, but v1 disables support codes.
- Storage policies mirror RLS (path-prefixed by `shop_id`).
- Audit columns on every table (`created_by`, `created_at`, `updated_at`); structured `audit_log` for setup/support changes.
- Append-only `txn` posting; corrections via reversing entries (`reverses_transaction_id`).
- Backups: rely on Supabase PITR; nightly logical export to object storage for pilot.
- Monitoring: Supabase logs + Sentry in Flutter; basic uptime check on Edge Functions.

## 7a. Denormalized fields & reconciliation
`party.receivable`, `party.payable`, `item.current_stock`, and `item.avg_cost` are **cached projections** maintained only by posting procedures (`post_sale`, `post_receive`, `post_payment`, `post_inventory_adjustment`, void/reversal procedures). To detect drift:
- Views `v_party_balance_truth` and `v_item_stock_truth` recompute from posted transaction/payment ledgers and `stock_movement`.
- Nightly Edge Function compares cached vs truth, logs discrepancies, and (optionally) auto-heals.

## 8. Reporting approach
- **Live queries** (Postgres views) for dashboards and lists: `v_sales_report`, `v_receive_report`, `v_expense_report`, `v_payment_report`, `v_item_stock_truth`, and `v_party_balance_truth`.
- **Daily/monthly rollups** are views: `v_daily_profit`, `v_monthly_profit`, `v_monthly_sales`, and `v_monthly_expenses`. Weekly rollups are not part of v1.
- **Profit** is computed from posted sale-line COGS snapshots and posted expense lines, never from live item average cost.
- **Precompute where practical:** high-traffic suggestions/facts should be updated during posting or scheduled jobs so the app reads ready rows instead of repeating ranking/threshold checks.
- If perf becomes an issue post-pilot, replace high-traffic rollup views with scheduled summary tables while keeping the same user-facing numbers.

## 8aa. Platform layer: templates, onboarding, help channels, audit

To support the "decision-free daily use" UX principle (see `ux.md` § 3a), shop setup is carried by a **platform layer** of cross-tenant data and a controlled onboarding state machine.

The staff-facing UI for this layer is the admin portal described in `admin-portal.md`. Recommended stack: React / Next.js, sharing the same Supabase backend and RLS boundaries as the shop app.

### Platform tables (cross-tenant; managed by the product team, read-only to shops)
```
template(id pk, kind, name, locale_default, version, is_active, created_at)
   -- kind: 'shop_starter' (grocery, restaurant, pharmacy, hardware, electronics, clothing)
   --       'receipt_layout', 'expense_categories', 'units', 'adjustment_reasons'
template_pack(id pk, template_id fk, code, version, is_required bool,
              file_path text, checksum text null)
   -- examples: catalog, settings, quick_actions, supplier_mappings,
   -- quantity_suggestions, aliases, ocr_mappings, expense_categories, dashboard
template_item(template_id fk, catalog_item_id fk null,
              catalog_revision_id fk null,
              custom_name text null, name_override text null,
              base_unit_code_override text null,
              default_sale_unit_code_override text null,
              default_receive_unit_code_override text null,
              suggested_sale_price_override numeric(14,2) null,
              reorder_threshold_override numeric(14,3) null, sort_order int)
template_item_unit(template_id fk, item_code text, unit_code text,
                   conversion_to_base numeric(14,6),
                   allow_sale bool, allow_receive bool, sort_order int)
template_expense_category(template_id fk, code, name, name_translations jsonb)
template_unit(template_id fk, code, name, name_translations jsonb)
template_adjustment_reason(template_id fk, code, name, name_translations jsonb,
                           is_increase bool null, is_system bool default false)
template_setting(template_id fk, key text, value jsonb)
template_quick_action(template_id fk, screen text, position int,
                     item_code text null, expense_category_code text null,
                     label jsonb null)
template_item_alias(template_id fk, item_code text, locale text, alias text,
                   source text default 'template')
template_party_alias(template_id fk, party_code text, locale text, alias text,
                    source text default 'template')
template_supplier_item(template_id fk, supplier_type_code text, item_code text,
                      usual_unit_code text null, cost_entry_mode text null,
                      sort_order int)
template_quantity_suggestion(template_id fk, item_code text null,
                            category text null, context text,
                            quantity numeric(14,3), unit_code text)
```

Templates are **operating profiles**, not product lists. They are composed from modular configuration packs (`catalog.json`, `settings.json`, `quick-actions.json`, etc.) so catalog configuration, UX shortcuts, OCR mappings, and dashboard defaults can evolve independently. They seed products, translations, aliases, settings, fast-entry layouts, supplier-item mappings, and quantity suggestions so daily flows start with useful defaults. See `templates-and-learning.md`.

### Application & traceability (per shop)
```
template_application(id pk, shop_id fk, template_id fk, template_version int,
                     applied_by, applied_at, merge_strategy text)
template_pack_application(id pk, template_application_id fk, pack_code text,
                          pack_version int, applied_at, status text)
   -- 'first_apply'  → insert all rows
   -- 'merge_update' → insert new rows, leave existing shop-modified rows alone
```
Stored procedure `apply_template(shop_id, template_id, pack_codes)` is **idempotent**: it records the template/version/packs applied, creates only missing setup rows matched by stable shop codes, and uses `activate_catalog_item()` for catalog-backed items. Shop edits are never overwritten when a newer template version is re-applied, and stock/cost fields are not seeded by templates.

### Shop-specific learning profile (per shop; UX acceleration only)
```
shop_item_usage(shop_id fk, item_id fk, sale_count int, receive_count int,
               total_sale_base_quantity numeric(14,3),
               total_receive_base_quantity numeric(14,3),
               last_sale_at timestamptz null, last_receive_at timestamptz null)
shop_item_entry_profile(shop_id fk, item_id fk, context text,
                       unit_id fk, quantity numeric(14,3),
                       usage_count int, last_unit_amount numeric(14,4) null,
                       last_used_at timestamptz null)
shop_supplier_item_profile(shop_id fk, supplier_id fk, item_id fk, unit_id fk,
                          receive_count int, total_base_quantity numeric(14,3),
                          last_unit_cost numeric(14,4) null,
                          last_received_at timestamptz null)
shop_party_usage(shop_id fk, party_id fk, sale_count int, receive_count int,
                payment_count int, last_sale_at timestamptz null,
                last_receive_at timestamptz null, last_payment_at timestamptz null)
shop_quick_action(shop_id fk, screen text, position int, item_id fk null,
                  expense_category_id fk null, source text)
shop_suggestion(shop_id fk, screen text, context_key text, target_key text,
               suggestion_type text, item_id fk null, party_id fk null,
               expense_category_id fk null, payment_method_id fk null,
               unit_id fk null, quantity numeric(14,3) null, source text,
               rank int, is_active bool, usage_count int, last_used_at timestamptz null)
ocr_correction(shop_id fk, document_id fk, raw_text text, accepted_entity_table text,
               accepted_entity_id uuid, confidence numeric, created_at timestamptz)
```

These rows are not accounting truth and never post transactions. They only rank suggestions, pre-fill safe defaults, and learn aliases/corrections after the shopkeeper confirms an entry. Daily screens read `v_shop_suggestions` ordered by precomputed `rank`; ranking thresholds are handled by template/posting triggers or scheduled rebuilds, not by repeated mobile read-time checks.

### Onboarding state machine on `shop`
```
shop.setup_status text default 'not_started'
   -- not_started → template_applied → opening_stock_done → ready
shop.setup_completed_at timestamptz null
```
Daily flows (Sale, Receive, Payment, Expense) are gated behind `setup_status = 'ready'`. The Settings UI shows a one-tap checklist that drives the state machine.

### V1 help channels and future support sessions

For v1/pilot, Dukan does **not** use in-app support codes. The shop app has a Help icon that opens:

- WhatsApp chat.
- Email support.

Support is therefore out-of-band in v1. Support can guide the shopkeeper through setup steps or use internal/admin tools for permitted setup work, but the shopkeeper does not grant app access through a 6-digit code.

Future hook (not enabled in v1):
```
support_session(id pk, shop_id fk, support_user_id fk auth.users,
                granted_by fk auth.users, code_hash text,
                granted_at, expires_at, revoked_at null, purpose text)
```

If enabled after v1, RLS for users with a platform support role checks `support_session` (active, non-expired, non-revoked) **in addition to** support assignment rules. The support role remains **strictly setup-only**: explicit deny on insert/update/delete of `txn`, `payment`, `payment_allocation`, `inventory_adjustment`, and any posting procedures. Support can never void, refund, or post on behalf of the shop — those are owner-only.

### Audit log
```
audit_log(id pk, shop_id fk, actor_user_id fk, support_session_id fk null,
          entity_table text, entity_id uuid, action text,
          diff jsonb, occurred_at)
   -- action: 'insert' | 'update' | 'delete' | 'apply_template' | 'grant_support' | ...
```
Written by triggers on setup-related tables and by `apply_template()` / support events. Future in-app support-session changes would be tagged with the session ID for after-the-fact review.

### Optional: CSV/Excel import for opening stock
For shops with an existing spreadsheet, a CSV import path produces a single `inventory_adjustment` (reason = `opening`) per import session. Same audit and idempotency guarantees as templates.

## 8b. Two spines, one system
Although the system has a unified logical transaction "money spine" (`txn` physically), inventory has its own parallel **quantity spine**:

```
                MONEY SPINE                          QUANTITY SPINE
    transaction ── transaction_line ─────▶ stock_movement ◀───── inventory_adjustment ── _line
        │                                       ▲                          ▲
        ▼                                       │                          │
     payment ── payment_allocation               └── (only writers) ───────┘
        │
        ▼
    party.receivable / payable  (cached)        item.current_stock / avg_cost (cached)
```

- `transaction_line` (Sale/Receive) writes to `stock_movement` via the posting procedure.
- `inventory_adjustment_line` (opening / spoilage / correction) writes to `stock_movement` via its own posting procedure.
- **Nothing else writes to `stock_movement`.** This is the invariant that prevents ERP-creep.

### Item units and split packages

Daily UX should not ask the shopkeeper to model package splits. Setup/template data defines the conversion once:

- If an item is never split, its base unit and sale/receive unit can be the same (`bag`, `carton`, `piece`).
- If a received package is split for sale, the **base unit is the smallest unit the shop sells**.
- Receive units convert into base units; sale units also convert into base units.
- `stock_movement.quantity_delta`, `item.current_stock`, and `item.avg_cost` are always in the base unit.

Example: `Candy ABC`

```
base unit: piece
receive unit: bag
sale units: piece, bag
conversion: 1 bag = 100 pieces

Receive 10 bags  -> stock_movement +1000 pieces
Sale 3 pieces    -> stock_movement -3 pieces
Sale 1 bag       -> stock_movement -100 pieces
```

This preserves UX speed: during Receive the user enters `10 bags`; during Sale the default chip is `1 piece`. The shopkeeper never runs a separate "split package" workflow during daily use.

## 9. What this architecture deliberately avoids (for now)
- Stock-count workflow (adjustments cover v1; `stock_count` tables added in v2).
- First-class returns flow (reversing transactions in v1).
- Multi-location / transfers / warehouses (single seeded `Default` location; `location_id` hook in place).
- Product variants, kits, BOM (use separate items in v1).
- Multi-currency per shop (enforce single currency per shop in v1).
- Promotions / discount engine (per-line price edit only).
- Tax engine (at most one optional shop-level rate).
- Approval workflows beyond role-gated voids.
- Procurement (POs, GRNs).
- Hardware integrations (scanners, printers, cash drawers).
- Loyalty / store credit.
- Barcode scanning hardware (nullable `barcode` column added; UI deferred).
- Separate Sale/Receive/Expense tables (unified money spine instead).
- PG enums for any user-visible category (reference tables instead).
- Full double-entry ledger (focused operational ledger; GL can layer later without breaking the spine).
- Full offline-first sync engine (`client_op_id` hooks in place; engine deferred).
