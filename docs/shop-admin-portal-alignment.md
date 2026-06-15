# Shop Admin Portal — Alignment

> **Punch list bridging the empty state to `docs/shop-admin-portal.md`.** Same convention as `docs/mobile-app-alignment.md`: each item is sized + priority-labeled so we can ship pilot-value first and grow into the target state without big-bang rewrites.
>
> **Priority bands:**
> - **P0** — needed before the first pilot org sees the portal.
> - **P1** — needed during pilot operation (lands within first ~4 weeks of pilot).
> - **P2** — needed before public launch beyond pilot.
> - **P3** — v1.x / nice-to-have; deferred without regret.
>
> **Effort sizes:** XS < 30 min · S < 2 h · M < 1 day · L 2–4 days · XL multi-week.

---

## 0. Current state

Empty. No web directory exists. Backend is ready: every RPC the portal needs already exists (or is one task away). Migrations 0050–0053 ship the `audit_log` + `v_party_aging` + `payment_allocation` surfaces the portal will surface. Nothing on the backend blocks portal work.

---

## 1. Tech stack (decided defaults)

| Layer | Pick | Reason |
|---|---|---|
| Framework | Next.js 15 (App Router) | Per design doc § 22; mature server components for read-heavy reports |
| Language | TypeScript (strict) | Generated Supabase types + safety on the bulk-edit surface area |
| Repo location | `web/shop-admin/` | Same monorepo as `app/dukan/`; `web/system-admin/` parallels later |
| Package manager | pnpm | Workspace-friendly for sibling `web/system-admin/` and shared `web/shared/` |
| Styling | Tailwind CSS v4 | Standard in Next.js ecosystem; works with shadcn |
| UI primitives | shadcn/ui (Radix under the hood) | Owns the components; no opaque CSS framework lock-in |
| Tables | TanStack Table v8 | Required for sortable / filterable / selectable tables across every module |
| Forms | React Hook Form + Zod | Type-safe forms, Zod schemas double as RPC payload validators |
| Charts | Recharts | Sufficient for overview dashboard + reports; Tremor as an option if we want batteries-included |
| Date / number | date-fns + Intl.NumberFormat | i18n-aware; no moment-shaped legacy |
| i18n | next-intl | Next.js App Router native; shares JSON message format with our existing ARB intent |
| Auth | Supabase Auth (phone OTP) | Same as mobile; same JWT; same capability resolution |
| Hosting | Vercel | Edge runtime + good Next.js defaults; can move later |

These are defaults. If you want to pre-empt any of them say so before #265 lands; otherwise they hold.

---

## 2. Phase 0 — Scaffolding (P0, foundational)

### 2.1 [P0] Monorepo restructure + pnpm workspace
**Why:** today the repo has only `app/dukan/`. Adding `web/shop-admin/` and (later) `web/system-admin/` needs a workspace declaration so they share `web/shared/` (types, utilities, design tokens).
**Work:**
- Add root `pnpm-workspace.yaml` declaring `app/dukan`, `web/*`, plus a `web/shared` placeholder.
- Add `package.json` at root with workspace scripts (build all, test all, lint all).
- Update CI to install via pnpm.
- Update `.gitignore` for `node_modules/`, `.next/`, etc.
**Effort:** S.

### 2.2 [P0] `web/shop-admin/` Next.js 15 scaffold
**Why:** the actual app shell.
**Work:**
- `pnpm create next-app` with App Router, TypeScript, Tailwind.
- Configure `tsconfig.json` strict, paths.
- shadcn/ui init: `pnpm dlx shadcn-ui@latest init`.
- Folder layout per design (§ 5.1 navigation): `app/(dashboard)/overview`, `/sales`, `/inventory`, `/people`, `/money`, `/setup`, `/audit`, plus auth at `app/login`.
- Root layout with left rail (collapsible), top bar (shop switcher + search + user menu), main content area.
- Theme tokens matching mobile's brand color.
**Effort:** M.

