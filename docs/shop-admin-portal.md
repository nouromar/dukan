# Shop Admin Portal — Design

> **Target state**, not as-built. This document is the design contract for the **shop admin portal**: the web-based back office for organization owners and shop owners. As of writing, the portal does not yet exist in this repository; this document is what we're building toward. The current-state alignment lives in `docs/shop-admin-portal-alignment.md` once that artifact is created.
>
> Companion documents:
> - `docs/product-vision.md` — why all three components exist and how they relate.
> - `docs/mobile-app.md` — the daily transactional surface this portal complements.
> - `docs/system-admin-portal.md` — the platform-staff mission control (separate audience, separate concerns).
> - `docs/roles-and-permissions.md` — the capability vocabulary this portal both uses and surfaces.
> - `docs/backend-schema.md` — the shared backend.

---

## 1. Purpose

The shop admin portal is the **back office for the business that owns the shop**. It is the surface where an organization owner running multiple shops, a single-shop owner doing month-end work from a laptop, or a part-time bookkeeper preparing tax filings does the wide, deep, bulk, and analytical work that mobile is the wrong tool for.

It exists because:

- Mobile is optimised for the cashier at a counter with one thumb. That same cashier's owner-mother needs to compare three shops side-by-side at the end of the week.
- Owners do month-end work — reconciliation, exports, supplier statements — sitting at a kitchen table laptop, not at a counter.
- Some operations are inherently wide: bulk price change across 200 SKUs, reviewing 60 days of sales for an audit, comparing top movers across 5 shops.
- Some operations are inherently print-shaped: catalog booklet for a new wholesaler, supplier statement to settle a debt, Z-report at end-of-day.

The portal is **not** a replacement for mobile. A shopkeeper who only uses the portal is using Dukan wrong. The portal is for the *administrative* mode of the business, not the *operating* mode.

## 2. Who uses it

### 2.1 Primary persona — the organization owner

A small-business owner who runs **2–6 neighbourhood shops** under one organization. Spends weekday mornings at the wholesaler, weekday afternoons checking on the shops, evenings reviewing yesterday's numbers from a laptop at home. Hands on enough to override prices and approve voids but does not run a register day-to-day.

Their portal session is typically: "compare today vs. last Thursday across all shops" → "drill into Shop B's slow afternoon" → "pull the supplier statement for next week's Maandeeq order" → "fire off a price change for the 12 items that just got more expensive at the wholesaler."

### 2.2 Secondary persona — the single-shop owner

Owns one shop, also serves customers half the day. Uses mobile for daily flows; uses the portal at the end of the week or month for the work mobile makes hard. Less time per session than the org owner. Wants reports, exports for the bookkeeper, and the occasional bulk price update.

### 2.3 Tertiary persona — the bookkeeper / accountant

Part-time, often the owner's relative, often new to the shop's data. Logs in monthly. Wants exports (CSV / PDF) that fit their existing workflow. Should never need to learn the operating model of the business — they need numbers.

### 2.4 Non-personas

