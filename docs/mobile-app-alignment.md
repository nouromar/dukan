# Mobile App — Alignment Plan

> **Purpose.** Maps the current mobile codebase to the target described in `docs/mobile-app.md`. A working punch list, not a reference doc. Once each item is resolved, this document gets archived; the design doc remains as the source of truth.
>
> **How to use this.** Each item below is one PR-sized unit of work. Categories tell you the shape of the work; priority tells you the urgency. Cite the relevant `mobile-app.md` section in PRs touching these items so reviewers see the contract being honoured.
>
> **Categories:**
> - **KEEP** — already aligns with target; documented to confirm we don't accidentally regress.
> - **REFACTOR** — capability exists but structure/naming/contract drifts from target.
> - **ADD** — missing from the codebase; need to build.
> - **REMOVE** — leftover artifact that contradicts the target.
>
> **Priority:**
> - **P0** — blocks pilot. Pilot shopkeepers will hit this in the first day.
> - **P1** — needed before pilot exits beta. Real shops will hit this within a week.
> - **P2** — quality-of-life or long-term hygiene. Schedule into v1.x.
> - **P3** — design-for, not build-for. v2 territory; keep in mind for future work.

---

## 1. Snapshot: what's in good shape

These items map cleanly to the target. Listed here so future contributors can confirm them at a glance and so accidental regressions are visible in code review.

### Daily flows (`mobile-app.md` § 6)
- ✅ **Sale flow** — search-driven cart, optimistic SAVE with `client_op_id`, receipt sheet, void via Sales history. *(`lib/sale/*`)*
- ✅ **Receive flow** — supplier picker → lines → optional bono photo → SAVE. Resume in-flight bono on re-entry. *(`lib/receive/*`)*
- ✅ **Payment flow** — direction toggle, party picker scoped to direction, default cash, optimistic SAVE. *(`lib/payment/*`)*
- ✅ **Expense flow** — category picker, amount, optional notes, optimistic SAVE. *(`lib/expense/*`)*

### Reference flows (`mobile-app.md` § 7)
- ✅ **History × 4** — Sales, Receives, Expenses, Payments. All four use the shared filter pattern with funnel + active-chips + scope subtitle. *(`lib/sale/sale_history_screen.dart`, `lib/receive/receive_history_screen.dart`, `lib/expense/*`, `lib/payment/*`)*
- ✅ **People** — Customers and Suppliers screens share `lib/parties/people_screen.dart` body; headline tile + balance-first sort. FAB adds a party with optional opening balance.
- ✅ **Products list** — headline tile (`N products · X low · Y no price`), pinned search, funnel (category · low-stock · no-price), sort dropdown (name · stock low first), packed row layout.
- ✅ **Product detail (merged)** — ITEM Settings tiles, stock readout, packaging tiles with inline barcode chips + price + defaults + delete, alias chip strip, `+ Add packaging`.
- ✅ **Low stock + Top movers** — both screens shipped; Top movers has 7 / 30 / 90 day period picker and dead-stock segment.

### Information architecture (`mobile-app.md` § 5)
- ✅ **Home** — Today card + 4-tile grid + sign-out icon.
- ✅ **Drawer** — compact header, 4 grouped sections (HISTORY / PEOPLE / PRODUCTS / SETUP) in the correct order. No dividers; section labels alone separate.

### Backend (`mobile-app.md` § 4 + `docs/backend-schema.md`)
- ✅ Migrations 0001–0046 applied; harness §A–§DD assertions green.
- ✅ Posting RPCs: `post_sale`, `post_receive`, `post_payment`, `post_expense`, `post_inventory_adjustment`, `post_opening_party_balance`, all sanctioned write paths.
- ✅ Read RPCs: `list_sales`, `list_receives`, `list_expenses`, `list_payments`, `list_parties`, `list_shop_items`, `list_product_velocity`, `get_shop_item`, `get_today_summary`, `list_receivables`, `list_payables`, `list_low_stock`, `search_items`, `list_categories`, `list_expense_categories`.
- ✅ Mutation RPCs: `set_shop_item_unit_sale_price`, `set_shop_item_category`, `set_shop_item_reorder_threshold`, `set_shop_item_unit_default_flags`, `deactivate_shop_item_unit`, `add_shop_item_alias`, `remove_shop_item_alias`, `add_shop_item_barcode`, `remove_shop_item_barcode`, `set_primary_shop_item_barcode`, `update_party`, `create_party`, `void_sale`, `void_receive`.

