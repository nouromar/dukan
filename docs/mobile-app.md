# Mobile App — Design

> **Purpose.** Canonical design document for the Dukan mobile app. Describes the **target** mobile experience as it should be — independent of what the current codebase happens to look like. The companion document `docs/mobile-app-alignment.md` is the punch list that maps the current implementation to this target.
>
> **Audience.** Engineers building mobile features, designers shaping screens, PMs scoping releases, support staff explaining behaviour to shopkeepers.
>
> **Sister documents.** `docs/product-vision.md` (the three-component architecture this app is part of) · `docs/roles-and-permissions.md` (the capability model this app honours) · `docs/ux.md` (the speed contract and interaction rules) · `docs/ux-screens.md` (pixel-level screen designs).

---

## 1. What the mobile app is for

The Dukan mobile app is the **transactional core** of the Dukan system. It is the till. It is the back-of-shop. It is the thing a Somali shopkeeper holds in one hand while a customer waits at the counter, and the only system the shop owner needs to run their business day to day.

It is **deliberately not** a back-office tool. Wide tables, bulk operations, multi-shop comparison, printing, CSV — all live on `admin.dukan.so`. The cashier is at the counter; the owner is at the desk. Mixing those audiences destroys both UXs.

This boundary is not a transitional limitation. It is a load-bearing design choice.

## 2. The four north-star principles, applied

These mirror `docs/product-vision.md` § 3, restated as mobile-specific commitments.

### 2.1 UX is the #1 success factor
A shopkeeper who is not tech-savvy will use this app 200+ times a day. If a feature adds a tap, a configuration question, or a moment of doubt to a daily flow, **the feature loses**. Engineering elegance, technical purity, and architectural cleanliness all defer to user-felt speed and clarity.

### 2.2 Decision-free daily use
Daily flows contain **zero configuration questions**. Every decision is made once, at setup — by template, by support, or by the owner explicitly. If a setting could plausibly be asked daily, it belongs in Setup.

### 2.3 Mobile is the transactional core
The mobile app must work fully without either web portal ever existing. Web portals add capabilities that the phone is bad at; they never become *required* for daily operations.

### 2.4 Backend is the single source of truth
No business logic in Dart. Every posting, every void, every adjustment goes through a sanctioned RPC. The mobile app is a client of the same RPCs the web portals use. This is what keeps three components feeling like one product.

## 3. The user

| | |
|---|---|
| **Who** | Shopkeeper or cashier in a small neighbourhood shop |
| **Device** | Mid-range Android (often), some iOS. Pre-installed Google Play / App Store |
| **Posture** | Often one-handed, often while looking at a customer |
| **Light** | Usually fine; sometimes outdoor glare, sometimes a dim corner |
| **Network** | Spotty 4G; sometimes none for minutes at a time |
| **Tech literacy** | Low to moderate; comfortable with WhatsApp and similar |
| **Language** | Somali first; English second; switches freely |
| **Hands** | May have just touched produce; screen interactions need to be tolerant of moisture and grime |
| **Distractions** | Constant; the app must survive being put down mid-flow and resumed minutes later |

This profile drives every interaction rule: big tap targets, generous spacing, defaults that match the typical action, no blocking modals during a flow, optimistic save with idempotent retry.

## 4. Speed contract

The targets from `docs/ux.md` are restated here because they govern every mobile design choice.

| Flow | Target |
|---|---|
| Sale, 1 item, cash | ≤ 5 s · 3 taps from Home |
| Sale, 5 items, cash | ≤ 20 s |
| Receive, 10-line bono (manual) | ≤ 90 s |
| Any tap → visible response | ≤ 100 ms |
| Cold start → Home | ≤ 3 s |
| Hot reload after locale switch | ≤ 1 s |

These are non-negotiable. Any feature whose implementation regresses these numbers for the flow it touches is, by definition, the wrong implementation.

## 5. Information architecture

