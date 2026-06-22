# Product Vision & System Overview

> **Purpose of this document.** This is the single page someone new reads to understand *what Dukan is*, *why it has three components*, *what each one is for*, and *the invariants that hold the system together as it grows*. Per-component depth lives in `mobile-app.md`, `shop-admin-portal.md`, and `system-admin-portal.md`; shared concerns (data model, RLS, OCR, UX speed contract, decisions) live in their own canonical docs.
>
> **Audience.** Engineers, designers, PMs, support staff, and platform leadership. Read once, refer back often.

---

## 1. What Dukan is

Dukan is a shop-management system for small neighbourhood shops. It replaces the **paper notebook + mental ledger** that the typical shopkeeper uses today, without making them feel like they've stepped into accounting software.

It is a **mobile-first transactional system** (the till + the back of house, in one phone) with a **web-based back office** for owners who want desk-time efficiency, and a **platform console** for the team that runs the SaaS.

The mobile app is the system's *heart*. The web portals are *lenses* — they observe and refine what mobile already records, and add capabilities that a 6-inch screen is bad at (bulk operations, wide tables, printing, cross-shop oversight).

## 2. Who we serve

| User | Where they work | Their day looks like |
|---|---|---|
| **Cashier / operator** | On the shop floor, on a mid-range Android, one-handed, often while serving a customer | Sale → Receive → Payment → Expense → close shop |
| **Shop owner (single shop)** | Same phone, sometimes a laptop in the back room | All cashier tasks, plus settings + reports + monthly review |
| **Multi-shop owner / chain** | Laptop or desktop; phone for shop visits | Compares shops, runs P&L, manages staff, sets prices, looks at aging |
| **Regional distributor / franchise HQ** *(future)* | Desktop primarily | Brand-level oversight, bulk operations across dozens of shops |
| **Platform support staff** | Desktop | Helps shops onboard, troubleshoots, edits templates, curates the global catalog |
| **Platform admin / engineer** | Desktop | Runs the SaaS — observability, billing, releases, compliance |

Primary language is **Somali**, English secondary. Pilot market is **Hargeisa**; the architecture must travel — multi-currency reference data, region-aware templates, locale-aware reports — without rework.

## 3. North-star principles

The four principles below are *load-bearing*. Every product and engineering decision must defer to them.

### 3.1 UX is the #1 success factor
The target user is **not tech-savvy**. If a feature is technically elegant but adds a tap or a configuration question to a daily flow, **the feature loses**. See `docs/ux.md` for the binding speed contract and interaction rules.

### 3.2 Decision-free daily use
Every decision is made **once, at setup** — via a one-tap operating template, or with concierge/support assistance. Daily flows (Sale, Receive, Payment, Expense) contain **zero configuration questions**. If a setting could plausibly be asked daily, it belongs in Setup.

### 3.3 Mobile is the transactional core
The cashier's phone is the **system of record**. Daily operations must always work without web. The web portals expose new *capabilities* (bulk, wide, print, cross-shop) — never new *daily-flow surfaces*. Resist the urge to mirror "Sale screen, but on web."

### 3.4 The backend is the single source of truth
All business logic — posting, void, opening balance, stock adjustment, alias/barcode mutation — lives in sanctioned Postgres RPCs. Mobile and web are *clients* of the same RPCs. No business logic in Dart or TypeScript that the other client doesn't see. This is what makes three components feel like one product.

## 4. The three components

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│   MOBILE APP (Dukan)                                             │
│   The till + back-of-shop in a phone.                            │
│   Used by:  cashier · single-shop owner                          │
│   Tech:     Flutter (Android, iOS)                               │
│   Domain:   bundled binary (Google Play, App Store)              │
│                                                                  │
│   ──────  works fully without either web portal  ──────          │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   SHOP ADMIN PORTAL                                              │
│   The owner's back office. Desk-time efficiency at scale.        │
│   Used by:  shop owner · multi-shop / chain owner · manager      │
│   Tech:     React / Next.js                                      │
│   Domain:   admin.dukan.so                                       │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   SYSTEM ADMIN PORTAL                                            │
│   Mission control for the platform team.                         │
│   Used by:  platform admin · support · engineer · finance        │
│   Tech:     React / Next.js                                      │
│   Domain:   ops.dukan.so                                         │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                ┌─────────────────────────────────┐
                │   SUPABASE (Postgres / Auth /   │
                │   Storage / Edge Functions)     │
                │   — Single source of truth      │
                │   — RLS by membership           │
                │   — Sanctioned posting RPCs     │
                └─────────────────────────────────┘