### Engineering hygiene
- ✅ Analyzer clean (`No issues found!`).
- ✅ 209 Flutter widget tests passing.
- ✅ Arabic / Persian digit normalisation on OTP + phone fields (`lib/shared/digit_input.dart`).
- ✅ All `Localizations.localeOf` reads moved to `didChangeDependencies` (no more `initState` traps).

---

## 2. REFACTOR — already exists, needs the target's shape

### 2.1 [P1] Capability gating — refactor from hardcoded role checks to capability vocabulary
**Target:** `mobile-app.md` § 10. **Current:** UI gates by hardcoded role/predicate checks; backend uses `auth_can_post_shop`, `auth_can_access_shop`, `auth_has_shop_role(_, 'owner')`. **Gap:** the capability vocabulary from `docs/roles-and-permissions.md` is not the language the codebase uses; UI does not consistently hide actions based on the caller's capability set.

**Work:**
- Define a `Capabilities` model on the client populated at session start from a new `auth_user_capabilities(shop_id)` RPC.
- Refactor screens to consult `caps.canPostSale` / `caps.canVoidSale` / etc., not implicit role checks.
- Hide drawer entries, hide tiles, hide per-row actions based on capability.
- Add a "read-only mode" render path for Product detail (cashier sees prices + stock but cannot tap to edit).
- Backend: keep the helper functions (`auth_can_post_shop`, etc.) but reimplement them on top of a new `auth_user_has_capability(p_capability, p_scope_kind, p_scope_id)` so the wire format aligns with the long-term roles model.

**Note:** v1 ships hardcoded `cashier` / `owner` roles. Refactoring the *vocabulary* now sets us up for the v1.x rollout of data-driven roles without UI rework.

---

### 2.2 [P2] Receipt SHARE button — stub → real adapter dispatch
**Target:** `mobile-app.md` § 6.1 (SHARE wired with Print + WhatsApp). **Current:** SHARE button surfaces a toast.

**Work:**
- Define an interface `ReceiptShareAdapter` with `shareToPrinter(SaleReceipt)` and `shareToWhatsApp(SaleReceipt)`.
- Implement WhatsApp via `share_plus`.
- Implement printer via a Bluetooth thermal printer plugin (decision in `docs/decisions.md` first — which printer SDK).
- Decision pending in `docs/plan.md` § 8.5: receipt printer in pilot or skip? Until decided, ship the WhatsApp half and keep the printer wired-but-disabled.

---

### 2.3 [P2] Drawer header — confirm against compact target
**Target:** `mobile-app.md` § 5.2 (slim ~72dp coloured strip). **Current:** matches target after the compact refactor.

**Work:** None. Listed here so a future "let's make the header bigger" PR gets pushed back to this section.

---

### 2.4 [P2] Stock adjust sheet — mode labels + helper text against target wording
**Target:** `mobile-app.md` § 8 (Opening / Add / Subtract / Set exact). **Current:** matches.

**Work:** None — but verify Somali translations against native-speaker review (see §3 ADD: Somali copy audit).

---

### 2.5 [P2] Settings — scope it to "single-owner, on-phone" only
**Target:** `mobile-app.md` § 9. **Current:** Settings screen exists with shop defaults; no leakage to web-belong items because none exist yet (no branding edit, no integrations, etc.). Borderline-clean.

**Work:**
- Remove the Products navigation entry from Settings (already done — confirmed in alignment, listed here for the record).
- When the shop admin portal ships, ensure no shop-branding / receipt-template / tax-config UI gets accidentally added to mobile Settings under feature pressure.

---

## 3. ADD — missing capabilities the target requires

