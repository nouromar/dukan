# Shop Management SaaS — Plan

> **North-star principle:** UX is the #1 success factor for this product. The target user is a shopkeeper who is not a tech-savvy user. See **`docs/ux.md`** for the speed contract, interaction rules, and screen designs that govern every feature.
>
> **Corollary — decision-free daily use:** every decision is made **once, at setup** (via one-tap template or concierge/support-assisted setup). Daily flows contain zero configuration questions. See `docs/ux.md` § 3a.

## 1. Product summary
A mobile-first (also web) multi-tenant SaaS that helps small shop owners — many with low tech literacy and primarily Somali/English speakers — to:
- Track **inventory** (no barcode scanner; manual + image-assisted entry).
- Record **purchases (Receive)** from suppliers using a paper *bono* (image + structured data).
- Record **sales** (cash or debt).
- Track **supplier payables** and **customer receivables**.
- Record **simple expenses** (rent, electricity, salary, etc.).
- View **reports & dashboards** (receivables, payables, daily/monthly/custom profit, etc.).
- Operate in **English** and **Somali** from day one (architecture supports adding more later).

## 2. Tech stack (decided)
- **Shop app frontend:** Flutter (Android/iOS first; Flutter Web optional for shop app later).
- **Admin web frontend:** React / Next.js for organization, multi-shop, setup, and support administration.
- **Backend / data:** Supabase (Postgres + Auth + Storage + Edge Functions + Realtime).
- **OCR:** Google Cloud Vision (called from a Supabase Edge Function — keys never on device).
- **Offline:** mostly online; basic caching + write-queue for short outages (not full offline-first).
- **i18n:** Flutter ARB files (`intl`), English + Somali; reference data uses a translations table.

## 3. Design principles (aligned with user's long-term philosophy)
- **Generic spine over service-specific branches.** One logical transaction header table (physical table: `txn`, to avoid SQL keyword quoting) + one `transaction_lines` table cover Sale, Receive, and Expense. One `parties` table covers Suppliers, Customers, or Both. One `documents` table covers bono images, receipt images, expense receipts.
- **Reference tables over PG enums.** Every "type/status/method/role" is a row in a small lookup table (with translations) so we never need a migration to add a new option.
- **Registration patterns over if/elif.** Transaction-type behaviour (stock effect, balance effect, sign) is data in the reference table, not branches in code.
- **Multi-tenant from day one.** Every business row carries `shop_id`; Postgres Row Level Security (RLS) enforces isolation.
- **Money & quantities as `numeric`** (never floats). Currency, timezone, locale per shop.
- **Audit trail.** Append-only `transactions` + `payments` + `stock_movements`; corrections via reversing entries, not destructive edits.
- **Simple UX for low-literacy users.** Icon-first, big tap targets, numeric pads, photo-first capture, confirm-before-save, minimal jargon, both languages always one tap away.

## 4. Domain model (logical)

### Core entities
- **Organization** → owns one or more **Shops** → has top owners/admins via **OrganizationMembership**; each **Shop** has cashiers/shop users via **ShopMembership**.
- **Shop** → has **Items**, **Parties**, **Transactions**, **Payments**, **Documents**, **Expense Categories**.
- **Item** (inventory product) → has a base unit plus allowed sale/receive units (`item_unit` conversions). `current_stock`, `avg_cost`, `last_cost` are **cached projections of `stock_movement` in the base unit** (single location in v1).
- **Party** (generic spine) → supplier, customer, or both; carries cached `receivable` and `payable`.
- **Transaction** (generic spine) → header with `type` (Sale / Receive / Expense), `party_id` (nullable for expense), `occurred_at`, `total`, `paid_amount`, `status`, `payment_method`, `document_id`, `notes`, `reverses_transaction_id` (for voids).
- **TransactionLine** → `item_id` *or* `expense_category_id`, `quantity`, `unit_amount`, `line_total`, plus `cogs_unit_cost` / `cogs_total` snapshotted at sale posting.
- **Payment** → money in/out against a party; settled against transactions via the **PaymentAllocation** join table (M2M, supports partial and split payments).
- **StockMovement** → the immutable inventory ledger; written **only** by `transaction_line` posting and `inventory_adjustment_line` posting.
- **InventoryAdjustment** (+ lines) → human-facing voucher for non-money stock changes (opening, spoilage, correction); carries reason, notes, optional photo, approver.
- **Document** → uploaded image (bono, receipt) in Supabase Storage; has `ocr_status` and `ocr_result` (parsed JSON + matched supplier/item candidates).
- **Platform layer** (cross-tenant): **Template** (shop-kind starter packs), **TemplateApplication** (per-shop trace), **Help channel config** (WhatsApp/email for v1), optional future **SupportSession** (disabled in v1), **AuditLog**. See `architecture.md` § 8aa.