The app has a fixed top-level shape that does not change with new features. New capabilities find a home **inside** an existing surface; you should rarely need an 11th item in any list.

### 5.1 Home
The landing screen. Three regions, top to bottom:

1. **App bar** — drawer hamburger · app title · sign-out icon.
2. **Today card** — at-a-glance summary: sales today, customers owe you, you owe suppliers, low-stock count. Every row tappable, drilling into the relevant screen pre-filtered.
3. **Four-tile grid** — the primary daily flows: **Sale · Receive · Payment · Expense**. Always in this order. Each tile ≥ 110dp tall. These four buttons account for the vast majority of taps over the app's lifetime.

The Home screen is the only screen many shopkeepers ever see for hours at a time. It must always be calm, fast, and predictable.

### 5.2 Drawer (left)
The drawer hosts everything that isn't a daily-flow tile. It is grouped into sections, in a stable order. Section headers are visual breaks, not interactive.

```
HISTORY      Sales · Receives · Expenses · Payments
PEOPLE       Customers · Suppliers
PRODUCTS     Products · Low stock · Top movers
SETUP        Settings
```

The header is a slim coloured strip (~72dp) with the app name and active shop name. The drawer items are dense (`visualDensity.compact`, dense ListTile) so all entries fit on a mid-range phone without scrolling. Tap an entry → drawer closes → destination pushes.

### 5.3 The boundary
Anything that does *not* belong on Home or in the drawer should challenge whether it belongs in the mobile app at all. The IA is the first defence against feature creep.

## 6. Daily flows

These four flows account for nearly all daily taps. Each is documented as a **state machine + speed budget**. Per-screen pixel design lives in `docs/ux-screens.md`; this document describes the contract.

### 6.1 Sale
- **Entry**: Home → tap Sale tile.
- **Default tender**: cash. (Debt is one tap away if the cashier picks a customer.)
- **Default party**: none (anonymous cash sale).
- **Adding items**: type-ahead search · recently-used at top · alias + barcode resolution · tap once for fast-add at the item's default packaging and price · long-press for the line editor (quantity > 1, price override, notes).
- **Item not in catalog**: inline "Add new item" sheet, never pop the user out of the flow.
- **No price set**: line editor surfaces a price prompt; the price is saved back to the packaging on commit so the same item ships priced next time.
- **Cart state**: persists across navigator pushes; survives backgrounding for a small window.
- **SAVE**: optimistic — UI clears immediately; post runs in the background with `client_op_id` idempotency. Failures surface as a non-blocking retry toast.
- **Receipt sheet**: pops over the cleared Sale screen on success. SHARE button is wired (Print / WhatsApp) with adapter dispatch.
- **Correction path**: voids via Sales history, owner-only, ≤ 7-day window. There is no in-flow undo button.

**Capability gating**: requires `can_post_sale` at shop scope. Without it, the Sale tile is hidden; an unauthorized direct navigation routes back to Home. The void path requires `can_void_sale` (cashier same-shift) or `can_void_sale_7d` (owner).

**Lives on web instead**: bulk historical analysis (sales by day/cashier/payment-method/category, P&L with COGS), CSV export, printable Z-reports, multi-shop sales comparison.

### 6.2 Receive
- **Entry**: Home → tap Receive tile → supplier picker (or resume an in-flight bono).
- **Supplier**: required. Inline create when missing; the new supplier is auto-selected and the flow continues.
- **Lines**: same search-driven UX as Sale, but defaults flip — the *default-receive* packaging shows first, costs are typed not prices.
- **Bono photo**: optional but encouraged. Camera or gallery; uploads to Storage; document row is created server-side. Attachment surfaces in the app bar with a tick state.
- **Payment**: defaults to credit (zero paid). Cash-on-delivery is one tap away.
- **SAVE**: optimistic with `client_op_id`. Same receipt-style confirmation pattern as Sale.
- **Correction path**: void in Bono history, owner-only, same-shift, refuses if subsequent stock activity occurred against any line — to protect downstream COGS math.

