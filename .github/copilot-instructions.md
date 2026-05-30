# Copilot instructions — Dukan shop management app

## North-star principle
**UX is the #1 success factor for this product.** The target users are shopkeepers in small neighbourhood shops who are **not tech-savvy**, often using a mid-range Android one-handed while serving customers. Primary language is **Somali**, with English as a secondary option.

If a proposed change makes the Sale or Receive flow slower, more confusing, or adds a step, **reject it** — even if it's technically elegant or adds a feature. Speed and clarity outrank everything else.

## Corollary: decision-free daily use
Every decision is made **once, at setup** — by support staff or via a one-tap template. Daily flows (Sale, Receive, Payment, Expense) must contain **zero configuration questions**. If a setting could plausibly be asked daily, move it to Setup. If it could plausibly be asked at Setup, prefer a sensible default sourced from the shop's template. Fewer settings = fewer ways to get stuck.

Templates live in the platform layer (`docs/architecture.md` § 8aa) and are applied idempotently. V1 support uses a Help icon linked to WhatsApp/email; in-app support codes are disabled for v1.

Templates are modular operating profiles, not product lists. Split them into configuration packs such as catalog, settings, quick actions, supplier mappings, quantity suggestions, aliases, OCR mappings, expense categories, and dashboard defaults. Learned data can rank suggestions and pre-fill fields, but must never auto-post or silently change stock/money.

The admin portal is a setup/support console, not an ERP. Keep transaction truth in approved posting flows and enforce the support boundary in the backend, not only in UI.

Support staff can help with setup data and occasional follow-up support through WhatsApp/email in v1. If time-bounded in-app support sessions are added later, they remain setup-only and cannot post sales/receives/payments/voids/stock movements. No exceptions.

## Canonical docs (read before contributing)
- `docs/ux.md` — speed contract (target times per flow), universal interaction rules, Sale & Receive principles, language/copy rules, anti-patterns. **Treat this as binding.**
- `docs/ux-screens.md` — complete screen inventory, Level A daily-flow layouts, bottom-sheet patterns, and screen-state checklist.
- `docs/plan.md` — scope, phases, decisions, open questions.
- `docs/architecture.md` — data model, RLS, OCR pipeline, design invariants.
- `docs/backend-schema.md` — Supabase/Postgres schema, RLS, RPC posting functions, Storage policy, and migration order.
- `docs/templates-and-learning.md` — operating-template contents, fast-entry mappings, and shop-specific learning rules.
- `docs/admin-portal.md` — staff-facing React/Next.js setup/support console; configuration only, never transaction posting.

## Non-negotiable UX rules (summary — see `docs/ux.md` for the full list)
- One screen per task. No wizards for routine entry (Sale, Receive, Payment, Expense).
- Numeric input always uses the OS big numpad — never the alphanumeric keyboard.
- No typing of currency, units, dates, or category names. Ever.
- Defaults are sacred: today's date, shop currency, cash for sales, credit for receives, item's default price.
- Type-ahead everywhere with recents on top and aliases (Somali + English + abbreviations).
- Tap = the normal path. Long-press = power (quantity > 1, price overrides, notes).
- Optimistic save with a 10-second undo. Never block on the network.
- No icon without a text label.
- Both languages always one tap away; all strings translated, not just menus.
- Big tap targets (≥ 56dp); primary actions live in the bottom third of the screen.
- Errors are warnings whenever possible — not blocking modals.
- Daily flows ask zero configuration questions; settings live in Setup, defaults come from templates.
- Reduce clutter aggressively: keep daily screens focused on the next obvious action; move supplier/customer search, filters, secondary choices, and advanced options into bottom sheets or focused modals.

## Speed contract (must hit on a mid-range Android, one hand, realistic data)
- Sale, 1 item, cash: **≤ 5 seconds, 3 taps from home**.
- Sale, 5 items, cash: **≤ 20 seconds**.
- Receive, 10-line bono manual: **≤ 90 seconds**.
- Any tap → visible response: **≤ 100 ms**.
- App cold start to home: **≤ 3 seconds**.