### Reference tables (with `ref_translations` for i18n)
`transaction_types`, `transaction_statuses`, `payment_methods`, `party_types`, `document_types`, `ocr_statuses`, `organization_roles` (org_owner, org_admin), `shop_roles` (owner, cashier; manager/viewer deferred), platform staff roles (admin/support, setup-only), `units`, `currencies`, `languages`, `adjustment_reasons` (opening, spoilage, correction), `location_kinds`. Shop-scoped per-shop list tables: `expense_category` (seeded from a platform template at setup; shop can edit).

`transaction_types` carries behaviour columns:
- `stock_effect` (+1 receive, −1 sale, 0 expense)
- `party_balance_effect` (+payable on receive, +receivable on sale, 0 expense)
- `requires_party` (bool)
- `requires_items` (bool)

This lets the engine handle new transaction types by inserting a row, not adding code branches.

### Multi-tenancy & security
- Every business table has `shop_id NOT NULL` + an index.
- RLS policy: a row is visible/writable only if the requesting user has active `shop_membership` for that `shop_id` or org-level access through `organization_membership` (looked up via `auth.uid()`).
- **No JWT shop claim is trusted for authorization.** The app may hold `current_shop_id` in app state for UX only.
- **Composite foreign keys on `shop_id`** enforce cross-row tenant integrity (RLS alone does not).
- Storage uses private bucket `shop-documents`; object names are `{shop_id}/documents/{document_id}/image.(jpg|jpeg|png|webp)` and policies verify the matching `document` row plus shop access.
- V1 support uses a Help icon that opens WhatsApp/email. In-app support codes are disabled for v1. Any future support-session access must be setup-only and cannot post transactions or payments.

### i18n strategy
- **UI strings:** Flutter ARB files (`app_en.arb`, `app_so.arb`).
- **Reference data labels:** `ref_translations(table_name, row_id, locale, label)` — a single table for all lookups.
- **Catalog/template product names:** translate the product concept and description only; brand, quantity, size, and package/unit attributes stay structured and are composed into the display name.
- **User-entered names** (shop item names, party names): stored as-is; shop items may optionally point to a shared catalog item and override the display name.
- **Shop default language** + **user preferred language**; user setting wins.

## 5. Key flows (MVP)

### 5.1 Receive (purchase from supplier)
1. Tap **Receive** → choose/create **Supplier** (most-recent as chips, type-ahead below).
2. **Snap the bono** — strongly defaulted; "I don't have a bono" link skips it (rule: no truly-required fields). When taken, photo uploads to Storage → `document` row with `ocr_status = pending`.
3. Add lines: Item (type-ahead with aliases), Quantity (numpad), Cost with **per-unit ↔ line-total toggle** (the other is auto-computed).
4. Confirm: bono total field (soft warning on mismatch); **Paid Now / Credit** slider (default 0 paid).
5. Save → `transaction (type=Receive)` + `transaction_lines` + `stock_movements` + optional `payment` + `payment_allocation`.
6. (Phase 7) OCR populates a Draft pre-filled with matched supplier and items via `item_alias`/`party_alias`; user reviews and confirms.

### 5.2 Sale
1. Tap **Sale** → pick items from the favorites grid (tap = +1; long-press = qty/price override). Picker stays open across taps.
2. Cart strip shows count + total always visible.
3. Default = **CASH** (paid in full). One tap to switch to **DEBT** (opens inline customer search; customer required for debt). **Partial** is a power option via long-press on the CASH/DEBT toggle (slider to set amount paid now).
4. (Optional) Receipt photo via small camera icon on Confirm.
5. CONFIRM → optimistic save → "Saved. Undo?" toast (10s) → screen resets for next sale. Posts `transaction (type=Sale)` + lines + stock decrement (with COGS snapshot) + optional `payment` + `payment_allocation`.

### 5.3 Settle balances
- **Customer pays** → `Payment (in)` against customer; optionally allocate to specific debt sale(s).
- **Pay supplier** → `Payment (out)` against supplier.
- Party balance recomputed; receipt image optional.

### 5.4 Expense
- Pick **Expense category** (rent/electricity/salary/other — shop-managed list).
- Amount, date, optional photo, optional note.
- Creates `transaction (type=Expense)` with a single line referencing the category.