- **Cashier** — never uses the portal. Daily flows are on mobile. (If a cashier needs the portal for some daily task, that's a design failure.)
- **Dukan platform staff** — has their own portal (`docs/system-admin-portal.md`). They may see *some* shop admin data in support contexts, but they enter through the system admin portal with explicit impersonation, not through this portal directly.

## 3. Target devices and form factors

In priority order:

1. **Desktop / laptop (1280px–1920px)** — primary form factor. Most owner sessions are here. Optimised for keyboard + mouse, wide tables, multi-pane layouts.
2. **Tablet (768px–1280px)** — comfortable for review work; the portal works in landscape and portrait but is not optimised for it as the primary surface.
3. **Large-screen mobile (375px–768px)** — works, but heavily de-featured. The portal on mobile is a "I left my laptop at the shop" fallback, not a parallel surface to the mobile app. The mobile app remains the right tool for daily work even on a 6.7" phone.

Print is a first-class output mode — see § 13.

## 4. Operating principles

The shop admin portal honours the same four north-star principles from `docs/product-vision.md`, adapted to its audience and form factor:

1. **Speed is still sacred** — but the measurement shifts. The metric is *time-to-insight* and *time-to-bulk-action*, not "≤ 5 seconds to post a sale." A bulk price change for 50 items should complete in under 30 seconds end-to-end, including review. A monthly P&L should render in under 3 seconds.
2. **No accounting jargon** — same as mobile. "Money customers owe you" not "Accounts Receivable." The bookkeeper persona is the only audience that knows the jargon, and we are deliberately not catering to their preferred vocabulary at the cost of the owner's literacy.
3. **Bilingual first-class** — every screen, every column header, every report title. Somali + English. Switching language is one click, persistent, applies portal-wide.
4. **No silent state changes** — bulk operations always preview-then-confirm. Every irreversible action is a two-step. Audit log captures actor + before-state + after-state for everything.

To these we add three portal-specific principles:

5. **Truth lives in mobile, projection lives in web.** The portal renders, aggregates, exports, and plans. It does not *post* transactions. (The two exceptions are explicitly carved out in § 6.)
6. **Wide is a feature, not a bug.** The portal uses the screen. Tables can be 12 columns wide. The mobile constraint of "one screen per task" does not apply here.
7. **Bulk-by-default for repetitive work.** If an owner is about to do the same thing 20 times, the portal should offer a way to do all 20 in one action.

## 5. Information architecture

### 5.1 Top-level navigation

A persistent left rail (collapsible) with these sections, in this order:

1. **Overview** — landing page, single-shop or multi-shop dashboard.
2. **Sales** — history, reports, voids, exports.
3. **Inventory** — products, stock, adjustments, low stock, top movers, dead stock.
4. **People** — customers, suppliers, aging, statements.
5. **Money** — payments, expenses, P&L, cash position.
6. **Setup** — shop settings, staff, roles, templates, integrations.
7. **Audit** — log search, filter, export.

The org-owner persona always has a **shop switcher** in the top bar showing the currently-scoped shop or "All shops." The single-shop persona's switcher is collapsed to a static shop name.

### 5.2 Shop scope vs org scope

Most modules render either at **shop scope** (Sales for one shop) or **org scope** (Sales across all shops). The shop switcher controls which. Some modules — Audit, Staff, Integrations — naturally span scopes and have their own scope selector inline.

### 5.3 Search

Global search lives in the top bar. Searches across: products, parties (customers + suppliers), invoices/receives by date or amount, audit entries. Scoped to the current shop unless the user explicitly selects "across all shops."

---

## 6. Module specs

Each module below has the same structure: **What it does**, **Lives on mobile instead** (the corresponding mobile surface, if any), and **Capability gating** (which roles see it).

### 6.1 Overview

#### What it does

Single-shop view shows a today/this-week/this-month dashboard: revenue, sales count, gross margin (from COGS snapshots), cash position, top 5 SKUs, low-stock count, receivables owed, payables outstanding. A timeline chart toggleable between revenue / margin / count.

Multi-shop view shows the same cards per shop, side-by-side, sortable. A comparison strip: which shop is up vs. yesterday, which is down. Drill-down: click any number → land in that shop's relevant module pre-filtered.

#### Lives on mobile instead

The mobile Home Today card shows today's revenue + count for the current shop. Beyond "today, this shop," all of this lives on web.

#### Capability gating

Anyone with `dashboard.view` on any in-scope shop. Org-scope view requires `dashboard.view_org`.

---

### 6.2 Sales

#### What it does

- **Sales history** — filterable, sortable, paginated table of every posted sale. Columns: date/time, cashier, party (customer name for credit sales), line count, gross, tax, total, payment method, voided-or-not. Filters: date range, cashier, party, payment method, voided. Export to CSV/PDF.
- **Sale detail** — click a row → full receipt-like view: lines, COGS-snapshot margin per line, void status, audit trail.
- **Void** — owner-only action; same backend RPC as mobile's owner void; preview the reversing entry before confirm. The portal makes the 7-day window from mobile easier to honour because the reasoning column is wider.
- **Sales reports** — daily / weekly / monthly summaries. Breakdowns by cashier, by category, by hour-of-day. Comparable across shops.

#### Lives on mobile instead

The mobile Sales History exists for the owner-on-the-floor who wants to look at today's sales without leaving the counter. It is not a replacement for the portal's history.

The mobile Sale detail screen shows the same line-level data but in a portrait-shaped layout. The portal's version surfaces margin per line; the mobile version does not (mobile shows revenue only).

#### Capability gating

`sales.history.view` (cashier baseline, scoped to own shifts in the cashier role) — for read.
`sales.void` (owner role) — for void action.
`sales.export` (owner role) — for CSV/PDF download.

---

### 6.3 Inventory

#### What it does

- **Products** — paginated grid, default 50 rows. Columns: name, category, base unit, default packaging, sale price, current stock, low-stock threshold, last received, last sold. Bulk-select for: change category, change reorder threshold, deactivate, export. Inline edit on price + threshold.
- **Bulk price change** — select N products, set price by: absolute amount, percentage delta, or by formula referencing last cost (e.g., "last cost × 1.25"). Preview every changed row before confirming.
- **Product detail** — full information view including all packaging variants, all aliases, all barcodes, full sale + receive history for the SKU, margin history. Edit any field inline; every edit appears in audit log.
- **Stock adjustments** — list of every posted adjustment (opening, correction, spoilage) with actor, reason, line count, total quantity moved. Click to drill into the lines.
- **Adjustment posting** — new adjustment via the same `post_inventory_adjustment` RPC mobile uses. Lines can be pasted from a spreadsheet. Owner-only.
- **Low stock** — current view of every SKU below threshold. Sort by velocity to see "which low-stock items will run out fastest." Export to CSV for the wholesaler order.
- **Top movers + dead stock** — same as mobile, extended: 365-day window option, profit-weighted ranking, dead-stock value column.

#### Lives on mobile instead

Mobile Product detail is the per-SKU surface for the cashier looking something up or the owner-on-the-floor adjusting a price. Mobile cannot do: bulk price changes, formula-based pricing, spreadsheet-paste adjustments, ranged history view.

Mobile Stock adjust sheet handles single-SKU adjustments. Bulk adjustments live here.

Mobile Top movers handles 7/30/90-day windows. Year-over-year views live here.

#### Capability gating

`inventory.product.view` — read.
`inventory.product.edit` — inline edit.
`inventory.product.bulk_edit` — bulk operations (owner baseline; managers may have it).
`inventory.adjustment.post` — owner-only.

---

### 6.4 People

#### What it does

- **Customers** — list with balance-first sort (largest debtors at top), filter by debt status, filter by activity recency. Click into customer detail.
- **Customer detail** — contact info, full transaction history (sales + payments), running balance graph, allocation list (which sale each payment cleared). Action: send statement via WhatsApp link or PDF download. Owner can edit contact info and opening balance (one-time, audited).
- **Suppliers** — symmetric: list, balance-first sort, supplier detail with receive history + payment history + statement.
- **Aging report** — receivables and payables bucketed by age: 0–7 days, 8–30, 31–60, 61+. Drill into any bucket to see which parties contribute. Total at the bottom matches the projection on `party.receivable` / `party.payable` (reconciliation guarantee — if it diverges, the audit log shows why).
- **Statement export** — pick a party, pick a date range, generate a PDF with all transactions and the running balance. WhatsApp share link.

#### Lives on mobile instead

Mobile People surfaces the same per-party detail but does not have: aging buckets, statement PDF export, opening-balance edit (that one is mobile-restricted to onboarding flow), bulk export.

#### Capability gating

`people.party.view` — read.
`people.party.edit` — edit contact info (manager+).
`people.party.opening_balance` — one-time post (owner-only).
`people.statement.export` — owner-or-manager.

---

### 6.5 Money

#### What it does

- **Payments** — list of every payment in or out. Same filters as Sales history. Detail view shows allocations: which sales/receives this payment cleared. Owner can re-allocate if implicit-allocation got it wrong.
- **Expenses** — list with category filter. Bulk re-categorisation. Inline edit on memo. Export.
- **P&L (profit and loss)** — period selector. Revenue (from posted sales), COGS (from sale-line snapshots), expenses (by category). Gross margin, net margin. Comparable to prior period side-by-side. Export to PDF for the bookkeeper.
- **Cash position** — current cash on hand (from sales received in cash minus expenses paid in cash minus payments out in cash). Reconcile-with-counted-cash tool: enter the counted amount → see the discrepancy → optionally post a correction expense. Owner-only.

#### Lives on mobile instead

Mobile Payment / Expense screens handle the single-transaction post. Mobile shows yesterday's revenue on the Today card. Mobile does not surface gross margin, net margin, P&L, or cash reconciliation.

#### Capability gating

`money.payment.view` / `money.expense.view` — manager baseline.
`money.payment.reallocate` — owner-only.
`money.report.view` — owner-only.
`money.cash.reconcile` — owner-only.

---

### 6.6 Setup

#### What it does

- **Shop settings** — currency, timezone, language, low-stock threshold default, receipt template (logo, header/footer text, languages on receipt). All edits audit-logged.
- **Staff** — list of users with access to this shop or org. Invite by phone number (sends an SMS link). Assign role. Remove access. Per-user audit trail of assignments.
- **Roles** — for v1 the role list is fixed (Cashier, Manager, Shop owner, Org owner — see `docs/roles-and-permissions.md` § 6). For v1.x the role editor lets owners *clone* a standard role and tweak its capability set. Custom roles are scoped to the org.
- **Templates** — apply a starter template to a new shop. Re-apply (idempotent) to pull in template updates. Diff view before apply.
- **Integrations** — placeholder for v2. (Accounting export, WhatsApp Business API, payment gateway, etc.)
- **Branding** — receipt template, logo upload, business registration info (for receipts/statements where regulated).

#### Lives on mobile instead

Mobile Settings has a slim subset: language, currency display, low-stock threshold toggle. Anything that affects what other people see (receipt template, staff list, branding) lives only here.

#### Capability gating

`setup.shop.edit` — owner.
`setup.staff.invite` — owner.
`setup.staff.assign_role` — owner.
`setup.roles.edit` — owner (v1.x).
`setup.template.apply` — owner (cooperative with platform staff who set the template up).
`setup.branding.edit` — owner.

---

### 6.7 Audit

#### What it does

Searchable, filterable view of every entry in `audit_log` for in-scope shops. Filters: actor, action type, entity type, date range, shop. Each entry shows actor + before-state + after-state where safe (PII redacted per role). Export filtered view to CSV.

#### Lives on mobile instead

Mobile surfaces inline audit cues — "voided by Asha 10 min ago" on a sale row — but never the searchable full log. The searchable view lives only here.

#### Capability gating

`audit.view` (org owner + shop owner baseline; manager may have read access scoped to non-PII fields per `docs/roles-and-permissions.md`).
`audit.export` (owner-only).

---

## 7. The two exceptions to "no posting from web"

The portal *almost* never posts transactions. The two exceptions are deliberate:

1. **Inventory adjustments** (§ 6.3) — owner-only, posted via the same `post_inventory_adjustment` RPC mobile uses. Justified because (a) bulk paste from spreadsheet is the dominant input shape, (b) opening-stock import is fundamentally a portal flow, and (c) the cashier role never sees this surface.
2. **Cash reconciliation correction** (§ 6.5) — owner-only, posts a correction expense via `post_expense`. Justified because the reconciliation calculation happens on the portal and asking the owner to re-enter the discrepancy on mobile is friction without value.

Both go through the same RPCs as mobile. Both write to the same `audit_log`. Both honour the same `client_op_id` idempotency.

Everything else — sales, receives, payments, expenses — posts only from mobile.

## 8. Capability gating mechanics

The portal consults the same capability model as mobile (`docs/roles-and-permissions.md`):

- **Nav items hidden** when the user has no capability for the section.
- **Action buttons hidden** when the user has read but not write.
- **Inline edit disabled** with a tooltip "Read-only — contact owner" when capability is missing.
- **Bulk-select** is hidden when bulk write capability is missing.
- **Export disabled** when export capability is missing.
- **Org scope toggle** hidden for users who only have access to one shop.

The portal does **not** silently hide differences between scope and capability — if a manager sees an action they cannot perform (because they have it for one shop but not another), the action is visible but disabled with the scope explained.

## 9. Realtime sync

The portal subscribes to the same Supabase realtime channels mobile does. The use cases differ:

- **Owner watches the shops from home** — the multi-shop overview updates as cashiers post sales. Charts re-render every few seconds.
- **Owner edits a price on the portal** — within seconds, the cashier's mobile reflects the change (covered in `mobile-app.md` § 11).
- **Owner sees a void come through from mobile** — the audit log entry appears live.

Realtime is **decorative** on the portal, not load-bearing. The owner can always refresh. Mobile can post if the realtime channel drops. The portal works fully without realtime, just feels less alive.

## 10. Multi-shop / org features

The org-owner persona is the primary user of the portal. Multi-shop features are first-class, not afterthoughts:

- **Shop switcher** in the top bar with "All shops" as a valid scope on most modules.
- **Org-scope dashboard** in Overview.
- **Cross-shop comparisons** in Sales reports (revenue ranked by shop), Inventory (which shops sell which SKU best), People (which shop has the most receivables outstanding).
- **Staff that spans shops** — one user, multiple shop assignments, one entry per assignment in `role_assignment`.
- **Org-level audit log** — the org owner can see audit entries across all org-owned shops in one view.
- **Bulk-apply settings across shops** — change a low-stock threshold default once, optionally propagate to N shops in the org.

Multi-shop features are **invisible to single-shop owners**. The portal detects the user's scope at session start and collapses unused affordances.

## 11. Bulk operations

The portal is the bulk surface. Patterns:

- **Multi-select with bulk action bar** — checkboxes in every table. Selecting any row reveals a sticky bottom bar with the available bulk actions for the selection.
- **Preview-then-confirm** — every bulk write shows a preview screen (or modal) with the diff before the post. Cancel returns to the original selection.
- **Spreadsheet paste** — wherever lines are the input (adjustments, opening stock, bulk price change), the portal accepts paste from Excel/Sheets. Column mapping UI on first paste; remembered for subsequent pastes.
- **Idempotent on retry** — bulk operations use one `client_op_id` per item; partial failure is recoverable. The UI shows per-line success/failure.

Bulk failures **never** roll back per-line. A bulk price change that hits 100 SKUs and fails 3 of them updates 97 and reports the 3 with their errors. The owner re-tries the 3.

## 12. Reports

All reports follow a consistent skeleton:

- **Period selector** at the top: today, yesterday, this week, last week, this month, last month, custom range.
- **Compare-to selector** to the right: none, prior period, same period last year.
- **Filter chips** below: shop (if org-scoped), cashier, category, etc. — filter chips depend on the report.
- **Chart at top, table below.**
- **Export** button: CSV, PDF, WhatsApp share link.

Standard reports for v1:

- Sales by day / week / month.
- Sales by cashier.
- Sales by category.
- Top movers + dead stock (with optional profit-weight).
- P&L.
- Aging (receivables + payables).
- Expense by category.
- Stock valuation (current stock × avg_cost).
- Cashier shift Z-report (when shifts ship — v1.x).

v1.x and v2 add: tax reports, custom report builder, scheduled report email, dashboards beyond Overview.

## 13. Print and PDF

Print is a first-class output mode. Receipts, statements, reports, catalogs all have **Print** and **Download PDF** buttons. The PDF generator runs server-side (Edge Function) so the output is identical regardless of the user's browser.

Standard PDF outputs:

- **Receipt** — re-print of a posted sale.
- **Statement** — per-party transaction history with running balance.
- **Catalog booklet** — owner-curated subset of products with prices and barcodes; useful when a new wholesaler asks "what do you stock?"
- **Z-report** — end-of-shift summary (when shifts ship).
- **Tax report** — when tax engine ships (v2).
- **Stock take sheet** — for a manual stock count (v1.x — when stock-count workflow ships).

PDFs honour the shop's receipt template (logo, header, footer) where appropriate.

## 14. CSV exports / imports

The bookkeeper persona uses CSV. The portal supports:

**Exports** — every list view has an "Export CSV" button. The export respects all active filters. Columns match what the user sees on screen. Always UTF-8 with BOM (so Excel doesn't mangle Somali).

**Imports** — these import flows exist:

- **Opening stock** (during onboarding) — match by name to existing SKUs; create missing with confirmation; preview adjustment lines before posting.
- **Bulk price update** — pre-formatted spreadsheet with SKU + new price; preview every change; post.
- **Customer / supplier list** — bulk-create parties from a spreadsheet (during onboarding).

The portal does **not** import sales or expenses from CSV. Posting is mobile-or-RPC, not bulk-loaded.

## 15. Receipt and branding templates

Each shop has a receipt template the cashier app uses for sale receipts. The portal is where this template is configured:

- Logo (PNG / JPG, max 2MB).
- Header text (multi-line, both languages).
- Footer text (multi-line, both languages).
- Show/hide cashier name on receipt.
- Show/hide line-level discounts (when discounts ship).
- Tax line treatment (when tax ships).
- Receipt language preference (matches shop default; per-receipt override on mobile).

The same template feeds the PDF receipts the portal generates.

## 16. Staff management

The portal is the only place staff are added or removed.

Workflow for inviting a cashier:

1. Owner types the new cashier's phone number.
2. Selects role (Cashier baseline; Manager for an experienced employee).
3. Selects shop(s) — org owners can assign to multiple shops at once.
4. Sends invite — generates an SMS deep-link to the mobile app's onboarding flow.
5. New cashier opens the link, completes phone OTP, lands on the home of the assigned shop.

Workflow for revoking access:

1. Owner finds the user in the staff list.
2. Selects "Revoke access from this shop" or "Remove from organization."
3. Confirmation modal explains the consequence (next sign-in, the cashier loses access; any pending offline writes will fail).
4. Audit log records the revoke with timestamp + actor.

The owner can edit role assignments but cannot grant capabilities that are restricted to higher scopes (an org owner cannot create a capability that the platform tier reserves).

## 17. Internationalisation

Every label, column header, button, report title, error message, PDF output, and email is bilingual (English + Somali). Switching language is one click; persistent per user.

The bookkeeper persona is the most likely to want English-only output (their downstream tools are English). The Somali-first owner is the most likely to want Somali-only. Both must be supported equally.

Numeric formatting respects locale (decimal separator, currency symbol position). Dates respect locale.

## 18. Online-only is OK here

The portal is **online-only**. There is no offline mode, no write queue, no local cache beyond browser standard caches. Justification: portal sessions are not time-critical the way a cashier transaction is. The owner can wait. The bookkeeper can wait. If connectivity is unreliable, the portal degrades to "please retry" rather than buffering.

This is the opposite trade-off from mobile (`docs/mobile-app.md` § 15) and is deliberate.

## 19. Error handling philosophy

The portal can use blocking modals where mobile cannot. The cashier at a counter cannot afford to wait for a confirmation; the owner reviewing a bulk price change can. Modals are appropriate for:

- Confirm destructive actions (revoke staff, void sale, delete draft template).
- Preview-then-confirm on bulk writes.
- "Are you sure? Type the shop name to confirm." for archive/delete operations.

Modals are **not** appropriate for:

- Recoverable errors that mobile would treat as toasts.
- Informational messages.
- Progress indication on long operations (use inline progress instead).

## 20. What the shop admin portal deliberately does NOT do

These are not v1 omissions — they are permanent design boundaries. If you find yourself wanting to add one of these, push back on the requirement; if it survives, write a `docs/decisions.md` entry first.

1. **Post sales.** Sales originate at the counter, on mobile. The portal never posts a sale.
2. **Post receives.** Same — receives originate where the bono is being taken, on mobile.
3. **Post payments.** Mobile.
4. **Post expenses** *except* the cash-reconciliation correction (§ 7).
5. **Run as the daily tool for a cashier.** The portal is back-office. A cashier who only uses the portal is being used wrong.
6. **Manage platform-level data** (reference tables, starter templates, languages, currencies). That's the system admin portal.
7. **Impersonate users.** That's the system admin portal too.
8. **Manage other organisations' data.** Strict org-scope enforcement.
9. **Edit posted transactions in place.** Corrections go through reversing entries — same as mobile.
10. **Drive a hardware register / cash drawer / receipt printer.** Mobile does that.
11. **Replace the bookkeeper's accounting software.** The portal exports to the bookkeeper's tools; it does not become them.

## 21. Mobile → portal handoffs (inverse view)

Looking from the mobile direction, which mobile flows have a richer portal counterpart:

| Mobile surface | Portal counterpart | Why portal is wider |
|---|---|---|
| Sale receipt sheet | Sales § 6.2 + Print § 13 | Bulk re-print, statement-style grouped receipts, margin per line. |
| Sales history | Sales reports § 12 | Period comparison, cross-shop, export. |
| Receive history | Money § 6.5 + supplier statements § 6.4 | Aging, supplier rollup. |
| Payment screen | Money § 6.5 (re-allocate) | Manual allocation, history-of-allocations view. |
| Expense screen | Money § 6.5 + Setup § 6.6 (categories) | Bulk recategorise, expense reports. |
| Customers / Suppliers | People § 6.4 | Aging, statements, opening-balance edit during onboarding. |
| Products list | Inventory § 6.3 | Bulk price change, formula pricing, mass deactivation, year-over-year. |
| Product detail | Inventory § 6.3 product detail | Same model, more screen real estate; year-of-margin history; barcode print sheet. |
| Stock adjust sheet | Inventory § 6.3 adjustments | Spreadsheet paste, opening stock import. |
| Today card | Overview § 6.1 | Multi-shop, period comparison, trend charts. |
| Top movers | Inventory § 6.3 | 365-day window, profit-weighted rank. |
| Settings | Setup § 6.6 | Receipt template, branding, staff, roles, templates. |
| Drawer link list | Left rail § 5.1 | Same modules, broader scope. |

## 22. Tech contract

- **Frontend:** React / Next.js (App Router). Server components for read-heavy pages; client components for interactive bulk editors.
- **State:** Server state via Supabase JS client + Next.js fetch caching; client state minimal (form state, selection state).
- **Realtime:** Supabase realtime channels for decorative live updates (§ 9).
- **Authentication:** Same Supabase Auth as mobile; same JWT; same capability resolution.
- **Authorisation:** All writes go through the sanctioned RPCs in `docs/backend-schema.md`. UI gating is informational only.
- **PDF generation:** Edge Function with a server-side renderer (e.g., Puppeteer or a templating library). PDFs render identically regardless of client browser.
- **CSV generation:** Either server-side (large exports) or client-side (small lists). UTF-8 with BOM unconditionally.
- **i18n:** Next-i18next or equivalent. Same `app_en.arb` / `app_so.arb` keys *should* be reusable (same translations) but the portal will need its own keys for portal-only UI.
- **Deployment:** Vercel or equivalent edge platform; one deployment per environment (dev / staging / production).
- **Repo location:** New top-level directory `admin-web/` alongside `app/dukan/`, sharing nothing in `src/` but referencing the same `supabase/` schema.

## 23. Protective rules

Two rules that catch the recurring failure modes:

1. **Don't add features to the portal that belong on the system admin portal.** If a feature is about *Dukan staff helping a customer* — impersonation, support sessions, platform reference data editing — it belongs on the system admin portal. The shop admin portal is for the business that owns the shop.

2. **Don't add posting capability the design doc doesn't carve out.** The two exceptions in § 7 are exhaustive. Any proposal to add a third posting path — "let's let the owner enter a sale from web" — requires a `docs/decisions.md` entry that explains why the rule is wrong for this case.

---

## 24. Companion documents

- `docs/product-vision.md` — why three components.
- `docs/mobile-app.md` — the transactional companion.
- `docs/system-admin-portal.md` — the platform-staff console (separate audience, separate concerns).
- `docs/roles-and-permissions.md` — capability vocabulary.
- `docs/backend-schema.md` — shared backend.
- `docs/ux.md` — UX principles (some adapt to portal, some are mobile-specific).
- `docs/templates-and-learning.md` — template content the portal applies.