### 3.1 [P0] Real-time sync from web edits
**Target:** `mobile-app.md` § 11. **Why P0:** without this, owner price edits on web don't propagate to mobile, and the three-component system feels like three separate apps.

**Work:**
- Add Supabase realtime subscription scaffolding (`SupabaseChannel` wrapper in `lib/shared/realtime.dart`).
- Subscribe long-running detail screens: `ShopItemDetailScreen` (subscribe to `shop_item` + `shop_item_unit` for the open id), `PartyDetailScreen` (subscribe to `party`).
- Subscribe list screens to invalidate-and-refetch when category/threshold/price changes land.
- Subtle visible feedback (refresh shimmer at top of screen on event).
- Reconnect logic + back-off on subscription failure.

---

### 3.2 [P0] Barcode scanning in Sale + Receive
**Target:** `mobile-app.md` § 6.1 + § 7.3 ("scanning a code resolves to the right product"). **Current:** `search_items` RPC matches barcodes; the search bar accepts a typed barcode. No camera or BT-scanner input.

**Work:**
- Camera scan: add `mobile_scanner` package; camera-icon next to the search field in Sale and Receive opens a scanner sheet.
- Scanned code goes through `search_items` → if a `shop_item_unit` matches, drop that packaging into the cart at the right price.
- Bluetooth HID scanner: most cheap BT scanners type as keyboard. The search-bar `TextField` is already focused during search; HID scans work today. Add an "always-on scan listener" mode so the cashier doesn't need to tap the field first.

---

### 3.3 [P0] CSV export from history pages
**Target:** `mobile-app.md` § 19 explicitly puts CSV on web — but a per-history "Export current view" button is on the v1 pilot punch list per `docs/plan.md` Phase 9. **Resolution:** CSV export *lives on web* per the architectural rule. **Don't add to mobile.** Listed here so the temptation to add it gets squashed.

**Work:** None. Cite this row when CSV-on-mobile is proposed.

---

### 3.4 [P0] Crash reporting
**Target:** not a user-visible feature but a pilot-shipping invariant. **Current:** errors go through `FlutterError.reportError`; nothing aggregates them off-device.

**Work:**
- Wire Sentry SDK (or equivalent) in `lib/main.dart` behind a `--dart-define` DSN.
- Route `FlutterError.onError` and `PlatformDispatcher.instance.onError` to Sentry.
- Tag events with shop_id + user_id + version.
- Test that a forced exception in debug shows up in the Sentry project.

---

### 3.5 [P0] Recorded speed audit
**Target:** `mobile-app.md` § 4. **Current:** speed contract is documented; never measured on a real device with realistic data.

**Work:**
- Provision a representative shop in the local stack: ~150 products, ~30 customers, ~30 suppliers, ~60 days of sales.
- Record screen capture of: Sale (1 item, cash), Sale (5 items, cash), Receive (10-line manual), cold start.
- Annotate each capture with timestamps against the contract.
- File the artifacts in `docs/pilot-readiness/` (new directory).
- Iterate any flow that misses the budget by > 10%.

---

### 3.6 [P0] Somali copy review
**Target:** `mobile-app.md` § 14 ("missing Somali strings are release blockers"). **Current:** Somali strings are present everywhere but never reviewed by a native speaker.

**Work:**
- Find a Somali-first reviewer (ideally a Hargeisa shopkeeper, not a translator).
- Walk every screen in `lib/l10n/app_so.arb`.
- Fix in place; record the review session in `docs/decisions.md`.

---

### 3.7 [P1] Platform impersonation banner
**Target:** `mobile-app.md` § 13. **Current:** impersonation does not yet exist on the system admin portal side; mobile has no banner. **Why P1:** ships with the system admin portal's impersonation feature, which is a v1.x deliverable.

**Work:**
- Backend: a session flag `is_impersonated_by` populated when a platform-staff JWT is acting on behalf of a tenant.
- Mobile: persistent banner across the top of every screen when the flag is set. Bright colour. Includes the staff member's name and a free-text reason from the impersonation request.
- Banner is dismissable per session; re-arms next impersonation event.

---