### 5.5 Reports & dashboard (MVP)
- **Today's summary card:** sales total, cash collected, expenses, gross profit.
- **Receivables list** (customers who owe), sortable by amount/age.
- **Payables list** (suppliers we owe).
- **Sales transactions** list with filters (date range, customer, cash/debt).
- **Receive transactions** list with filters.
- **Profit report:** daily / monthly / custom range (no weekly v1 rollup). Profit = Σ(sale line revenue − snapshotted sale COGS) − expenses in range.
- **Low-stock alert** (item `current_stock` ≤ `reorder_threshold`).

### 5.6 OCR pipeline (Phase 7)
- Image upload → Storage event → Edge Function → Google Cloud Vision → light parser (regex + heuristics for supplier name, line items, totals) → **matching step**: fuzzy-match parsed supplier text against `party` + `party_alias` and each line's item text against `item` + `item_alias` (Postgres `pg_trgm`); attach `candidate_party_id`, `candidate_item_id`, and confidence to each parsed entity.
- Enriched JSON written to `document.ocr_result`; app subscribes via Realtime → opens a **Draft** screen with pre-filled supplier and items; user edits → confirms → posts as real transaction.
- Corrections feed `item_alias` / `party_alias` automatically so matching improves per shop over time.
- Always require human confirmation before posting (no auto-post).

## 6. UX
See **`docs/ux.md`** — the binding reference for UX principles, speed contract, screen designs, copy rules, anti-patterns, and process. See **`docs/ux-screens.md`** for the full screen map and Level A daily-flow designs. See **`docs/templates-and-learning.md`** for setup templates, fast-entry mappings, and shop-specific learning rules that keep daily flows decision-free. See **`docs/admin-portal.md`** for the staff-facing setup/support console. See **`docs/backend-schema.md`** for the Supabase/Postgres schema, RLS, RPC posting functions, storage policies, and migration order.

## 7. Phased roadmap

| Phase | Scope | Outcome |
|-------|-------|---------|
| 0 | This plan + architecture doc + UX doc | Approved direction |
| 1 | Supabase project, schema, RLS, reference data, auth, organization/shop memberships, core RPC posting functions from `docs/backend-schema.md`, Flutter app skeleton, i18n scaffolding (en, so) | Login → pick shop → empty home with backend foundation ready |
| **1.5** | **Complete UX screen map, then Sale/Receive/Payment/Expense Flutter prototype (mock data) + usability testing with 2–3 real shopkeepers in Somali against the speed contract in `ux.md` and screen coverage in `ux-screens.md`. Iterate until metrics are hit.** | **UX validated before backend wiring** |
| **1.6** | **Onboarding & modular operating templates: platform-level `template` + `template_pack` tables (catalog, settings, quick-action layouts, aliases, supplier-item mappings, quantity chips, OCR mappings, expense categories, dashboard defaults), `apply_template()` procedure, shop-specific learning profile, `shop.setup_status` state machine, v1 Help channel config (WhatsApp/email; no support codes), audit log, and a small React/Next.js admin portal for organization, multi-shop, setup, and support administration. Concierge-assisted setup tooling.** | **New organizations/shops can be set up in minutes with one tap or with support help; daily entry starts fast and gets faster** |
| 2 | Items + Units + Parties (supplier/customer) CRUD + `item_alias` / `party_alias` for fast search | Can manage inventory & contacts |
| 3 | Receive flow (manual entry + bono image upload, no OCR yet) + opening-stock onboarding | Stock and payables update |
| 4 | Sale flow (cash, debt, partial) + stock decrement + receivables | End-to-end sale works |
| 5 | Payments (in/out) + payment allocations + balance reconciliation | Settle customer/supplier balances |
| 6 | Expenses + expense categories | Full P&L data captured |
| 7 | OCR pipeline (bono + receipt → draft with supplier/item matching via aliases) via Edge Function + Google Vision | Reduce manual typing |
| 8 | Reports & dashboard (receivables, payables, sales, profit, low-stock) + reconciliation views | Owner insights |
| 9 | Pilot hardening: Somali copy review, UX speed audit, perf, crash reporting, onboarding, CSV export, owner-assisted correction tooling | Ready for pilot shops |
| 10+ | Post-pilot: pricing/plans, stock counts as workflow, first-class returns, more languages, advanced reports, hardware printer, optional barcode, etc. | Scale |

## 7a. V1 scope vs growth hooks (avoid becoming an ERP)

**Principle:** build the minimum that's *correct*; leave hooks (columns, IDs, separations) so the next step is a migration, not a rewrite.