**Capability gating**: requires `can_post_receive`. The bono-photo attach requires `can_attach_document`. Void requires `can_void_receive`.

**Lives on web instead**: supplier scorecards, lead-time tracking, cost-variance reports, receive history with wide filters, printable supplier statements.

### 6.3 Payment
- **Entry**: Home → tap Payment tile, or via Party detail → PAY button (pre-fills party + direction).
- **Direction**: inbound (customer paid us) or outbound (we paid supplier). Toggle is a segmented control; party picker scope follows the direction.
- **Method**: defaults to cash.
- **Amount**: numeric numpad; OS big keyboard.
- **Allocation**: implicit in v1 (oldest debt first); explicit per-invoice allocation deferred to v1.x.
- **SAVE**: optimistic with `client_op_id`. Party balance reload on return.

**Capability gating**: requires `can_post_payment`. Refund payments minted by void_sale require `can_post_refund` and are visible on the Payment History as flagged rows.

**Lives on web instead**: bulk SMS / WhatsApp dunning, aging-bucket exports, payment scheduling, bank-feed reconciliation.

### 6.4 Expense
- **Entry**: Home → tap Expense tile.
- **Category**: required (Electricity, Rent, Salary, ...). Picker shows shop's expense_category set with recents at top.
- **Amount**: numeric numpad.
- **Optional**: notes, document attach (paper receipt photo).
- **SAVE**: optimistic with `client_op_id`.

**Capability gating**: requires `can_post_expense`.

**Lives on web instead**: bulk expense import (a month of utility bills from CSV), expense trend analytics, budget vs actual, category management.

## 7. Reference flows

These are the surfaces a shopkeeper reaches less often but every day at least once. Each is search-first, filter-aware, and ends with tap-into-detail.

### 7.1 History (Sales, Receives, Expenses, Payments)
Four parallel surfaces, identical interaction model. App bar with title + scope subtitle (active date range). Funnel icon opens a bottom sheet with date range, party / category filter, and "hide voided" toggle. Active filters render as dismissible chips above the list. Tap a row → detail screen with receipt-style read-out + void action (within window + within capability).

**Capability gating**: viewing history requires `can_view_history`. Voiding requires the appropriate `can_void_*` capability.

**Lives on web instead**: same data, wide tables, exportable CSV, cross-shop filters, scheduled emailed reports.

### 7.2 People (Customers, Suppliers)
Two parallel screens. Each is search-driven with a funnel for *has balance only* and a sort toggle. Headline tile at top shows the total owed (receivables or payables) and the count. Tap a row → party detail with sales/receives/payments timeline + PAY button + edit sheet (name, phone). FAB adds a new party with optional opening balance.

**Capability gating**: viewing the list requires `can_view_parties`. Editing requires `can_edit_party`. Adding requires `can_create_party`. Opening balance requires `can_post_opening_balance`.

**Lives on web instead**: bulk CSV import / export, dedupe + merge, marketing segments, automated outreach, credit-limit management, supplier scorecards.

### 7.3 Products
Products list with a pinned search bar (matches name, alias, **barcode** — scanning a code resolves to the right product), filter funnel (category · low-stock · no-price-yet), and a sort dropdown (name · stock low first). Headline tile at top: `N products · X low · Y no price`. Tap a row → product detail.

Product detail is **the one place** everything about a product is edited: name / category / threshold / base unit (read-only) as Settings tiles, big stock readout (tap to open the stock-adjust sheet), packaging tiles with inline barcode chip row + default-sale/receive toggles + tap-to-edit price, aliases as a chip strip, `+ Add packaging`. No separate editor; no pencil icon; every change commits immediately and reloads.

**Capability gating**: viewing products requires `can_view_products`. Each mutation maps to its own capability: `can_edit_price`, `can_edit_party`, `can_adjust_stock`, `can_post_opening_balance`, etc. Cashiers see read-only product detail by default.