### 3.8 [P1] Audit-log inline references
**Target:** `mobile-app.md` § 12. **Current:** audit log is being written (per `post_sale`, `void_sale`, etc., per the harness assertions) but there's no inline UI.

**Work:**
- On a voided sale row in Sales history, show "voided by Asha 10 min ago" as the subtitle.
- On a price tile in Product detail, show "last edited by Cabdi yesterday" as a hover/tap tooltip.
- Do **not** build a full audit log search/filter UI — that's the shop admin portal's job. Confirm by reading § 12 + § 18.

---

### 3.9 [P1] Improved offline write-queue
**Target:** `mobile-app.md` § 15 ("write queue: posts with `client_op_id` retry on transient failure"). **Current:** `client_op_id` is on the schema; retry policy on the client is minimal.

**Work:**
- Add a durable in-memory + restart-survivable write queue (SQLite or Hive).
- On network failure during SAVE, the post lands in the queue with status `pending`.
- A background ticker retries pending posts when connectivity returns.
- UI shows a small "syncing N actions" chip in the app bar while the queue has items.
- Idempotency is server-enforced via `client_op_id`; duplicate sends are no-ops.

---

### 3.10 [P1] Capability-aware read-only Product detail
**Target:** `mobile-app.md` § 7.3 + § 10 ("Cashier viewing Product detail sees prices and stock; the chips are visible but their tap is a no-op with a 'Contact owner' toast"). **Current:** Product detail edits commit regardless of role; cashier gets a backend rejection toast on the first edit attempt.

**Work:** depends on the capability refactor (§ 2.1). Once `caps.canEditPrice` etc. are available, the detail screen renders with disabled tap targets + a "Contact owner" toast on tap rather than allowing the action then failing.

---

### 3.11 [P1] Per-invoice payment allocation
**Target:** `mobile-app.md` § 6.3 ("Allocation: implicit in v1; explicit per-invoice deferred to v1.x"). **Current:** implicit oldest-first.