Any new feature must include a check that it doesn't regress these numbers for the flows it touches.

## Architectural invariants (summary — see `docs/architecture.md`)
- Multi-tenant: every business table has `shop_id`; RLS by membership; **composite FKs on `shop_id`** for cross-row integrity (not RLS alone).
- One generic `transaction` spine (Sale/Receive/Expense) driven by `transaction_type` reference rows. No separate per-type tables.
- Reference tables over PG enums for every user-visible category, with a single `ref_translation` table for i18n.
- Two spines, one system: `transaction` is the money spine; `stock_movement` is the inventory spine. **Only** `transaction_line` and `inventory_adjustment_line` may write to `stock_movement`.
- Posted transactions are immutable. Corrections via reversing entries (`reverses_transaction_id`), never edits.
- COGS is snapshotted on each sale line at posting time. Profit reports use the snapshot, never live `avg_cost`.
- Payments use a `payment_allocation` M2M so one payment can settle multiple debts.
- Denormalized fields (`item.current_stock`, `item.avg_cost`, `party.receivable`, `party.payable`) are cached projections, updated only by posting procedures, with a nightly reconciliation view.
- Item stock is tracked in the item's base unit. Split packages use `item_unit` conversions (e.g., receive bags, sell pieces) so daily Sale/Receive stays simple.
- Money and quantities use `numeric` — never floats.

## Scope discipline (v1 is a shop app, not an ERP)
Build now: Sale, Receive (with bono image), Expense, Payment, customer/supplier balances, simple reports, English + Somali, single location, single currency per shop.

Out of v1 (resist scope creep): stock-count workflow, first-class returns, multi-location/transfers, product variants/kits/BOM, promotions/discount engine, tax engine, approval workflows, procurement (POs/GRNs), hardware integrations, loyalty/store credit, barcode UI.

Inert hooks already in the schema for v2 (do not remove): `location_id` on `stock_movement`, `barcode` on `item`, `client_op_id` on `transaction` and `payment`.

## Language & copy
- Somali is a first-class language, not a translation afterthought. All copy reviewed by a native Somali shopkeeper before release.
- Plain words only — no accounting jargon ("receivable", "ledger", "post"). Use "money customer owes", "saved", etc., in both languages.
- Button labels are verbs (**SAVE**, **CONFIRM**, **ADD LINE**), not nouns.
- Error and warning copy is action-oriented ("Take a photo of the bono", not "Document required").

## Tech stack (decided)
- Flutter shop app (Android/iOS first; Flutter Web optional later).
- React / Next.js admin web portal for organization, multi-shop, setup, and support administration.
- Supabase (Postgres + Auth + Storage + Edge Functions + Realtime).
- Google Cloud Vision OCR, called only from Edge Functions (API key never on device).
- Light offline: cache + write queue (`client_op_id` for idempotency). Full offline-first is deferred.
- **Pilot currency:** USD by default (one currency per shop; SLSH supported for Hargeisa).

## Process expectations
- Test extensively. Do not cover only happy paths; include edge cases, authorization failures, invalid inputs, idempotency, tenant isolation, and posting/reversal edge cases.
- Aim for 100% code coverage for every backend, Flutter, and web change. If full coverage is not practical, document the exact gap and why.
- For Flutter changes, run `flutter analyze` and `flutter test` before considering the change complete.
- For backend changes, add migration/RPC/RLS tests that prove both allowed and denied paths.
- For web admin changes, add tests for the affected forms, permissions, and error states.
- For any change to a Sale or Receive flow: produce a Flutter prototype against mock data and validate against the speed contract before backend wiring.
- Use `docs/ux-screens.md` as the required screen map for prototype coverage; Level A screens need full flow, bottom sheets, empty/error states, and timing.
- Pilot UX changes against 2–3 real shopkeepers in Somali. Watch them use it; time them. Iterate.
- Per-release speed audit: record a real Sale and Receive screen capture. Any hesitation > 2 seconds is a bug.
- Never add a "small" feature that costs an extra tap in a flow used 200 times a day — that's a major regression.