### 2.3 [P0] Supabase JS client + generated TypeScript types
**Why:** every screen reads from Supabase; type-safe rows prevent runtime surprises in bulk-edit surfaces.
**Work:**
- Add `@supabase/supabase-js` dependency.
- Set up `supabase gen types typescript --project-id <ref>` script that emits `web/shared/database.types.ts`.
- Wire the script into CI so the types check stays current.
- Build a `createSupabaseServerClient()` + `createSupabaseBrowserClient()` pair following Next.js App Router idioms.
**Effort:** S.

### 2.4 [P0] Phone OTP auth flow
**Why:** the only entry point; can't do anything without it.
**Work:**
- `/login` route with phone input (E.164 normalized, same `+252` default logic as mobile per `lib/config/business_rules.dart` — needs to be ported as `defaultCountryCode` in `web/shared/config.ts`).
- OTP entry route.
- Session cookie + middleware that protects all `(dashboard)/*` routes.
- "Wrong number — sign out" affordance in user menu.
- A `useAuthCapabilities()` hook that resolves `auth_user_shop_capabilities` once per session and caches it.
**Effort:** M.

### 2.5 [P0] Capability gating components
**Why:** every action button, nav link, and bulk operation needs to consult capabilities. Per design § 8: hide nav, hide actions, disable inline edits, hide bulk selection, hide exports.
**Work:**
- `<RequireCapability code="sales.void">` server component wrapper — children render only if user has the cap on the current shop scope.
- `<CapabilityGate code="..." mode="hide|disable">` client component for action buttons.
- A `useHasCapability(code)` hook for inline conditional rendering.
- Tests: render snapshot with each role from `roles-and-permissions.md` § 6.
**Effort:** S.

### 2.6 [P0] Shop switcher in top bar
**Why:** the design's primary UX device. Every module reads from "current shop" or "all shops in scope."
**Work:**
- Dropdown listing all shops the user has membership in.
- "All shops" option visible only when user has ≥ 2 shops AND `dashboard.view_org`.
- Selection persisted in URL params (so deep links scope correctly).
- A `useCurrentShopScope()` hook returning `{type: 'shop'|'org', shopId?, orgId?}`.
**Effort:** S.

### 2.7 [P0] i18n setup + English + Somali message catalog
**Why:** every label, column header, button must be bilingual per design § 17.
**Work:**
- `next-intl` configured with `en` + `so` locales.
- Locale stored in user preference; persisted to `shop_membership.ui_locale` (new column? — see Backend Question 1 below).
- Message catalog at `web/shop-admin/messages/{en,so}.json`.
- Locale switcher in the user menu.
**Effort:** S (initial setup); ongoing per-module.