**Lives on web instead**: spreadsheet-style bulk price + threshold editor, CSV import (300-row initial onboarding), bulk category change, printable shelf labels + barcode label printing, image management, attribute schemas, product variants, kits / BOM.

### 7.4 Low stock + Top movers
Two reports under the PRODUCTS drawer group.

- **Low stock** — items at or below their reorder threshold, sorted lowest first. Tap a row → product detail. Refreshes on return.
- **Top movers** — period selector (7 / 30 / 90 days) in the app bar. Two segments: top sellers (sorted by base-unit volume sold) with revenue + sale count, and dead stock (items with stock on hand and zero sales in the period). Tap a row → product detail.

**Capability gating**: both surface require `can_view_reports`.

**Lives on web instead**: cross-shop top-mover comparison, reorder-suggestion workflow that pre-fills a Receive, scheduled emailed reports, ML-powered demand forecasting.

## 8. Stock management on mobile

The mobile app's stock surface is **product-centric**, not warehouse-centric. The shopkeeper thinks about Bariis-the-product, not stock-batch-#473.

The single stock-adjust surface is a bottom sheet from product detail with four modes:

| Mode | Reason posted | Use case |
|---|---|---|
| **Opening** | `opening` | "What I had in stock before the app." |
| **Add** | `correction` | "Found this stash behind the shelf." |
| **Subtract** | `spoilage` | "These bananas went bad." |
| **Set exact** | `correction` (delta = target − current) | "I counted; the real total is 47 kg." |

Each mode is one chip; the amount + optional note + live preview round out the sheet. Posts through `post_inventory_adjustment` with the right reason code.

**Capability gating**: `can_adjust_stock`. Opening balances additionally require `can_post_opening_balance`.

**Lives on web instead**: bulk physical-inventory count workflow (print sheet → walk shelves → enter totals → review variance → post), per-product stock movement history, multi-location stock + transfers, batch / expiry tracking.

## 9. Settings on mobile

Settings is intentionally small. Anything that could be edited daily belongs in a flow, not Settings.

Mobile Settings contains:
- Shop defaults that surface during flows (currency display, default language)
- Per-shop toggles (low-stock warning on/off, low-stock global threshold)
- Sign out
- Help (link to WhatsApp / email channel)

Mobile Settings does **not** contain:
- Branding (logo, address) — these appear on printed receipts, edited on shop admin portal
- Receipt template — shop admin portal
- Tax configuration — shop admin portal
- Integrations — shop admin portal
- Plan + billing — shop admin portal
- Cashier invitations — shop admin portal

This is the boundary. Mobile Settings is "things a single owner edits on their own phone at their own pace." Anything else routes through the back office.

## 10. Capability gating in the mobile UI

The capability model from `docs/roles-and-permissions.md` is the universal grammar for what shows and what hides.

| Gating mechanism | Where it applies |
|---|---|
| **Tile / drawer entry hidden** | If the user lacks any capability that the destination requires, the entry point disappears entirely. No dimmed-button cluttering the UI. |
| **In-screen action hidden** | Edit buttons, FABs, swipe actions, popup-menu items all disappear when their capability is missing. |
| **Route gating** | A direct push of a route the user cannot reach (deeplink, restore-from-background) lands them on Home with a brief toast. |
| **Backend rejection toast** | If the backend rejects an action that the UI thought was allowed (race between role change and screen), the user sees a non-blocking error toast and the screen reloads. |
| **Read-only mode** | Most screens have a read-only render path for users who can view but not edit. Cashier viewing Product detail sees prices and stock; the chips are visible but their tap is a no-op with a "Contact owner" toast. |

The effective capability set is delivered to the app at session start and updated via realtime subscription when roles change.

## 11. Real-time sync from web edits

When the owner changes a price on the shop admin portal, the cashier's open Product detail screen should reflect it within seconds, without manual refresh. Same for new categories, new packagings, new threshold edits, party edits.

