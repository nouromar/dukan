# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## North-star principle
**UX is the #1 success factor.** Target users are shopkeepers in small neighbourhood shops who are **not tech-savvy**, often using a mid-range Android one-handed while serving customers. Primary language is **Somali**, English secondary.

If a proposed change makes the Sale or Receive flow slower, more confusing, or adds a step, **reject it** — even if it is technically elegant or adds a feature. Speed and clarity outrank everything else.

## Decision-free daily use
Every decision is made **once, at setup** (by support staff or via a one-tap template). Daily flows (Sale, Receive, Payment, Expense) contain **zero configuration questions**. If a setting could plausibly be asked daily, move it to Setup; if at Setup, prefer a default sourced from the shop's template.

Templates live in the platform layer (`docs/architecture.md` § 8aa) and are applied idempotently. V1 support is a Help icon linked to WhatsApp/email; in-app support codes are disabled for v1. Support staff can configure setup data; they **cannot** post sales/receives/payments/voids/stock movements. Enforce this boundary in the backend, not only in UI.

## Canonical docs (read before contributing)
- `docs/product-vision.md` — the three-component architecture (mobile + shop admin + system admin), north-star principles, invariants. Read first.
- `docs/ux.md` — speed contract, interaction rules, anti-patterns. **Binding.**
- `docs/ux-screens.md` — screen inventory, Level A daily-flow layouts, bottom-sheet patterns.
- `docs/plan.md` — scope, phases, decisions, open questions.
- `docs/architecture.md` — data model, RLS, OCR pipeline, design invariants.
- `docs/backend-schema.md` — Supabase/Postgres schema, RLS, RPC posting functions, Storage policy, migration order.
- `docs/templates-and-learning.md` — operating-template contents, fast-entry mappings, shop-specific learning rules.
- `docs/roles-and-permissions.md` — capability vocabulary, role catalog, scope tiers (platform/org/shop).
- `docs/staff-onboarding.md` — how owners add cashiers / other owners: `create_shop_invite` (phone OR email) + `claim_pending_invites_for_me()` auto-claim on sign-in. No SMS, no deep links, no accept step.
- `docs/mobile-app.md` — target-state design for the Flutter shop app. Companion: `docs/mobile-app-alignment.md` (punch list to reach target).
- `docs/shop-admin-portal.md` — target-state design for the React/Next.js back-office portal used by org/shop owners.
- `docs/system-admin-portal.md` — target-state design for the Dukan-internal mission-control portal. Supersedes `docs/admin-portal.md` (kept for historical reference until alignment doc lands).
- `docs/local-development.md` — Supabase CLI local stack instructions and the local phone OTP fixture.
- `docs/offline-first-architecture.md` — local-first thick-client design: sqflite mirror tables, sync engine (full + delta + realtime), conflict resolution, per-shop feature flag (`use_local_db = true | false`). Naming discipline: "useLocalDb" is the feature toggle; "offline" refers strictly to phone connectivity state.
- `docs/decisions.md` — decision log.

## Non-negotiable UX rules (summary — see `docs/ux.md`)
- One screen per task. No wizards for routine entry.
- Numeric input always uses the OS big numpad — never the alphanumeric keyboard.
- No typing of currency, units, dates, or category names. Ever.
- Defaults are sacred: today's date, shop currency, cash for sales, credit for receives, item's default price.
- Type-ahead with recents on top and aliases (Somali + English + abbreviations).
- Tap = the normal path. Long-press = power (quantity > 1, price overrides, notes).
- Optimistic save, no blocking dialogs. SAVE clears the UI immediately; the post runs in the background with `client_op_id` idempotency. Corrections to posted transactions go through Void in Sales history (owner-only, ≤7 days) — no 10-second in-app undo button.
- No icon without a text label.
- Both languages always one tap away; all strings translated, not just menus.
- Big tap targets (≥ 56dp); primary actions live in the bottom third of the screen.
- Errors are warnings whenever possible — not blocking modals.
- Reduce clutter aggressively; push search, filters, and advanced options into bottom sheets.

## Speed contract (mid-range Android, one hand, realistic data)
- Sale, 1 item, cash: **≤ 5 s, 3 taps from home**.
- Sale, 5 items, cash: **≤ 20 s**.
- Receive, 10-line bono manual: **≤ 90 s**.
- Any tap → visible response: **≤ 100 ms**.
- App cold start to home: **≤ 3 s**.

Any new feature must include a check that it doesn't regress these numbers for the flows it touches.