```

The three components are **deliberately separated** at the domain + deployment level. Single codebase (monorepo) for the two web portals to share components and Supabase types, but separate Next.js apps so the system-admin blast radius can never accidentally leak into the shop-admin user session.

## 5. Component responsibilities

### 5.1 Mobile app — *the till*
- **Owns:** every daily transactional flow — Sale, Receive, Payment, Expense, stock adjust, party balance, opening balance entry, history with filters, all primary reports a cashier needs.
- **Must work:** offline-first (per-shop feature flag — see `docs/offline-first-architecture.md`), one-handed, big tap targets, Somali-first, optimised for the speed contract.
- **Optimises for:** speed (3 taps from home to a posted sale), discoverability via the Today card + drawer, zero configuration during daily flows.
- **Does not own:** bulk operations across many records, CSV import/export, wide multi-column reports, multi-shop comparison, cashier-account management, platform-wide configuration.

### 5.2 Shop admin portal — *the back office*
- **Owns:** the things a desk gives you that a phone can't:
  - Bulk operations (spreadsheet-style editors, multi-select actions, CSV import/export)
  - Wide reports + custom report builder + scheduled exports
  - Cross-shop dashboards for multi-shop owners
  - Printing (receipts, labels, count sheets, end-of-day Z)
  - Staff/cashier management for the owner
  - Settings hub (branding, receipt template, tax config, integrations)
  - Audit trail viewer
- **Must work:** for both a one-shop owner and a 50-shop chain owner without re-architecting.
- **Does not own:** posting daily transactions (it can, technically, via the same RPCs — but the mobile app is the canonical surface for sale/receive/payment/expense).

### 5.3 System admin portal — *mission control*
- **Owns:** everything platform-level:
  - Tenant directory + lifecycle (impersonation, suspend, archive)
  - Template authoring + versioning + A/B testing
  - Global catalog curation + community contribution review
  - Reference data (units, currencies, payment methods, languages)
  - Customer support workspace (tickets, KB, CSAT)
  - Observability (health, usage, latency, errors per tenant)
  - Billing + monetisation (when monetised)
  - Translations workflow (en/so today; ar/sw later)
  - Feature flags, gradual rollouts, killswitches
  - Platform-wide audit log
- **Must enforce:** support staff can configure setup data; **they cannot post sales/receives/payments/voids/stock movements**. This boundary is enforced in the backend, not just the UI.
- **Does not own:** anything tenant-specific that the shop owner should be doing themselves. If the system admin portal is doing it for a shop, it's a temporary support escalation, not a feature.

## 6. The boundaries that hold the system together

These rules tell you where a new piece of functionality belongs. They have been load-tested by every "where does X go?" question.

| Question | Answer |
|---|---|
| It's done at the counter, mid-transaction. | Mobile app. |
| It's done once a week at a desk, scanning across many records. | Shop admin portal. |
| It's the same for *every* tenant (template, catalog, currency, translation). | System admin portal. |
| It's the same for *one* tenant across all their shops (chain branding, group reports). | Shop admin portal. |
| It writes a transactional row (sale, receive, payment, expense, stock movement). | Backend RPC. Mobile is canonical; shop-admin may call it for power users; system-admin **never** calls it. |
| It mutates configuration that a shop owner controls. | Shop admin portal (mobile gets read access). |
| It mutates configuration that *only the platform team* controls. | System admin portal. Shop owners cannot reach it. |
| It views or exports data. | Mobile (focused, current-shop), shop-admin (wide, cross-shop, exportable), system-admin (cross-tenant). Same RPCs, different lenses. |

If a feature doesn't fit one of these answers, the answer is **don't build it yet** — clarify the boundary first.

## 7. Integration contract

The three components communicate **only through Supabase**. They do not call each other. The contract is:

1. **All business logic lives in sanctioned Postgres RPCs.** Direct table writes from clients are forbidden for any transactional table; RLS makes them impossible, code review enforces the convention for cached projections.
2. **All reads go through RLS-gated views or RPCs.** Even system admin reads honour tenant boundaries by default; cross-tenant reads require explicit elevation, audit-logged.
3. **All clients share the same DTOs.** Field names, JSON shapes, and null semantics are identical between the Flutter app and the Next.js apps. The mobile app's `lib/api/types.dart` and the web portals' shared TypeScript types are generated from the same source.
4. **Auth is one system.** Phone OTP for mobile + shop-admin (shop users); Google SSO (or similar) for system admin (platform staff). Same `auth.users` table; different membership tables decide what you can see.
5. **Storage is one system.** Bono images, product images, exports all live in Supabase Storage with RLS-policy-gated buckets.
6. **Notifications are one system.** Whether triggered by mobile (low-stock toast), shop-admin (scheduled report), or system-admin (incident alert), they go through one notification service.

A new component (e.g., a partner integration) must follow the same contract or be rejected.

## 8. Cross-cutting concerns (invariants that survive every change)

These hold across all three components. Adding a new module without honouring them is a defect.

### 8.1 Audit by default
Every state change is recorded. Who, when, what changed, from where. The shop admin portal and system admin portal both have audit-log surfaces. Mobile contributes to the audit log; it does not need to display it.

### 8.2 Role separation
- **Cashier** — operational only (Sale, Receive, Payment, Expense, view). Can create parties (operational, not setup).
- **Shop owner** — everything within their organization.
- **Platform support** — configuration + observation across tenants. No transactional posting.
- **Platform admin** — everything system-admin can do, plus billing + lifecycle + secrets.

Enforced at the backend (`auth_can_post_shop`, `auth_is_platform_staff`, etc.); UI hides what the user can't do but never relies on hiding as the security boundary.

### 8.3 Impersonation is a primitive
Support viewing a tenant's data is read-only by default, audit-logged, time-boxed, and explicitly elevated for any write. The shop admin portal renders a "you are viewing as <support staff name>" banner during impersonation so the owner can audit.

### 8.4 i18n is not an afterthought
- Reference data: every user-visible code has translations in a `name_translations` jsonb.
- App strings: ARB on mobile, ICU on web — same JSON-encodable plural/select rules.
- New languages added at the system-admin portal; no code changes required to roll out a translation update.
- Somali + English are *both* first-class.

### 8.5 Templates over configuration
Anything that varies by "kind of shop" (grocery vs. pharmacy vs. hardware) lives in an operating template, not in hand-tuned per-shop settings. Templates are authored in the system admin portal; applied to shops at setup; version-controlled and diffable.

### 8.6 Numbers are correct
- Money + quantity use `numeric`, never floats.
- Posted transactions are immutable; corrections are reversing entries.
- COGS is snapshotted on each sale line.
- Cached projections (`shop_item.current_stock`, `party.receivable`, etc.) are written only by posting RPCs, with a nightly reconciliation view.
- Composite FKs on `shop_id` enforce tenant integrity (RLS is a second line of defence, not the first).

### 8.7 Speed contract (from `docs/ux.md`)
- Sale, 1 item, cash: ≤ 5 s, 3 taps from home.
- Sale, 5 items, cash: ≤ 20 s.
- Receive, 10-line bono manual: ≤ 90 s.
- App cold start to home: ≤ 3 s.
- Any tap → visible response: ≤ 100 ms.

These are non-negotiable on mobile. The web portals have their own targets (sub-second page loads, instant filter response on cached datasets), but the speed contract above is the one that gates pilot release.

## 9. Evolution principles

How the system grows without rewriting itself.

### 9.1 Stable top-level navigation
Each portal has ~10 top-level modules chosen to be *load-bearing for years*. New features find a home **inside** a module; you should rarely need an 11th module. (See `mobile-app.md`, `shop-admin-portal.md`, `system-admin-portal.md` for the locked module lists per portal.)

### 9.2 Backend evolves first, clients catch up
- New capability → new RPC + migration.
- Migration order is the source of truth. Numbered files, never edited once applied (pre-pilot exception is in `docs/decisions.md`).
- Clients update at their own pace. A mobile release behind by a week does not break a feature delivered first to the web portal.

### 9.3 Inert hooks for future capabilities
- `location_id` on `stock_movement` (multi-location v2).
- `client_op_id` on `transaction` + `payment` (idempotency, offline retry).
- Composite FKs ready for cross-shop transfers.
- Schema is `numeric`-typed so multi-currency consolidation later doesn't require migration of money rows.

### 9.4 Templates absorb growth
A new market (e.g., pharmacies in Mogadishu) doesn't require code — it requires a template. Reference data, quick actions, OCR mappings, expense categories, suggested aliases, dashboard defaults all live in template packs.

### 9.5 Web portals scale by adding to modules, not adding modules
- Shop admin: bulk operations get richer over time *inside* Catalog, Inventory, People, etc.
- System admin: tenancy module grows from "directory" to "health scores" to "churn prediction" without restructuring.

### 9.6 Mobile stays the transactional core forever
We will be tempted, repeatedly, to add a "fast sale" surface to the shop admin portal. **Resist.** The cashier is at the counter. The owner is at the desk. Mixing those audiences destroys both UXs.

## 10. What this document does *not* cover

This is the spine. Depth lives in companion documents:

| Question | Doc |
|---|---|
| Mobile app — screens, flows, interaction rules | `docs/mobile-app.md` (target) + `docs/mobile-app-alignment.md` (punch list) |
| Shop admin portal — modules, IA, screens | `docs/shop-admin-portal.md` |
| System admin portal — modules, IA, screens | `docs/system-admin-portal.md` (supersedes `docs/admin-portal.md`) |
| Roles, capabilities, scope, role catalog | `docs/roles-and-permissions.md` |
| Backend data model, RLS, triggers, RPCs | `docs/backend-schema.md` + `docs/data-model-v2.md` |
| OCR pipeline, edge functions, storage policy | `docs/architecture.md` |
| UX speed contract, interaction rules, anti-patterns | `docs/ux.md` |
| Operating templates, learning profiles | `docs/templates-and-learning.md` |
| Per-product decisions and their rationale | `docs/decisions.md` |
| Phased roadmap, scope, pilot scope | `docs/plan.md` |

## 11. Change log

| Date | Change | Author |
|---|---|---|
| 2026-06-11 | Initial draft establishing the three-component architecture and the invariants. | — |