The pattern:

- The mobile app holds Supabase realtime subscriptions for the tables relevant to the current screen.
- On a realtime event, the screen re-fetches the affected row(s).
- Visible feedback is subtle (small refresh shimmer, not a banner).
- Long-running detail screens (Product detail, Party detail) subscribe; transient screens (cart) do not.

This is the contract that makes the three-component system feel like one product. Without it, the cashier and the owner are working from different mental models.

## 12. Audit log contribution

Mobile **writes to** the audit log on every state-changing action. Mobile does **not display** the audit log in detail — that's the shop admin portal's job. The most a cashier sees on mobile is "voided by Asha 10 min ago" inline on a sale row.

If a feature on mobile needs to display "who did this and why", it's a sign the design should defer that surface to the web portal.

## 13. Behaviour during platform impersonation

When a platform support agent is impersonating the owner via the system admin portal, the mobile app shows a **persistent banner** at the top: "Dukan support is viewing your data right now — <reason>." The banner is bright, dismissable per session, and re-arms next time impersonation begins.

This is a trust feature. Shopkeepers should never wonder whether something they're seeing is being watched.

## 14. Internationalisation

- Every string is in ARB (`lib/l10n/app_*.arb`). No literal strings in code outside of debug labels.
- Both Somali and English are first-class. Missing Somali strings are release blockers, not warnings.
- Reference data is locale-resolved server-side via the `name_translations` jsonb pattern.
- The language toggle is one tap from any screen (currently in app bar before auth, in Settings post-auth — see `docs/ux.md`).
- Plain words only. No accounting jargon ("receivable", "ledger", "post"). Use "money customer owes", "saved".

## 15. Offline behaviour

The mobile app is **online-tolerant**, not offline-first. Spotty 4G is the design target.

- Caches: recent results from search RPCs and listing RPCs are kept in memory and survive short backgrounds.
- Write queue: posts with `client_op_id` retry on transient failure. Idempotency on the server prevents duplicates.
- UI never blocks waiting for the network on a daily-flow action. SAVE clears the UI immediately; failure surfaces as a non-blocking toast.
- Catalog browsing degrades to "cached results only" with a banner when offline.
- Reports are unavailable offline and say so.

Full offline-first (durable queue across app restarts, conflict resolution on reconnect) is **not** v1. It's a design target for v2.

## 16. Error handling philosophy

| Severity | Treatment |
|---|---|
| **Recoverable, low-stakes** (search failed, list reload failed) | Inline retry affordance ("Try again") within the screen. No popup. |
| **Recoverable, mid-stakes** (save failed because offline) | Persistent toast with retry. User can continue working. |
| **High-stakes, blocking** (cannot post — backend rejected with a reason) | Inline message at the action site with the reason. No modal dialog. |
| **Soft errors that look like errors but aren't** (low stock after sale) | Warning toast, not an error. "Sukar stock is now 2 Kg. Receive soon." |

There are no blocking error dialogs in any daily flow. Ever.

## 17. Notifications

Mobile receives push notifications for things that need the shopkeeper's attention right now: low-stock thresholds breached, opening-balance reminders, support messages, owner-approved cashier actions (when the approval workflow ships). Quiet hours are configurable.

Mobile does **not** receive notifications for things that don't need immediate action (scheduled reports — those are email / web).

## 18. What mobile deliberately does *not* do

This list exists to protect the mobile app from feature creep. Every entry here has been considered and routed elsewhere on purpose.