## Architectural invariants (summary — see `docs/architecture.md`)
- Multi-tenant: every business table has `shop_id`; RLS by membership; **composite FKs on `shop_id`** for cross-row integrity (not RLS alone).
- One generic `transaction` spine (Sale/Receive/Expense) driven by `transaction_type` reference rows. No separate per-type tables.
- Reference tables over PG enums for every user-visible category, with a single `ref_translation` table for i18n.
- Two spines, one system: `transaction` is money; `stock_movement` is inventory. **Only** `transaction_line` and `inventory_adjustment_line` may write to `stock_movement`.
- Posted transactions are immutable. Corrections via reversing entries (`reverses_transaction_id`), never edits.
- COGS is snapshotted on each sale line at posting time. Profit reports use the snapshot, never live `avg_cost`.
- Payments use a `payment_allocation` M2M so one payment can settle multiple debts.
- Denormalized fields (`shop_item.current_stock`, `shop_item.avg_cost`, `shop_item_unit.last_cost`, `shop_item_unit.sale_price`, `supplier_item_unit_cost.last_unit_cost`, `party.receivable`, `party.payable`) are cached projections, updated only by posting procedures, with a nightly reconciliation view. **Convention enforced by code review** — service role bypasses RLS, so admin portal and future tooling must go through the sanctioned RPCs (see `docs/data-model-v2.md` §7).
- Item stock is tracked in the item's base unit; split packages use `item_unit` conversions.
- Money and quantities use `numeric` — never floats.