### 2.8 [P0] Design system: layout primitives + table component
**Why:** every module renders tables; we need the table component to be excellent or the whole portal feels janky.
**Work:**
- shadcn-style table primitive wrapping TanStack Table: sort, multi-column filter, column visibility toggle, row selection, pagination.
- Empty state, loading skeleton, error state — three shared variants.
- "Bulk action bar" component that sticks to the bottom when ≥ 1 row is selected.
- CSV export hook backed by the same column definitions (reuse, don't duplicate).
**Effort:** M.

### 2.9 [P0] CI + deploy pipeline
**Why:** so the portal can ship and pilot can be invited.
**Work:**
- GitHub Action: pnpm install → typecheck → lint → test → build.
- Vercel project for `web/shop-admin/`; preview deployments on PRs; production on main.
- Environment variables: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (server-only).
- Sentry wired (same DSN organization as mobile).
**Effort:** S.

### 2.10 [P0] End-to-end vertical slice: "List my organizations"
**Why:** proves the scaffolding before we replicate; first feature ships through the full pipeline.
**Work:**
- A `/login → OTP → dashboard` flow.
- Dashboard shows a list of orgs/shops the user can access.
- One real Supabase read; one capability gate; one i18n string; deployed to Vercel.
- Manual smoke test on a pilot-rep account confirms the loop closes.
**Effort:** M.

---

## 3. Phase 1 — Overview module (P0)

### 3.1 [P0] Single-shop Overview dashboard
**Target:** design § 6.1.
**What:** today / this week / this month revenue, sales count, gross margin, cash position, top 5 SKUs, low-stock count, receivables + payables.
**Backend:** mostly `get_today_summary` (exists) + a few new aggregations.
- New RPC `get_overview_summary(p_shop_id, p_window)` returning the bundle.
**Capability:** `dashboard.view`.
**Effort:** L (1 day backend RPC + 1 day frontend).

### 3.2 [P1] Multi-shop Overview (org-scope)
**Target:** design § 6.1 multi-shop view.
**What:** the same per-shop card, rendered side-by-side, sortable. A "which shop is up vs. yesterday" comparison strip.
**Backend:** the same `get_overview_summary` called per-shop, or one `get_overview_summary_org(p_org_id)` that fans out.
**Capability:** `dashboard.view_org`.
**Effort:** M.

### 3.3 [P2] Timeline chart (revenue / margin / count toggle)
**Target:** design § 6.1.
**What:** Recharts line chart at the top of Overview with period + metric toggles.
**Effort:** M.

---

## 4. Phase 2 — Sales module (P0)

### 4.1 [P0] Sales history table
**Target:** design § 6.2.
**What:** filterable / sortable / paginated table backed by `list_sales` (exists). Filters: date range, cashier, party, payment method, voided.
**Capability:** `sales.history.view`.
**Effort:** M.

### 4.2 [P0] Sale detail screen
**Target:** design § 6.2.
**What:** click row → full receipt-like view with lines, COGS-snapshot margin per line, void status, audit trail. Margin column is the unique-to-portal field.
**Backend:** `get_sale` (exists) + `list_sale_lines` (exists). Need `get_sale_audit_trail(p_shop_id, p_txn_id)` to surface void/edit history — use `list_audit_entries_for_entity` (exists from #231).
**Effort:** M.

### 4.3 [P0] Void sale (owner-only, with preview)
**Target:** design § 6.2.
**What:** owner clicks Void → modal previews the reversing entry (lines that will reverse, stock that will restore, party balance that will adjust, refund if any) → confirm → posts via `void_sale` RPC.
**Capability:** `sales.void`.
**Effort:** M.

### 4.4 [P1] Sales reports (daily / weekly / monthly)
**Target:** design § 6.2 + § 12.
**What:** period selector + cashier breakdown + category breakdown + hour-of-day. Compare to prior period side-by-side.
**Backend:** new RPC `report_sales(p_shop_id, p_from, p_to, p_group_by)`.
**Effort:** L.

### 4.5 [P2] Sales reports — cross-shop
**Target:** design § 6.2 + § 10.
**What:** revenue ranked by shop within the org.
**Effort:** S (incremental on 4.4).

### 4.6 [P2] CSV / PDF export of sales history + reports
**Target:** design § 13 + § 14.
**What:** CSV from the table directly; PDF via the edge function (see § 11).
**Effort:** M.

---

## 5. Phase 3 — Inventory module (P0–P2)

### 5.1 [P0] Products table (paginated grid, 50 rows default)
**Target:** design § 6.3.
**What:** name, category, base unit, default packaging, sale price, current stock, reorder threshold, last received, last sold. Sort + filter. Inline edit on price + threshold (capability-gated).
**Backend:** `list_shop_items_with_price` (exists) + `set_shop_item_unit_sale_price` (exists; audit-instrumented in #256).
**Capability:** `inventory.product.view` (read), `inventory.product.edit` (inline edit).
**Effort:** M.

### 5.2 [P0] Product detail screen (margin history, full packaging + alias list)
**Target:** design § 6.3.
**What:** read-heavy detail with full packaging variants, all aliases, all barcodes, sale + receive history, margin history graph.
**Backend:** `get_shop_item` (exists) + new RPC `get_shop_item_history(p_shop_id, p_shop_item_id, p_window)`.
**Effort:** L.

### 5.3 [P1] Low stock report (sortable by velocity)
**Target:** design § 6.3.
**What:** SKUs below reorder threshold, ranked by recent sales velocity ("which low-stock item will run out fastest"). CSV export for the wholesaler order.
**Backend:** `list_low_stock` (exists) + velocity join (might need extension).
**Effort:** M.

### 5.4 [P1] Bulk price change (with preview)
**Target:** design § 6.3 + § 11.
**What:** select N products → modal: set price by absolute / percent delta / formula (`last_cost * 1.25`) → preview every changed row with old/new → confirm → fires N `set_shop_item_unit_sale_price` calls with one shared `client_op_id` per item.
**Capability:** `inventory.product.bulk_edit` (likely needs to be added to the capability catalog — see Backend Question 2).
**Effort:** L.

### 5.5 [P1] Stock adjustments list + post (spreadsheet paste)
**Target:** design § 6.3 + § 7.
**What:** list of every posted adjustment (opening, correction, spoilage). Click for line drill-down. New-adjustment surface accepts spreadsheet paste; posts via `post_inventory_adjustment` (exists, audit-instrumented).
**Capability:** `inventory.adjustment.post` (owner-only).
**Effort:** L.

### 5.6 [P2] Top movers + dead stock (365-day, profit-weighted)
**Target:** design § 6.3.
**What:** extends mobile's `list_product_velocity` (exists) with longer windows + profit-weighted ranking + dead-stock value column.
**Effort:** M.

### 5.7 [P3] Catalog booklet PDF (owner-curated subset)
**Target:** design § 13.
**Effort:** M.

---

## 6. Phase 4 — People module (P0–P1)

### 6.1 [P0] Customers + Suppliers list (balance-first sort)
**Target:** design § 6.4.
**What:** balance-first sort (largest debtors at top). Filter by debt status + activity recency.
**Backend:** `list_parties` (exists).
**Capability:** `people.party.view`.
**Effort:** S.

### 6.2 [P0] Party detail (transactions + payments + running balance)
**Target:** design § 6.4.
**What:** contact info, full transaction history, running-balance graph, **allocation list (which sale each payment cleared)** — direct consumer of `list_payment_allocations` from #234.
**Backend:** `get_party_detail` (exists) + `list_payment_allocations` (exists from #234).
**Effort:** M.

### 6.3 [P0] Aging report (receivables + payables)
**Target:** design § 6.4.
**What:** age buckets 0-7 / 8-30 / 31-60 / 61+. Drill into bucket to see contributing parties. Total at bottom matches `party.receivable` / `party.payable` projections (reconciliation guarantee).
**Backend:** `v_party_aging` (exists from #234). Just SELECT-render-aggregate.
**Effort:** M.

### 6.4 [P1] Party statement export (PDF + WhatsApp share)
**Target:** design § 6.4 + § 13.
**What:** pick party + date range → PDF with all transactions + running balance → WhatsApp share link.
**Backend:** new RPC `get_party_statement(p_shop_id, p_party_id, p_from, p_to)`; PDF edge function.
**Effort:** L.

### 6.5 [P1] Edit party contact info (audit-instrumented)
**Target:** design § 6.4.
**Backend:** `update_party` (exists, audit-instrumented).
**Capability:** `people.party.edit`.
**Effort:** S.

### 6.6 [P2] Opening balance (one-time, audited)
**Target:** design § 6.4. Onboarding feature.
**Backend:** `post_opening_party_balance` (exists).
**Effort:** S.

---

## 7. Phase 5 — Money module (P1–P2)

### 7.1 [P1] Payments list + detail (allocation view)
**Target:** design § 6.5.
**What:** list of every payment in/out, same filters as Sales. Detail shows allocations (which sales/receives this payment cleared).
**Backend:** `list_payments` (exists) + `list_payment_allocations` (from #234).
**Effort:** M.

### 7.2 [P2] Manual payment re-allocation
**Target:** design § 6.5.
**What:** owner can re-allocate if implicit-allocation got it wrong. Requires extending `post_payment` to accept a `payment_id` to update — currently it only handles new payments. Needs a separate `reallocate_payment_allocations(p_shop_id, p_payment_id, p_allocations)` RPC.
**Capability:** `money.payment.reallocate` (owner-only).
**Effort:** L (backend RPC + UI).

### 7.3 [P1] Expenses list + bulk recategorize
**Target:** design § 6.5.
**Backend:** `list_expenses` (exists) + new `recategorize_expenses(p_shop_id, p_txn_ids[], p_category_id)` for the bulk operation.
**Effort:** M.

### 7.4 [P1] P&L report (period + compare-to)
**Target:** design § 6.5 + § 12.
**What:** revenue (posted sales) - COGS (line snapshots) - expenses (by category). Gross margin + net margin. Compare to prior period.
**Backend:** new RPC `report_pl(p_shop_id, p_from, p_to)`.
**Effort:** L.

### 7.5 [P3] Cash reconciliation with correction-post
**Target:** design § 6.5 + § 7.
**What:** owner enters counted cash → portal computes discrepancy → optionally posts a correction expense via `post_expense`.
**Capability:** `money.cash.reconcile` (owner-only).
**Effort:** M.

---

## 8. Phase 6 — Setup module (P1–P2)

### 8.1 [P1] Shop settings page
**Target:** design § 6.6.
**What:** currency, timezone, language, low-stock default. Audit-logged via `update_shop` (audit-instrumented in #256 — actually `update_shop_settings` doesn't exist yet; the mobile path uses `updateShopDefaults` direct PATCH; this needs to become an RPC for audit-correctness — see Backend Question 3).
**Capability:** `setup.shop.edit`.
**Effort:** M (includes the new RPC).

### 8.2 [P1] Staff list (read + revoke)
**Target:** design § 6.6 + § 16.
**What:** list users with shop/org access; per-row revoke action.
**Backend:** new RPC `list_shop_staff(p_shop_id)` and `revoke_shop_membership(p_shop_id, p_user_id)`.
**Capability:** `setup.staff.invite` (for invite); revoke under `setup.staff.assign_role`.
**Effort:** M.

### 8.3 [DONE] Staff invite (phone OR email, auto-claim on sign-in)
**Target:** design § 6.6 + § 16.
**What we shipped (#288, simpler than original P1 design):** owner enters phone OR email + role in Setup → portal calls `create_shop_invite` → invite waits in `shop_invite` table → cashier signs in normally on mobile or portal → `claim_pending_invites_for_me` RPC fires automatically and creates the `shop_membership` row. **No SMS, no deep links, no accept step.** Owner tells the cashier which phone/email to log in with via WhatsApp / in person.
**Backend:** `create_shop_invite(p_shop_id, p_phone, p_email, p_role_code)` + `claim_pending_invites_for_me()` (migration `0055_invite_email_and_autoclaim.sql`). Hook in `getCurrentShop()` (portal) + `AuthController.start` (mobile) call the claim RPC.
**Full design:** `docs/staff-onboarding.md`.
**Effort delivered:** M (saved L by skipping SMS infra and deep-link plumbing).

### 8.4 [P2] Receipt template editor (logo, header, footer)
**Target:** design § 6.6 + § 15.
**Effort:** L.

### 8.5 [P2] Branding (logo upload, business registration info)
**Effort:** M.

### 8.6 [P3] Custom roles editor (v1.x feature)
**Effort:** XL.

### 8.7 [P3] Template (re-)apply with diff view
**Target:** design § 6.6.
**Backend:** `apply_template` (exists from 0012). Diff view is the new piece.
**Effort:** L.

---

## 9. Phase 7 — Audit module (P0)

### 9.1 [P0] Audit log feed
**Target:** design § 6.7.
**What:** searchable, filterable view of `audit_log`. Filters: actor, action type, entity type, date range, shop. Each entry shows actor + before-state + after-state where safe (PII redacted per role).
**Backend:** new RPC `list_audit_log(p_shop_id, p_filters, p_cursor, p_limit)`. The existing `list_audit_entries_for_entity` from #231 is a narrower per-entity slice; this is the broader feed.
**Capability:** `audit.view`.
**Effort:** M.

### 9.2 [P1] Audit entry expansion (before/after diff)
**Target:** design § 6.7.
**What:** click an entry → before-state vs. after-state side-by-side diff. PII fields shown per the action_code's policy from 0050.
**Effort:** M.

### 9.3 [P2] Audit log CSV export
**Capability:** `audit.export` (owner-only).
**Effort:** S.

### 9.4 [P2] Org-level audit view (across all owned shops)
**Effort:** S.

---

## 10. Phase 8 — Bulk operations (cross-cutting, P1)

### 10.1 [P0] Multi-select infrastructure
Already covered in scaffolding (§ 2.8). Every table inherits.

### 10.2 [P1] Bulk action bar (sticky bottom, capability-gated actions)
**Target:** design § 11.
Already partially covered in scaffolding; each module wires its actions.

### 10.3 [P1] Preview-then-confirm dialog primitive
**Target:** design § 11 + § 19.
**What:** generic primitive used by bulk price change, bulk recategorize, bulk threshold update, etc. Shows the diff per row + per-row success/failure on commit.
**Effort:** M.

### 10.4 [P2] Spreadsheet paste primitive
**Target:** design § 11 + § 14.
**What:** paste TSV/CSV → column mapping UI → preview → commit. Used by bulk price change, opening stock, party import.
**Effort:** L.

### 10.5 [P2] Idempotent retry on partial failure
**Target:** design § 11.
**What:** each row has its own `client_op_id`; the bulk dispatcher reports per-row status; user can re-try just the failed rows.
**Effort:** M.

---

## 11. Phase 9 — Reports + PDF + CSV (P1–P2)

### 11.1 [P1] Standard report skeleton
**Target:** design § 12.
**What:** shared layout: period selector + compare-to + filter chips + chart-on-top + table-below + export buttons. Every report in modules 4, 5, 7 plugs into this.
**Effort:** M.

### 11.2 [P1] CSV export shared hook
**Target:** design § 14.
**What:** `useCsvExport(table, filters)` — respects active filters, UTF-8 with BOM for Somali support.
**Effort:** S.

### 11.3 [P2] PDF edge function (Puppeteer + templates)
**Target:** design § 13.
**What:** `supabase/functions/render-pdf/` takes a template id + payload → returns PDF bytes. Used by receipt re-print, statements, P&L exports, catalog booklet.
**Effort:** L.

### 11.4 [P2] WhatsApp share link generation
**Target:** design § 13 + § 6.4.
**What:** uploads the PDF to a public-but-unguessable Storage path; returns a `wa.me/...?text=...` link with the URL.
**Effort:** S.

### 11.5 [P2] Bulk imports — opening stock + party list
**Target:** design § 14.
**What:** onboarding flow consumes these.
**Effort:** L.

---

## 12. Phase 10 — Realtime + polish (P2)

### 12.1 [P2] Decorative realtime subscriptions on overview
**Target:** design § 9.
**What:** subscribe to `txn` insert events for current shop/org; refresh dashboard cards every few seconds.
**Effort:** M.

### 12.2 [P2] Realtime audit feed
**What:** new audit entries appear at the top of the audit feed without refresh.
**Effort:** S.

### 12.3 [P3] Global search in top bar
**Target:** design § 5.3.
**What:** unified search across products + parties + invoices + audit. Server-side fulltext on a materialized view.
**Effort:** XL.

---

## 13. Priority view — what blocks pilot

### P0 must-haves before first owner is invited to the portal:

| Item | § |
|---|---|
| Phase 0 scaffolding (everything in § 2) | 2 |
| Overview single-shop dashboard | 3.1 |
| Sales history + sale detail + void | 4.1, 4.2, 4.3 |
| Products table with inline price/threshold edit | 5.1 |
| Product detail | 5.2 |
| Customers + Suppliers list | 6.1 |
| Party detail | 6.2 |
| Aging report | 6.3 |
| Audit log feed | 9.1 |

**That's ~8 days of focused work.** It's the minimum portal that delivers real owner value: see today's sales, void a mistake, review who owes you money, audit who did what.

### P1 within first month of pilot:

| Item | § |
|---|---|
| Multi-shop Overview | 3.2 |
| Sales reports (period + breakdowns) | 4.4 |
| Low stock + bulk price change | 5.3, 5.4 |
| Stock adjustments | 5.5 |
| Party statement PDF + edit | 6.4, 6.5 |
| Payments + P&L | 7.1, 7.3, 7.4 |
| Shop settings + staff list/invite | 8.1, 8.2, 8.3 |
| Audit entry expansion | 9.2 |
| Bulk action infrastructure | 10.2, 10.3 |
| Report skeleton + CSV | 11.1, 11.2 |

**Another ~10 days.** This is portal-as-business-tool: bulk operations, recurring reports, supplier statements for collections.

### P2 before public launch:

| Item | § |
|---|---|
| Timeline charts | 3.3 |
| Cross-shop reports + CSV exports | 4.5, 4.6, 9.3, 9.4 |
| Top movers + dead stock 365d | 5.6 |
| Opening balance flow | 6.6 |
| Payment re-allocation | 7.2 |
| Cash reconciliation | 7.5 |
| Receipt template + branding | 8.4, 8.5 |
| Spreadsheet paste + idempotent retry | 10.4, 10.5 |
| PDF edge function + WhatsApp share | 11.3, 11.4 |
| Bulk imports | 11.5 |
| Realtime subscriptions | 12.1, 12.2 |

**Another ~14 days.**

### P3 v1.x / nice-to-have

§ 5.7 catalog booklet, § 8.6 custom roles, § 8.7 template diff-apply, § 12.3 global search.

---

## 14. Backend questions to answer before P0 ships

These touch the existing backend; need decisions before #265 (the first task) lands.

1. **Per-user UI locale persistence.** Where does it live? Today the mobile app stores it in `SharedPreferences`. The portal needs cross-device sync. Options: new `shop_membership.ui_locale_pref` column, or a separate `user_preference` table. Recommend the latter (cleaner for future preferences).

2. **`inventory.product.bulk_edit` capability.** The capability catalog in `0048` has `inventory.product.edit` but no separate `bulk_edit`. Bulk-edit semantics are different (preview-then-confirm contract). Should we add `inventory.product.bulk_edit` as a distinct capability or treat bulk-edit as `inventory.product.edit` × N? Recommend distinct — easier to constrain managers to single-row edits while reserving bulk to owners.

3. **Shop settings RPC.** Mobile currently PATCHes `shop` directly via `ShopApi.updateShopDefaults` — RLS allows owner writes. For audit-correctness (`setup.shop.edit` action code per 0050) we should route through `update_shop_settings(p_shop_id, p_settings jsonb)` instead. Worth doing pre-pilot (in-place edit on the mobile path) so the portal isn't inventing two patterns.

4. **PDF edge function authentication.** PDFs may need shop-scoped data; the edge function needs to authenticate the requester. Standard pattern: forward the user's JWT; edge function calls Supabase as the user. Confirm Vercel + Supabase edge function pattern.

5. **Shop invite token model.** New `shop_invite` table: `(id, shop_id, phone, role, expires_at, accepted_at, accepted_by_user_id)`. Token in the SMS deep link is the `id` (uuid). Acceptance flow on mobile checks token validity + creates `shop_membership` row. Confirm this is the right shape.

---

## 15. Out of scope for v1 (consistent with shop-admin-portal.md § 20)

These design-doc § 20 boundaries are repeated here so we don't drift:

- The portal never posts sales, receives, or payments. Period.
- The portal never manages platform-level data (templates, currencies, reference tables).
- The portal never impersonates users.
- The portal does not become the daily tool for a cashier.
- No hardware printer driver / cash drawer integration.
- No accounting-software replacement.

---

## 16. Companion docs

- `docs/shop-admin-portal.md` — the target-state design contract.
- `docs/mobile-app-alignment.md` — the precedent for this punch list format.
- `docs/roles-and-permissions.md` — capability catalog the portal consults.
- `docs/backend-schema.md` — RPC reference.
- `docs/audit-log.md` — the audit log feed surfaces this directly.
- `docs/payment-allocation.md` — the allocation view in § 6.2 reads `list_payment_allocations` from there.