- ❌ **Bulk product onboarding from a spreadsheet** → shop admin portal CSV import.
- ❌ **Bulk price update** ("+5% on all rice") → shop admin portal table editor.
- ❌ **Multi-select on lists** with batch actions → shop admin portal.
- ❌ **Wide reports with many columns** → shop admin portal.
- ❌ **Cross-shop dashboard** → shop admin portal.
- ❌ **Printing** — receipts come via SHARE adapter, not native print → shop admin portal for label / barcode / count-sheet printing.
- ❌ **Cashier user management** (invite / revoke) → shop admin portal.
- ❌ **Audit log viewer** (full searchable history) → shop admin portal.
- ❌ **Receipt template editing** → shop admin portal.
- ❌ **Tax configuration** → shop admin portal.
- ❌ **Plan + billing** → shop admin portal.
- ❌ **Integration management** (banking, accounting export, payment gateway) → shop admin portal.
- ❌ **Per-tenant platform configuration** → system admin portal.
- ❌ **Catalog curation, template authoring, translation management** → system admin portal.

If a request maps to any of these, the answer is: *not on mobile, by design.*

## 19. Web-portal handoffs (the inverse view)

For shopkeepers who do have access to a desk + computer, every mobile module has a counterpart on the shop admin portal that does the wider / bulkier / printier version of the same job. The two surfaces share the same backend RPCs; they differ in *what makes sense in 6 inches vs 27*.

| Mobile module | Counterpart on shop admin portal |
|---|---|
| Sale | Sales history with wide filters · cashier comparison · printable Z-report · profit by item · split-tender support *(future)* |
| Receive | Bono history with supplier scorecards · cost-variance report · purchase orders *(future)* |
| Payment | Aging exports · scheduled payments · dunning campaigns |
| Expense | Trend analytics · budget vs actual · bulk CSV import |
| History | All exports · custom report builder · scheduled emailed reports |
| People | CSV import + export · dedupe / merge · marketing segments · credit-limit management |
| Products | Bulk price + threshold editor · CSV import · variant + image management · label + barcode printing |
| Reports | BI-grade dashboards · custom report builder · saved views |
| Settings | Branding, receipt template, tax config, integrations, cashier management |

These handoffs are not "the mobile app is incomplete." They are the system working as designed.

## 20. Tech notes (target state)

The mobile app's structural commitments. Implementation details (folder structure, state-management library, dependency choices) live in code; what follows is the contract.

- **Flutter** (Android + iOS).
- **Provider** for screen-scoped state; controller classes are `ChangeNotifier`s.
- **All RPC calls** go through one `ShopApi` instance; no `SupabaseClient` references outside that file.
- **One Supabase auth session** per device. Multi-account is out of v1.
- **Realtime subscriptions** scoped to mounted screens.
- **`client_op_id`** on every mutation that can be retried.
- **`Localizations.localeOf` reads** happen in `didChangeDependencies`, never `initState`.
- **Tests** cover every daily flow as widget tests; backend RPCs are tested in `scripts/test-backend-migrations.sh` (Dockerized harness).

## 21. The two things that protect this design

If you take one thing from this document, take these two.

1. **Don't add features to mobile that belong on web.** It is constantly tempting (a power-user shopkeeper asks, an investor sees a competitor doing it, a designer has a clever idea). Every time the mobile app absorbs work the web portal should do, the mobile UX gets a little worse for the cashier who actually uses it daily. Boundaries are the product.
2. **The speed contract is a release gate.** A feature that regresses Sale-1-item to 5.4 seconds is not ready. Period. Re-do the design.

## 22. Companion documents

- `docs/product-vision.md` — the three-component architecture.
- `docs/roles-and-permissions.md` — the capability model this app honours.
- `docs/ux.md` — speed contract + interaction rules + anti-patterns.
- `docs/ux-screens.md` — per-screen pixel design.
- `docs/architecture.md` — backend, RLS, OCR pipeline.
- `docs/backend-schema.md` — concrete migrations + posting RPC contracts.
- `docs/mobile-app-alignment.md` — punch list mapping the current codebase to this target.

## 23. Change log

| Date | Change | Author |
|---|---|---|
| 2026-06-11 | Initial draft. Target state framing. Companion to `mobile-app-alignment.md`. | — |