## Scope discipline (v1 is a shop app, not an ERP)
**Build now:** Sale, Receive (with bono image), Expense, Payment, customer/supplier balances, simple reports, English + Somali, single location, single currency per shop. Plus an optional item-onboarding step at setup (add items, set prices, browse catalog — all skippable; doesn't block "start selling"). See `docs/data-model-v2.md` §3 and §11.10.

**Out of v1:** stock-count workflow, first-class returns, multi-location/transfers, product variants/kits/BOM, promotions/discount engine, tax engine, approval workflows, procurement (POs/GRNs), hardware integrations, loyalty/store credit, barcode UI.

**Inert v2 hooks (do not remove):** `location_id` on `stock_movement`, `client_op_id` on `transaction` and `payment`. (Barcodes are now first-class via `item_barcode` / `shop_item_barcode` per data-model-v2.)

## Language & copy
- Somali is first-class, not a translation afterthought. Native Somali shopkeeper review before release.
- Plain words only — no accounting jargon ("receivable", "ledger", "post"). Use "money customer owes", "saved".
- Button labels are verbs (**SAVE**, **CONFIRM**, **ADD LINE**), not nouns.
- Error and warning copy is action-oriented ("Take a photo of the bono", not "Document required").

## Tech stack (decided)
- **Flutter** shop app (Android/iOS first; Flutter Web optional later).
- **React / Next.js** admin web portal (org/multi-shop setup + support administration). *Not yet present in this repo.*
- **Supabase** (Postgres + Auth + Storage + Edge Functions + Realtime).
- **Google Cloud Vision OCR**, called only from Edge Functions (API key never on device).
- **Offline-first** by default (per-shop feature flag, see `docs/offline-first-architecture.md`). The `use_local_db` flag defaults to `true` (local sqflite mirror + sync engine + write queue); set `false` per shop for thin-client behavior (every read/write goes to the server, no queue, no local mirror). "Offline" in copy refers to phone connectivity only — a separate axis from the toggle.
- Pilot currency: USD by default (one currency per shop; SLSH supported for Hargeisa).

## Repository layout
- `app/dukan/` — Flutter shop app. Daily flows (Sale/Receive/Payment/Expense) are wired to Supabase via `ShopApi` posting RPCs and a durable offline write queue (`lib/queue/`).
- `supabase/migrations/` — numbered SQL migrations (`0001_…` through `0015_…`). **Order is load-bearing.** New migrations append; never edit applied ones.
- `supabase/config.toml` — Supabase CLI local stack config. Includes a fixed local phone OTP (`+252612345678` → `123456`) and placeholder Twilio values that are **local-only** (production uses Meta/WhatsApp).
- `supabase/seed.sql` — local-only seed data loaded on `supabase db reset`.
- `scripts/test-backend-migrations.sh` — standalone Docker harness that applies all migrations to a clean Postgres and exercises RPCs / RLS for both allowed and denied paths. Run this for any backend change.
- `templates/` — composable operating profiles per shop kind (currently `grocery/`). Each template is a `manifest.json` plus independent packs (catalog, settings, quick-actions, supplier-mappings, quantity-suggestions, aliases, ocr-mappings, expense-categories, dashboard). Idempotent on apply; bump the relevant pack `version` plus `manifest.json` when changing packs. The admin portal (not in this repo) is the only thing that should call the template-apply RPC.
- `docs/` — canonical product, UX, architecture, and schema documentation.
- `.github/copilot-instructions.md` — kept in sync with this file.

## Commands

### Supabase local stack (run from repo root)
```bash
supabase start           # bring up Postgres, Auth, REST, Storage, Studio
supabase db reset        # re-apply all migrations + seed.sql
supabase status -o env   # print local URLs and anon/service keys
supabase stop            # stop containers (preserve data)
supabase stop --no-backup && supabase start && supabase db reset  # full clean reset
```
Local URLs: Studio `http://127.0.0.1:54323`, API `http://127.0.0.1:54321`, DB `postgresql://postgres:postgres@127.0.0.1:54322/postgres`.

### Backend migration / RLS / RPC tests
```bash
./scripts/test-backend-migrations.sh
```
Spins up a disposable Postgres in Docker, mocks `auth` and `storage` schemas, applies every migration in order, then runs allow/deny assertions for `create_organization`, `create_shop`, membership/RLS access, and posting RPCs. Use this script (not just `supabase db reset`) when validating backend changes — it is the contract that proves both allowed and denied paths. Override the Postgres image with `POSTGRES_IMAGE=postgres:16-alpine ./scripts/test-backend-migrations.sh`.

### Flutter (run from `app/dukan/`)
```bash
flutter pub get
flutter analyze
flutter test                                   # all tests (pre-commit gate)
flutter test test/auth_controller_test.dart    # single test file
flutter test --name "createFirstShop"          # single test by name
tool/test.sh                                   # FAST inner loop: unit tests only (skips widget tests)
tool/test.sh full                              # whole suite via the helper
tool/test.sh test/sync                         # targeted path(s)
# NOTE: never run two `flutter test` at once — they share build/ + .dart_tool/
# and corrupt each other (phantom "_pendingExceptionDetails" failures).
# tool/test.sh refuses to start if another run is active.
flutter run                                    # prototype mode (no Supabase)
flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon key from `supabase status -o env`>
```
Localizations are generated from `lib/l10n/app_en.arb` and `app_so.arb` via `flutter pub get` (see `l10n.yaml`); generated files live in `lib/l10n/generated/`.

### Template validation
```bash
cd templates
python3 -m json.tool grocery/manifest.json >/dev/null
for f in grocery/*.json; do python3 -m json.tool "$f" >/dev/null || exit 1; done
```

## Backend architecture notes
- **Migration order is the source of truth.** Each numbered file builds on the previous: `0001` extensions → `0002` reference data → `0003` tenancy → `0004` auth helpers → `0005` shop setup → `0006` catalog templates → `0007` items/parties → `0008` documents/OCR → `0009` transactions/stock/payments → `0010` posting RPCs → `0011` catalog activation → `0012` apply template → `0013` reports/reconciliation → `0014` learning profiles → `0015` RLS/storage.
- **`0015_rls_storage.sql` intentionally does not run `alter table storage.objects enable row level security`.** Supabase owns and manages that table in both local and hosted projects. This is not a local-only workaround. The standalone Docker test harness enables RLS on its mocked `storage.objects` only because it creates that table itself.
- **Posting RPCs are the only sanctioned write path** for `transaction`, `payment`, `stock_movement`, and the cached projections (`item.current_stock`, `item.avg_cost`, `party.receivable`, `party.payable`). Do not write to those tables directly from the app. Corrections go through reversing entries; never edit posted rows.
- **Onboarding** uses `create_organization(p_organization_name, p_shop_name)` (returns org + first shop) and `create_shop(organization_id, name)` for additional shops. Shop visibility is determined by `auth_can_access_shop()`, which checks `shop_membership` plus org-level access via `organization_membership`.
- **Local phone OTP fixture:** `supabase/config.toml` pins `+252612345678` → `123456`. The Twilio credentials in that file are placeholders so Supabase Auth enables phone login; production must use the Meta/WhatsApp OTP path.

## Flutter architecture notes
- **Posting flows go through the offline queue.** Sale/Receive/Payment/Expense screens call `ShopApi` directly on the network-happy path, and fall through to `OfflineQueueController.enqueue(PendingPost(...))` on transient failure (see `lib/queue/`). Structured server rejects (`PostgrestException`) snapshot/restore the in-memory controller state instead of queueing. The `QueueStatusPill` in screen app bars surfaces backlog + tap-to-drain. Idempotency is enforced server-side via `client_op_id`.
- `lib/auth/auth_controller.dart` — `ChangeNotifier` that owns session + shop list + selected shop. `normalizePhoneNumber` defaults bare/leading-zero numbers to Somalia `+252` and enforces E.164.
- `lib/config/app_config.dart` — reads `SUPABASE_URL` / `SUPABASE_ANON_KEY` from `--dart-define`. If either is missing, the app skips `Supabase.initialize()` entirely and runs in prototype mode (no Supabase calls).
- `lib/l10n/` — ARB-based i18n. Add new strings to both `app_en.arb` and `app_so.arb`; missing Somali strings are a release blocker.
- Tests live in `app/dukan/test/`. Backend RLS / RPC behavior is tested in `scripts/test-backend-migrations.sh`, not in Dart.

## Process expectations
- Test extensively. Cover edge cases, authorization failures, invalid inputs, idempotency, tenant isolation, and posting/reversal edge cases — not only happy paths.
- Aim for 100% coverage on backend, Flutter, and web changes. If full coverage is impractical, document the exact gap and why.
- For Flutter changes: `flutter analyze` and `flutter test` must pass.
- For backend changes: add migration/RPC/RLS assertions to `scripts/test-backend-migrations.sh` (or a sibling) that prove both allowed and denied paths.
- For any change to a Sale or Receive flow: prototype against mock data and validate against the speed contract **before** backend wiring.
- Pilot UX changes against 2–3 real shopkeepers in Somali. Watch them; time them. Iterate.
- Per-release speed audit: record a real Sale and Receive screen capture. Any hesitation > 2 s is a bug.
- Never add a "small" feature that costs an extra tap in a flow used 200 times a day — that is a major regression.