**Work:**
- Add a `payment_allocation` editor: party detail surfaces unpaid sales/receives as line items; the Payment screen optionally drills into "Allocate this payment" with checkboxes.
- Default behaviour stays oldest-first (don't slow down the common case).
- Backend already supports `payment_allocation`.

---

### 3.12 [P1] Push notifications
**Target:** `mobile-app.md` § 17. **Current:** none.

**Work:**
- FCM (Firebase Cloud Messaging) on Android; APNs on iOS.
- Trigger types for v1.x: low-stock breach, opening-balance reminder (after onboarding), support inbound message.
- Quiet hours setting in mobile Settings.
- Suppression when the app is foreground on the relevant screen.

---

### 3.13 [P2] Per-cashier shift workflow
**Target:** `mobile-app.md` § 6.1 ("same-shift void" for the Manager role). **Current:** void window is 7 days for owner; no concept of shifts.

**Work:**
- Define a `shift` model server-side: cashier opens a shift with optional opening cash float, closes with a reported total.
- Mobile: shift-open prompt when a cashier signs in to a new day; shift-close prompt before sign-out.
- "Same-shift void" capability becomes meaningful.
- Z-report for the closed shift is exportable from the shop admin portal (not mobile, by § 18).

---

### 3.14 [P3] Discount engine
**Target:** `mobile-app.md` § 18 lists it as "future". **Current:** none.

**Work:** v2. Don't build into v1.

---

### 3.15 [P3] Split tender
**Target:** future. **Work:** v2.

---

### 3.16 [P3] Tax engine
**Target:** future. **Work:** v2, pending decision per `docs/plan.md` § 8.

---

## 4. REMOVE — leftover artifacts to delete

### 4.1 [P2] `lib/prototype/inline_party_search.dart`
**Why:** still references `lib/mock/mock_data.dart`; the only file in the app that does. The party picker has been on Supabase since the party-detail / party-list work.

**Work:**
- Delete the file.
- Delete any unused symbols in `lib/mock/mock_data.dart`.
- Confirm `flutter analyze` stays clean.

---

### 4.2 [P2] Dead ARB keys
**Why:** strings like `drawerOpenTooltip`, `drawerReceivables`, `drawerPayables`, `drawerParties`, `drawerReportsHeader` no longer correspond to any UI surface after the drawer regroup + Customers/Suppliers merge.

**Work:**
- Audit `lib/l10n/app_en.arb` + `lib/l10n/app_so.arb` for keys not referenced in `lib/`.
- Delete unreferenced keys.
- Regenerate localizations.

---

### 4.3 [P3] `low_stock_warning_enabled` per-shop toggle in Settings
**Why (maybe):** the toggle exists on `shop`. The Today card always renders low-stock count; the low-stock toast was added before the dashboard tile existed. The toggle may be vestigial.

**Work:**
- Decide: do we still want the toggle, or is the dashboard tile enough?
- If vestigial: delete the toggle + the per-toast logic + the column (migration).
- If kept: document its purpose in `docs/decisions.md`.

---

## 5. Priority view — what blocks pilot

The shopkeeper-facing readiness gate. Everything **P0** ships before the first pilot shop signs in:

| Item | § |
|---|---|
| Real-time sync from web edits | 3.1 |
| Barcode scanning in Sale + Receive | 3.2 |
| Crash reporting | 3.4 |
| Recorded speed audit | 3.5 |
| Somali copy review | 3.6 |

**P1** ships before pilot exits beta (estimated 1-2 months of pilot operation):

| Item | § |
|---|---|
| Platform impersonation banner | 3.7 |
| Audit-log inline references | 3.8 |
| Improved offline write-queue | 3.9 |
| Capability-aware read-only Product detail | 3.10 |
| Per-invoice payment allocation | 3.11 |
| Push notifications | 3.12 |
| Capability gating refactor | 2.1 |
| Receipt SHARE adapter | 2.2 |

**P2** ships into v1.x. **P3** is v2.

---

## 6. Cross-document dependencies

Items that block on work outside the mobile codebase:

| Item | Depends on |
|---|---|
| § 2.1 Capability refactor | `docs/roles-and-permissions.md` § 9 backend functions land first. |
| § 2.2 Receipt SHARE | `docs/plan.md` § 8.5 printer decision. |
| § 3.1 Real-time sync | None — can ship today. |
| § 3.4 Crash reporting | Sentry project provisioned by platform team. |
| § 3.7 Impersonation banner | System admin portal impersonation feature ships first. |
| § 3.11 Per-invoice allocation | Shop admin portal aging report rendering the same allocations correctly. |
| § 3.12 Push notifications | Backend notification service decision (Edge Function vs. dedicated service). |
| § 3.13 Shift workflow | Backend `shift` model. |

---

## 7. Sequencing guidance

A reasonable rolling plan, week by week, starting from "this document is committed":

**Week 1:** § 3.4 crash reporting + § 3.5 speed audit + § 3.6 Somali review kick-off. Foundational; un-tangles other work.

**Week 2:** § 3.1 real-time sync + § 3.2 barcode camera scan. Both are user-visible step changes.

**Week 3:** § 2.1 capability refactor (backend half) + § 3.10 read-only Product detail (client half).

**Week 4:** § 3.9 offline write queue + § 4.1 + § 4.2 cleanup.

**Week 5–6:** § 3.7 impersonation banner (after system admin portal lands the feature), § 3.8 audit log inline, § 3.11 per-invoice allocation, § 3.12 notifications.

**Week 7:** § 2.2 SHARE adapter (assumes printer decision in `docs/plan.md` § 8.5 resolved), § 3.13 shift workflow design (build slips into v1.x).

This is not a commitment — it's a sketch to give a feel for ordering. Real sequencing depends on team size + parallelism + the printer decision.

---

## 8. Closing this document

This is a mortal document. When every P0 + P1 item is shipped, archive it to `docs/archive/` and link to it from a one-line entry in `docs/decisions.md`. The design doc (`docs/mobile-app.md`) is the surviving source of truth.

---

## 9. Change log

| Date | Change | Author |
|---|---|---|
| 2026-06-11 | Initial draft against `mobile-app.md` v1. | — |
