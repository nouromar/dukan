# System Admin Portal — Design

> **Target state**, not as-built. This document is the design contract for the **system admin portal**: the Dukan-internal mission control where platform staff configure templates, onboard organisations, run support sessions, manage reference data, and observe platform health. As of writing, an earlier version of this document existed as `docs/admin-portal.md` (now superseded). The current-state alignment lives in `docs/system-admin-portal-alignment.md` once that artifact is created.
>
> This portal is **not for shop owners**. Owners use `docs/shop-admin-portal.md`. The two portals share zero UI; they share the backend and some operational vocabulary, but they are fundamentally separate products for separate audiences.
>
> Companion documents:
> - `docs/product-vision.md` — why all three components exist.
> - `docs/shop-admin-portal.md` — the customer-facing back-office portal (different audience).
> - `docs/mobile-app.md` — the customer-facing transactional app (different audience).
> - `docs/roles-and-permissions.md` — capability vocabulary; platform-tier roles are defined there.
> - `docs/templates-and-learning.md` — template structure that this portal manages.
> - `docs/backend-schema.md` — shared backend.

---

## 1. Purpose

The system admin portal is the **internal operational surface for Dukan, the company**. It is how Dukan staff:

- Onboard new organisations and shops.
- Run pilots and support customers.
- Maintain the shared catalog of starter templates.
- Curate reference data (currencies, languages, units, expense categories).
- Investigate customer issues via time-bounded impersonation.
- Review OCR failures and feed corrections back into the templates.
- Observe platform health (active shops, posting failure rate, OCR confidence trends).
- Hold platform-tier accountability: the audit log of every staff action.

The single design tension this portal navigates: **Dukan staff need power to help customers without becoming able to corrupt customer accounting truth.** The portal solves this by making *setup configuration* fully editable by staff while making *transactional posting* impossible from staff sessions, full stop. (See § 3 — the non-negotiable boundary.)

## 2. Who uses it

### 2.1 Platform admin

Internal Dukan engineering / product staff. Full platform configuration: starter templates, reference data, supported regions, feature flags. Can grant other staff the support agent role. Read access across all tenants for operational support. Cannot post transactions on any shop.

### 2.2 Support agent

Internal Dukan customer-support staff. Onboarding-focused: walk new shops through setup, apply templates, fix configuration mistakes, review OCR failures. Can impersonate a tenant user with explicit reason and time bound (see § 9). Cannot post transactions. Cannot edit the starter templates that affect *other* tenants (only the platform admin role can publish a new template version).

### 2.3 Engineering on-call

Subset of platform admin. Same UI role as platform admin but the on-call rotation is operationally distinct: they get paged, they triage, they may use impersonation in incident response. The portal does not have a separate "on-call" tab — they use the existing surfaces with elevated context.

### 2.4 Non-personas

- **Organisation owner** — their portal is `docs/shop-admin-portal.md`.
- **Shop owner** — same.
- **Cashier** — uses the mobile app.

The system admin portal is **internal-only**. It is not deployed at a customer-facing URL. It sits behind an internal SSO (Google Workspace) plus device attestation, not Supabase customer auth.

## 3. The non-negotiable boundary

**Dukan platform staff can configure setup data, but they must not become daily operators of the shop.**

Platform staff **cannot**:

- Post sales.
- Post receives.
- Post payments.
- Post expenses.
- Post stock adjustments.
- Void transactions.
- Edit posted transaction rows.
- Manipulate `party.receivable` / `party.payable` directly.
- Manipulate `shop_item.current_stock` directly.
- Manipulate `shop_item.avg_cost` directly.
- Generate cash flow events.

Platform staff **can**:

- Configure starter templates.
- Apply templates to a shop (during onboarding, with the owner's consent).
- Manage reference data (currencies, units, languages).
- Configure shop *setup* data (aliases, fast-entry layout, supplier mappings, quick actions) — these don't move money.
- Help import opening stock — but via the same `post_inventory_adjustment` RPC, *as the owner* via impersonation, not as themselves. The opening-stock row is owner-authored.
- Review OCR failures and suggest aliases (the owner accepts).
- Configure help channels and support contact details.
- Grant other staff roles.
- View audit logs across tenants.
- Impersonate a tenant user with explicit reason + time bound (§ 9).

This boundary is enforced in **three** layers:

1. **Platform staff have no `*.post` capability.** The role catalog in `docs/roles-and-permissions.md` § 6 explicitly excludes posting capabilities from platform tiers.
2. **Sanctioned posting RPCs check capability.** A staff JWT calling `post_sale` fails capability check, returns a "platform staff cannot post transactions" error, audit-logged.
3. **The portal UI has no "post a sale" button.** Defence in depth — but UI is the weakest layer.

If a change affects money, stock, receivables, or payables, it must go through the owner/cashier-controlled posting flow on mobile or (per `docs/shop-admin-portal.md` § 7) the two carved-out portal exceptions. Platform staff do not have a third path.

## 4. Operating principles

The system admin portal honours principles different from the customer-facing surfaces, because the audience is different:

1. **Boring is good.** Internal tools should look like internal tools. No marketing polish. Dense tables, generous information density, keyboard-first navigation.
2. **Every action is auditable.** No exceptions. Every read of customer data, every write to a template, every impersonation session start and end — all logged.
3. **Defence in depth on the boundary.** The non-negotiable boundary (§ 3) is enforced at backend, RPC, and UI layers. Each enforces independently.
4. **Time-bound everything sensitive.** Impersonation sessions auto-expire. High-risk capabilities require recent re-authentication.
5. **Operator clarity over user friendliness.** A platform admin debugging an incident at 2 AM cares about exact identifiers, raw payloads, and timestamps — not animated transitions.
6. **No customer data leaves the platform.** Exports from this portal go to internal observability tools, not to the platform admin's laptop. (See § 16.)

## 5. Information architecture

Persistent left rail with these sections:

1. **Dashboard** — operational overview.
2. **Organisations** — list, detail, lifecycle management.
3. **Shops** — list, detail, setup workspace.
4. **Templates** — starter template management.
5. **Reference data** — platform-level catalogs.
6. **OCR review** — bono parsing failures and corrections.
7. **Users** — platform staff management.
8. **Impersonation** — active sessions, history.
9. **Audit** — full-platform audit log.
10. **Observability** — health metrics, SLOs.

The current scope is **always platform-wide**. There is no "current shop" or "current org" concept in the global navigation; scope is selected per module.

---

## 6. Module specs

Each module: **What it does**, **Who can use it** (platform admin vs support agent), **Audit shape** (what gets logged when the module is used).

### 6.1 Dashboard

#### What it does

Landing page showing platform health: active organisations, active shops, signup funnel (new orgs by week, shops in `not_started` → `template_applied` → `opening_stock_done` → `ready`), posting volume, OCR confidence trend, support session count, error rate, capability rejection rate.

#### Who

Both roles see it. Different cards prioritised: platform admin sees system health up top, support agent sees support workload up top.

#### Audit shape

Read of the dashboard is logged at session level (not per-card). Drill-downs into per-tenant data are logged per-tenant.

---

### 6.2 Organisations

#### What it does

- **Organisation list** — sortable by created date, shop count, last activity, health flag.
- **Organisation detail** — owner contact info, shops under the org, billing status (when billing ships), org-level audit log, support session history for the org.
- **Lifecycle** — create new org (platform admin only), suspend (incident response, owner consent), archive (after cancellation, retention-policy-aware).

Onboarding flow at the org level: create org → invite first owner → owner creates first shop → support agent walks owner through shop setup workspace (§ 6.3).

#### Who

- Platform admin: full lifecycle.
- Support agent: read + invite, no suspend/archive.

#### Audit shape

Org creation, owner invite, suspension, archival — each logged with actor, before-state (where applicable), after-state, free-text reason.

---

### 6.3 Shops

#### What it does

- **Shop list** — filterable by setup status (`not_started` / `template_applied` / `opening_stock_done` / `ready`), org, region, last activity.
- **Shop detail** — current setup status, template applied, owner contact, recent activity summary (read-only — staff doesn't drill into transactions), audit log scoped to this shop.
- **Setup workspace** — guided onboarding for one shop. Steps: choose template → apply → review products → add suppliers/customers → import or enter opening stock → configure quick actions → confirm language/currency → mark ready.
- **Re-apply template** — idempotent re-application; diff view before posting.
- **Setup status reset** — incident response only, platform admin only, audit-logged with reason.

The setup workspace is the most-used module for support agents. Walking a Hargeisa shopkeeper through their first day is mostly clicking through this flow on a video call.

#### Who

- Platform admin: everything including reset.
- Support agent: setup workspace + read; cannot reset.

#### Audit shape

Setup step transitions logged with actor + step + before-state + after-state. Template application logged with template version. Opening stock import logged as a sequence of `post_inventory_adjustment` invocations under impersonation (§ 9).

---

### 6.4 Templates

#### What it does

Manage the starter templates per shop kind (grocery, restaurant, pharmacy, hardware, etc.).

- **Template list** with version + status (draft / published).
- **Template detail** with the eight independent packs documented in `docs/templates-and-learning.md`:
  - `catalog.json` — products, units, package fields, unit conversions.
  - `settings.json` — default language, currency, behaviours.
  - `quick-actions.json` — sale favourites, expense shortcuts, category order.
  - `supplier-mappings.json` — supplier types, likely items, receive defaults.
  - `quantity-suggestions.json` — quantity chips.
  - `aliases.json` — item and party aliases.
  - `ocr-mappings.json` — OCR labels and matching hints.
  - `expense-categories.json` — starter expense categories.
  - `dashboard.json` — default dashboard cards and report order.
- **Editor per pack** — JSON-aware editor with schema validation.
- **Version operations** — draft → publish; copy version to new draft; rollback to previous published version.
- **Import / export JSON** — for offline review or git-tracked authoring.
- **Validation** — flag duplicates, missing Somali names, missing aliases, invalid unit codes, products without category, products without reorder threshold, conflicting quick-action positions, supplier mappings to missing items.
- **Preview applied** — show what the template will create when applied to a hypothetical shop.

#### Who

- Platform admin: edit + publish.
- Support agent: read only.

#### Audit shape

Every save of a template draft logged. Every publish logged with before-version + after-version. Every apply-to-shop logged elsewhere (§ 6.3).

---

### 6.5 Reference data

#### What it does

Manage the platform-level reference catalogs that all shops draw from:

- Languages (English, Somali, future Arabic).
- Currencies (USD, SLSH, future others).
- Cities / regions.
- Units (kg, g, l, ml, piece, dozen, etc.).
- Unit conversions (1 kg = 1000 g).
- Payment methods (cash, mobile money, bank transfer).
- Adjustment reasons (opening, correction, spoilage — closed set, expansion requires schema change).
- Default expense categories.
- Shop kinds (grocery, restaurant, etc.).
- Transaction types (sale, receive, expense — closed set).

These live in reference tables (per `docs/architecture.md` § 4), not PG enums, so they can be edited without migration.

#### Who

- Platform admin: edit.
- Support agent: read only.

#### Audit shape

Every reference data write is logged. Reference data deletions are denied at the schema level for anything referenced by a tenant row (FK enforced); attempts logged with the reason.

---

### 6.6 OCR review

#### What it does

Bono image parsing produces structured data with a per-line confidence score. Low-confidence parses land in OCR review for staff (with owner consent) to correct.

- **Failure list** — every OCR job with confidence below threshold (default 0.85), filterable by shop, age, supplier.
- **Job detail** — original bono image, parsed text, the suggested supplier/item matches, the per-line confidence.
- **Correct** — staff suggest an alias (e.g., "Tropi 25kg" → existing SKU "Tropi Sugar 25kg bag"). The suggestion goes into a queue for the owner to accept; once accepted, the alias is added to the shop's learning profile.
- **Promote to template** — if the same correction is suggested across many shops, platform admin can promote it to a template alias so future shops benefit.

#### Who

- Support agent: review + suggest.
- Platform admin: promote to template.

#### Audit shape

Suggestion logged per shop. Owner acceptance logged on the tenant side. Promotion to template logged at platform level with the source-shop count.

---

### 6.7 Users (platform staff)

#### What it does

Manage Dukan-internal staff accounts.

- **Staff list** with role (platform admin / support agent / read-only auditor), last sign-in, last impersonation.
- **Grant role** — platform admin only; logged with effective date and reason.
- **Revoke role** — platform admin only; logged.
- **Force-revoke active sessions** — for offboarding or compromise response.

Internal SSO (Google Workspace) handles authentication; this module manages *roles* mapped onto the SSO identity.

#### Who

Platform admin only. (A support agent inviting another support agent is a security smell.)

#### Audit shape

Every grant, revoke, and forced-revoke logged with actor + subject + reason. Logged to the platform audit log *and* mirrored to internal security tooling.

---

### 6.8 Impersonation

#### What it does

Time-bound, reason-required, fully-audited "act as" mode.

- **Start session** — pick the tenant user to impersonate; enter a free-text reason; pick a duration (max 60 min default, max 4 hours hard cap); confirm.
- **Session UI** — once a session is active, the portal shows a persistent banner: "Impersonating <user name> for <reason>. Ends at <time>. [End session]"
- **Active session list** — see every active impersonation across all staff. Force-end any session (platform admin only).
- **Session history** — every prior session with actor, subject, reason, start, end, list of actions taken.

When an impersonation session is active, the impersonated user's mobile app shows the banner described in `docs/mobile-app.md` § 13: "Dukan staff <name> is helping you. Reason: <free text>. Session ends at <time>."

Impersonation can do most things the impersonated user could do — *except* posting transactions. The non-negotiable boundary (§ 3) is checked at the backend regardless of the impersonation layer.

#### Who

- Support agent: start sessions for users in tenants assigned to them.
- Platform admin: start sessions for any user; force-end any session.

#### Audit shape

Every session: actor, subject, reason, start time, end time, every action attempted (including denied attempts), every action posted under impersonation. The platform audit log is the source of truth; tenant audit logs mirror entries for actions affecting their data so the tenant can see "staff did X at time Y."

---

### 6.9 Audit

#### What it does

Full-platform searchable audit log. Filters: actor, action type, entity type, scope (platform / org / shop), date range, free-text search of reason field.

- **Live tail** — for incident response, scrolling tail of recent actions.
- **Saved searches** — common queries (e.g., "all impersonations this week," "all template publishes").
- **Export to observability** — push filtered slices to internal logging tooling for cross-correlation. No raw export to a staff member's laptop.

#### Who

- Both roles read.
- Export to observability is platform admin only.

#### Audit shape

The audit log is itself audit-logged: every query and every filter is logged, so we can see "who looked at what when." This catches staff fishing through customer data without justification.

---

### 6.10 Observability

#### What it does

Operational dashboards independent of customer-facing data:

- Posting RPC latency p50 / p95 / p99.
- Posting RPC error rate.
- OCR pipeline confidence histogram.
- Realtime channel connection count.
- Sign-in success rate.
- Capability rejection rate (catches misconfigured roles).
- Active shop count by region.
- Setup funnel conversion (`not_started` → `ready`).
- SLO burn rate.

#### Who

Both roles read. Platform admin can configure alerts and SLO targets.

#### Audit shape

Reads logged at session level. Alert config changes logged per change.

---

## 7. Three scope tiers in the UI

The portal's UI surfaces all three scope tiers from `docs/roles-and-permissions.md` § 5:

1. **Platform scope** — templates, reference data, staff users, platform observability, platform-wide audit. Most modules.
2. **Organisation scope** — when drilling into an org, the UI shows org-scoped capabilities and surfaces shop list, org audit log, billing.
3. **Shop scope** — when drilling into a shop, the UI shows shop-scoped capabilities and surfaces the setup workspace, shop audit log, OCR jobs.

The current scope is **explicit in the URL** and the breadcrumb. There is no ambient "currently selected shop" affordance — scope is a property of the page, not the session.

## 8. Capability gating mechanics

Same model as the other surfaces; mechanisms:

- **Nav rail items hidden** when the staff role lacks the capability.
- **Action buttons hidden** when the staff role lacks write capability.
- **Re-authentication required** for high-risk actions (publish template, suspend org, force-end impersonation). The re-auth prompt validates the SSO token within the last 5 minutes; if older, prompts for fresh sign-in.
- **Soft denial** for in-window actions: the portal shows the action but greys it out with the reason ("Requires platform admin role").
- **Hard denial at backend**: even if the UI offers an action by bug, the RPC rejects and logs the rejection.

## 9. Impersonation in detail

Impersonation is the highest-risk capability in the portal. Treatment:

- **Reason required** — free-text, ≥ 20 characters. "Helping with setup" is OK; empty is not.
- **Time bound enforced** — default 60 min; max 4 hours; auto-end on timeout; the impersonation JWT is short-lived and refreshes against the staff session, so an expired staff session ends the impersonation.
- **Visible to the subject** — mobile banner (`docs/mobile-app.md` § 13) shows the impersonation in progress. The subject can do nothing to suppress the banner.
- **Force-end** — platform admin can force-end any active session; logged.
- **No posting** — capability checks at the RPC layer reject any `*.post` attempt under impersonation regardless of the subject's role. The exceptions (`post_inventory_adjustment` for opening stock; `post_expense` for cash reconciliation) are explicitly *not* allowed under impersonation either; the owner posts those themselves.
- **Recorded session log** — every action attempted is logged, including failures. Replayable in the audit module.
- **Subject consent** — for sensitive operations (changing the shop's currency, changing the shop's primary language, applying a new template version), the subject must accept a confirmation on their own device before the action commits. Impersonation does not bypass owner consent for high-impact changes.

The non-negotiable boundary (§ 3) is enforced under impersonation by the same mechanism as outside it: the staff's *underlying* capability set, not the subject's, gates `*.post` capabilities.

## 10. Realtime for incident response

The portal subscribes to the same Supabase realtime channels for incident-response value:

- The audit tail (§ 6.9) is realtime by default.
- The active impersonation list (§ 6.8) is realtime.
- The observability dashboards (§ 6.10) refresh on a sub-minute cadence.
- The OCR review queue is realtime as new failures land.

Realtime is **functional** here, not decorative. An on-call engineer watching a deploy depends on the realtime audit tail.

## 11. Authentication

- **Internal SSO** (Google Workspace at `dukan.<corp-domain>`) — not Supabase customer auth.
- **Device attestation** — staff devices enrolled; unenrolled devices cannot reach the portal even with valid SSO.
- **MFA required** — enforced by the SSO; portal does not implement its own.
- **Session length** — 8 hours; re-auth required for high-risk actions (§ 8).
- **No remember-me, no long-lived sessions, no API keys** — the portal is interactive-staff-only. Programmatic access to the same operations exists separately as scripts under engineering ownership.

## 12. Authorisation

- Platform-tier roles defined in `docs/roles-and-permissions.md` § 6 (`platform_admin`, `support_agent`, future `read_only_auditor`).
- Capabilities resolved at session start; refreshed on re-auth.
- RLS enforced at backend regardless of UI gating.
- All writes through sanctioned RPCs.
- The non-negotiable boundary (§ 3) checked at the RPC layer for every `*.post` capability.

## 13. Audit log requirements

Every action surfaces a row in `audit_log` with:

- Actor (staff user id + SSO email).
- Subject (org id and/or shop id, when scoped).
- Action type.
- Entity type and id.
- Before-state and after-state (JSONB; PII fields redacted by policy).
- Timestamp.
- Reason (free-text, required for high-risk; optional for low-risk).
- Impersonation session id, when applicable.
- Source IP and device id from device attestation.

Audit entries are append-only. There is no UI affordance to edit or delete an entry. Retention is governed by an internal policy (currently: indefinite for security audit, 7 years for transactional audit).

## 14. Internationalisation

The system admin portal is **English-only**. Justification: the audience is internal Dukan staff; the cost of bilingual support for a 20-person staff is not justified vs. the cost of getting customer-facing translations excellent.

Customer data displayed in the portal (product names, party names, shop names) renders in the customer's chosen language with no translation. Staff see "Sonkor" if the customer named the product that.

## 15. Online-only, intentional

The portal is **online-only**. No offline mode, no write queue, no local cache beyond browser standard. Justification: same as the shop admin portal — sessions are not time-critical the way mobile cashier transactions are.

## 16. No exports of customer data to staff laptops

This is a security-policy rule that shapes UI:

- **No "download CSV" button on customer data lists.** Every list view is read-only on the portal.
- **Exports for legitimate operational use go to internal observability tooling**, never to a staff member's local filesystem.
- **Screenshots are not technically prevented** (impossible to prevent on a general-purpose OS) but the AUP requires staff to not take screenshots of customer data outside an active incident.
- **Customer data shown in the portal is the minimum necessary**: product names yes, prices no (unless in scope of an active support task). Cashier names yes, phone numbers redacted by default with a "reveal" capability gated to support-agent-or-above and audit-logged on reveal.

## 17. What the system admin portal deliberately does NOT do

Permanent design boundaries. These are not v1 omissions.

1. **Post transactions on a customer's behalf.** Ever. Even with consent. Customer posts, staff configures.
2. **Edit posted transactions.** Same — corrections go through the customer's reversing-entry flow.
3. **Bypass customer audit logs.** Staff actions affecting a tenant appear in that tenant's audit log too.
4. **Run as a customer's daily back office.** That's the shop admin portal.
5. **Hold customer-data exports for staff laptops** (§ 16).
6. **Allow long-lived impersonation.** Hard 4-hour cap.
7. **Allow impersonation without a written reason.**
8. **Allow staff to grant themselves capabilities they don't have.** Role assignments require platform admin; platform admin is a small fixed set.
9. **Replace incident response tools** (PagerDuty, Datadog, etc.). The portal *consumes* those tools' signals via the observability module; it does not become them.
10. **Replace billing platforms.** When billing ships, it integrates with a third-party billing platform (Stripe, etc.); the portal surfaces billing state, not billing logic.

## 18. Mobile / shop admin portal handoffs (inverse view)

Looking from the customer-facing surfaces, which customer-surface flows have a system admin counterpart:

| Customer surface | System admin counterpart | Why platform-side is different |
|---|---|---|
| Mobile auth (phone OTP) | Internal SSO + device attestation | Different audience, different threat model. |
| Mobile shop list | Shops module § 6.3 | Platform-wide vs. user's accessible shops. |
| Mobile Settings → owner-only items | Reference data § 6.5 + Templates § 6.4 | Platform-wide vs. per-shop overrides. |
| Mobile Receive → OCR results | OCR review § 6.6 | Per-shop view vs. platform-wide review queue. |
| Shop admin People (statements) | (none — staff doesn't access financial statements) | Boundary § 3. |
| Shop admin Sales reports | (none — staff doesn't access posted transactions) | Boundary § 3. |
| Shop admin Setup → Templates | Templates module § 6.4 | Apply vs. author. |
| Shop admin Audit | Audit module § 6.9 | One-shop vs. cross-tenant. |

## 19. Tech contract

- **Frontend:** React / Next.js (App Router). Server components for dashboards; client components for interactive editors.
- **Authentication:** Internal SSO (Google Workspace); not Supabase customer auth.
- **Authorisation:** Platform-tier capabilities resolved at session start.
- **Realtime:** Supabase realtime channels for audit tail, impersonation list, OCR queue.
- **Deployment:** Internal-only deployment behind corporate VPN + device attestation. Not deployed at a public URL.
- **Repo location:** New top-level directory `system-admin-web/` alongside `app/dukan/` and the future `admin-web/`. Strictly separate from the customer-facing portal — different audit treatment, different auth, different deployment, different threat model.
- **No shared UI code with `shop-admin-web/`.** Shared types and API client may be extracted into a shared package later; UI shells are intentionally separate.

## 20. Protective rules

Three rules that catch the recurring failure modes:

1. **The non-negotiable boundary (§ 3) is sacred.** Any proposal to add a posting capability to a platform role requires a `docs/decisions.md` entry, security review, and explicit approval. No exceptions inferred from "but it would be convenient."

2. **Impersonation is the last resort, not the first.** If a task can be done by walking the owner through a video call, that's preferred. If it can be done by improving the template so future shops don't hit the problem, that's preferred. Impersonation is for the cases where neither alternative is feasible.

3. **Customer-data leakage is a fireable offence.** The portal makes the right thing easy (no download buttons, redacted PII, audit on reveal). The wrong thing (screenshot, copy-paste into Slack) is impossible to technically prevent — it's prevented by hiring well and operational discipline.

---

## 21. Companion documents

- `docs/product-vision.md` — why three components.
- `docs/shop-admin-portal.md` — the customer-facing back-office portal.
- `docs/mobile-app.md` — the customer-facing transactional app.
- `docs/roles-and-permissions.md` — capability vocabulary; platform-tier roles.
- `docs/templates-and-learning.md` — template structure managed here.
- `docs/architecture.md` — data model, RLS, OCR pipeline.
- `docs/backend-schema.md` — shared backend.

---

## 22. Replaces `docs/admin-portal.md`

This document supersedes the earlier `docs/admin-portal.md`. The earlier doc mixed platform-staff content with org-owner content; the three-component architecture (`docs/product-vision.md`) split that into two portals with separate audiences. The old document will be archived once `docs/system-admin-portal-alignment.md` is drafted.