### Build in v1 (pilot)
- **Money spine:** `txn` (logical Transaction: Sale, Receive, Expense) + `transaction_line` + `payment` + `payment_allocation` + `document`. Posted = immutable; void via reversing entry. COGS snapshotted on sale lines.
- **Inventory spine:** `item` with embedded `current_stock`, `avg_cost`, `last_cost` (single location, single row), plus `item_unit` conversions for receive/sale units. `stock_movement` as the immutable ledger in the item's base unit. `inventory_adjustment` (+ `_line`) with an `adjustment_reason` reference table — v1 reasons: `opening`, `spoilage`, `correction`.
- **Catalog inheritance:** central `catalog_item` + immutable `catalog_item_revision` + `catalog_item_unit`; shops activate catalog rows into small shop-owned `item`/`item_unit` projections with local overrides instead of copying all product metadata blindly.
- **Opening stock flow** at shop onboarding (mandatory — otherwise every report lies from day one).
- **Parties & balances:** `party` (supplier/customer/both) with cached `receivable`, `payable`; payments + allocations.
- **Aliases:** `item_alias`, `party_alias` (used by fast search in v1; reused by OCR matching in v1.5).
- **Platform layer:** modular `template` / `template_pack`, `template_application`, v1 help-channel config, future `support_session`, `audit_log`, `shop.setup_status` state machine.
- **Entry acceleration:** template-seeded settings, quick actions, aliases, supplier-item mappings, quantity chips, and shop-scoped learning profiles that precompute Sale/Receive suggestions without auto-posting.
- **Split-package handling:** base stock unit is the smallest unit the shop sells; received packages convert to that base unit (e.g., 10 candy bags × 100 pieces = +1000 pieces) while Sale/Receive screens stay simple.
- **Reports:** today's summary, receivables, payables, sales list, receive list, low-stock, profit (daily/monthly/custom).
- **Foundations:** en + so from day one; RLS + composite `shop_id` FKs from day one.

### Design for, don't build (v2+)
Add these as inert hooks now so they cost nothing in v1:

| Future capability | Hook to add now | v1 cost |
|---|---|---|
| Multi-location per shop | `location_id` on `stock_movement` (+ single seeded `Default` location per shop) | one column |
| Stock counts | none — adjustments cover v1; add `stock_count` tables in v2 | none |
| Returns (customer/supplier) | model as reversing transactions in v1 (manual); first-class flow in v2 | none |
| Repack / conversions | handle ad-hoc via `inventory_adjustment` in v1 | none |
| Multi-currency per shop | reference table exists; **enforce one currency per shop** in v1 | none |
| Per-item variants | model as separate items in v1; add `variant` table later | none |
| Barcodes | nullable `barcode` column on `item`, no scanner UI | one column |
| Per-customer pricing / discounts | flat per-line price edit only | none |
| Receipt printing, WhatsApp send | design transaction render so a "share" hook can attach later | none |
| Double-entry GL / accountant export | CSV export covers v1 | none |
| Offline-first sync | `client_op_id` column on `txn`, `payment`, and `inventory_adjustment` for idempotency | one column |

### Explicitly out of v1 (the path to ERP — say no)
Stock-count workflow, first-class returns, multi-location/transfers/warehouses, variants/kits/BOM, promotions/discount engine, tax engine (single optional rate at most), approval workflows, procurement (POs/GRNs), hardware (scanners/printers/drawers), loyalty / store credit.

### Two rules that keep this honest
1. **Every non-money stock change is an `inventory_adjustment` with a reason.** Nothing else writes to `stock_movement` directly. This single rule postpones half of ERP for years without losing accuracy.
2. **Cached columns (`current_stock`, `avg_cost`, `party.receivable/payable`) are projections, never inputs.** A nightly reconciliation view compares cache vs ledger. When caches need their own tables later (e.g., multi-location), only the projection logic changes.

## 8. Open questions to resolve before Phase 1

> See **`docs/decisions.md`** for recommended answers (Track B research, in progress).

1. **Currency policy for pilot:** **DECIDED — USD as default per shop** (one currency per shop; no mixed-currency totals). SLSH supported for Hargeisa shops. SOS not in v1 unless a pilot shop specifically requests it.
2. **Auth method:** **DECIDED — phone OTP for shop users on mobile and web.** Prefer WhatsApp OTP delivery through existing Meta/Facebook WhatsApp API access; use SMS aggregator fallback only after real delivery testing. Owners self-register the first shop; workers are owner/admin-invited.
3. **Supabase region:** pick closest region with acceptable latency from Somalia; validate with a real-device test before pilot.
4. **Pricing model** for SaaS (free pilot? per-shop monthly?) — doesn't affect schema much but affects org/plan model.
5. **Receipt printer** at point of sale: required for pilot or skip?
6. **SMS / WhatsApp** sharing of receipts to customers — pilot feature or later?
7. **Cost capture on bono:** confirmed both *unit cost* and *line total* must be supported (UI toggle). Are discounts/multiple costs common on one bono?
8. **Sales pricing:** fixed per item, or negotiable per sale? (Plan assumes editable per line, default from item.)
9. **Roles:** confirm minimum set (likely Owner + Cashier + Support); who can void/refund/edit prices.
10. **Costing policy:** weighted-average at receive posting; sale COGS snapshotted on the line; no backdated recomputation. Confirm acceptable.
11. **Data export & admin recovery:** **DECIDED** — pilot ships with CSV export and owner self-service void (≤7 days). **Support role is strictly setup-only**; cannot post voids, sales, or any transactional changes. Owner-only privilege for corrections.

## 8a. Design invariants (locked after critique)
- **Posted transactions are immutable.** Corrections are reversing transactions (`reverses_transaction_id`), never edits.
- **COGS is snapshotted** on each sale line at posting time (`cogs_unit_cost`, `cogs_total`); profit reports use the snapshot, never live `avg_cost`.
- **Product meaning is snapshotted** on each item transaction line (`item_name_snapshot`, `unit_code_snapshot`, `unit_conversion_to_base_snapshot`, optional `catalog_revision_id`) so catalog or shop-name changes never rewrite history.
- **Payments use many-to-many allocations** (`payment_allocation`) so one payment can settle several debts and partial/over-payments are first-class.
- **Tenant integrity is enforced by composite FKs on `shop_id`**, not by RLS alone.
- **No JWT shop claim trusted for authorization** — RLS checks `auth.uid()` + `shop_membership` / `organization_membership` directly. `current_shop_id` is a UX-only app-state value.
- **Denormalized balances** (`party.receivable/payable`, `item.current_stock`, `item.avg_cost`) are cached projections updated only by posting procedures; a nightly reconciliation job checks against ledger views.
- **Only `transaction_line` and `inventory_adjustment_line` may write to `stock_movement`.** Anti-ERP-creep guardrail.
- **`payment.direction` is an internal enum**; `stock_movement` uses typed source FKs (`transaction_line_id` or `inventory_adjustment_line_id`) so parent integrity is enforced without user-extensible reference data.
- **Setup gates daily flows:** `shop.setup_status` must be `ready` before Sale / Receive / Payment / Expense can be posted.

## 9. Deliverable from this session
- `docs/plan.md` (this file).
- `docs/architecture.md` — deeper architecture, ER overview, RLS approach, OCR pipeline, i18n strategy, platform layer.
- `docs/ux.md` — UX north-star, speed contract, screen designs, interaction rules, anti-patterns.
- `docs/ux-screens.md` — complete screen inventory, Level A daily-flow layouts, bottom-sheet patterns, screen states.
- `docs/templates-and-learning.md` — operating-template reference: setup defaults, fast-entry mappings, and shop-specific learning techniques.
- `docs/admin-portal.md` — admin/setup portal scope, roles, functionality, security boundary, and MVP.
- `docs/backend-schema.md` — Supabase/Postgres schema draft, migration order, RLS plan, RPC posting functions, Storage policy, reporting/reconciliation views, and learning/suggestion profiles.
- `supabase/migrations/0001_extensions.sql` through `0015_rls_storage.sql` — backend foundation plus setup, catalog/templates, shop items/units, suppliers/customers, aliases, documents/OCR, Storage bucket/object policies, transaction/payment/stock ledgers, reports, learning profiles, precomputed suggestions, RLS helpers, bootstrap RPCs, and posting RPCs.
- `app/dukan` — Flutter app now has Supabase bootstrap via `--dart-define`, phone OTP login, OTP verification, RLS-backed shop loading, shop picker, and first-shop owner onboarding placeholder.
- `supabase/seed.sql` — development-only seed placeholder; required production lookup data lives in migrations.
- `scripts/test-backend-migrations.sh` — Docker-based backend migration/RLS test harness.
- `.github/copilot-instructions.md` — binding principles summary for AI/human contributors.
- `docs/decisions.md` (in progress, Track B) — recommended answers to the open questions above.

Next: wire the Flutter prototype against Supabase data for template-applied items and the core Sale/Receive/Payment/Expense flows, then replace the owner-onboarding placeholder with the full setup checklist.
