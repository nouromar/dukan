# Roles & Permissions

> **Purpose.** Canonical reference for the capability-based access-control model that all three Dukan interfaces (mobile app, shop admin portal, system admin portal) share. Defines the primitives (capabilities, roles, assignments, scopes), the lifecycle, and the standard role bundles we ship.
>
> **Audience.** Engineers writing backend RPCs, designers naming buttons, support staff troubleshooting "why can't I see X?", platform admins composing custom roles for paying customers.
>
> **Sister documents.** `docs/product-vision.md` establishes the three-component architecture and the four north-star principles; this doc is the shared concern those components defer to for *who can do what*. Concrete enforcement code lives in `docs/backend-schema.md`.

---

## 1. Core concepts

Four primitives, each a row in the database.

| Concept | Definition | Example |
|---|---|---|
| **Capability** | A single, atomic action the platform recognises. Always a verb, always granular. | `can_post_sale`, `can_void_sale`, `can_invite_cashier`, `can_impersonate_tenant` |
| **Role** | A named bundle of capabilities. Composable; clonable. | `Cashier` = { `can_post_sale`, `can_post_receive`, `can_post_payment`, `can_post_expense`, `can_create_party`, `can_view_today` } |
| **Assignment** | The grant of a role (or a single capability) to a user at a scope. | "Asha → Cashier @ Shop A" |
| **Scope** | The boundary the assignment is good for. One of three tiers: platform / organization / shop. | `shop:abc-123`, `org:def-456`, `platform` |

A user's **effective capabilities** are the union of every capability granted by every assignment they hold. There is no negative grant — roles always *add* permissions, never subtract. If you want a user to lose a capability, you remove (or reduce) one of their assignments.

## 2. Why capability-based, not role-only?

A pure role-enum model (e.g., `role IN ('cashier', 'manager', 'owner')`) is faster to ship on day one and harder to maintain on day 365. Every new requirement — "we want a weekend cashier who can sell but not refund", "this auditor needs read-only access for two weeks", "give Sales the ability to apply discounts but not voids" — becomes either (a) a new hardcoded role, growing the enum forever, or (b) a code change with a migration.

The capability model **separates the change surface**: adding a new capability is a backend concern (one new check function, one new policy); composing it into a role is a configuration concern (config, possibly self-serve for paying orgs). Over a multi-year platform, the configuration surface absorbs almost every "can we just…" request without engineering work.

The tradeoff is real but small: more tables, slightly more careful authorization checks. We pay that cost intentionally.

## 3. Scope: the three tiers

Every assignment lives at exactly one of these scopes. The scopes are hierarchical: a capability at a higher scope is honoured at all narrower scopes for the same user, but only if the role itself was authored for that scope.

```
┌─────────────────────────────────────────────────────────────────┐
│   PLATFORM scope                                                │
│   — capabilities that cross tenants                             │
│   — e.g., `can_impersonate_tenant`, `can_publish_template`,     │
│     `can_view_global_observability`                             │
│   — held by: platform admin, platform engineer, support staff   │
├─────────────────────────────────────────────────────────────────┤
│   ORGANIZATION scope                                            │
│   — capabilities that apply across all shops in an org          │
│   — e.g., `can_invite_org_member`, `can_view_org_pnl`,          │
│     `can_manage_billing`, `can_define_custom_role`              │
│   — held by: org owner, org admin, org accountant, marketing    │
├─────────────────────────────────────────────────────────────────┤
│   SHOP scope                                                    │
│   — capabilities that apply at a single shop                    │
│   — e.g., `can_post_sale`, `can_void_sale`, `can_edit_price`,   │
│     `can_adjust_stock`, `can_apply_discount`                    │
│   — held by: cashier, shop manager, shop owner                  │
└─────────────────────────────────────────────────────────────────┘
```

A user at org-scope `Org Accountant` automatically gains org-wide read of every shop in that org. They do *not* gain shop-scope capabilities like `can_post_sale` unless they also hold a shop-scope assignment that grants it.

**Last owner protection** — every org and every shop must always have at least one assignment with `can_grant_role` at that scope. The backend refuses revocations that would leave a scope ownerless.

## 4. The capability registry

Capabilities are seeded as `reference` data, in the same spirit as `transaction_type` or `payment_method` — versioned, locale-translatable for UI labels, but not user-extensible. Adding a new capability is a backend migration.

Naming convention: **`can_<verb>_<object>`**, all lowercase, underscores.

```
can_post_sale
can_post_receive
can_post_payment
can_post_expense
can_void_sale
can_adjust_stock
can_edit_price
can_create_party
can_edit_party
can_invite_cashier
can_invite_org_member
can_view_pnl
can_view_audit_log
can_impersonate_tenant
can_publish_template
can_manage_billing
...
```

Every capability has:

| Field | Purpose |
|---|---|
| `code` | The string identifier (`can_post_sale`). Stable forever. |
| `label` + `label_translations` | User-facing string ("Post a sale" / "Diiwaan iib") for the role editor. |
| `valid_scopes` | Which tiers (platform / org / shop) can grant this capability. `can_post_sale` is shop-only; `can_impersonate_tenant` is platform-only. |
| `risk_level` | `low` / `medium` / `high`. Drives UI warnings + audit-log retention. `can_impersonate_tenant` is `high`. |
| `is_active` | Soft-deprecation flag. Old capabilities don't disappear; they stop being assignable. |
| `category` | For grouping in the role editor: `pos`, `inventory`, `finance`, `people`, `setup`, `platform`, `support`. |

## 5. Standard roles (the ones we ship)

These are the platform-shipped role bundles. They live in `reference` data and ship with new orgs at provisioning time. Orgs can clone them; they cannot edit them in place (clone-and-modify is the upgrade-safe pattern).

### Shop-scope roles

| Role | Capabilities (representative) | Shipped in |
|---|---|---|
| `Cashier` | `can_post_sale`, `can_post_receive`, `can_post_payment`, `can_post_expense`, `can_create_party`, `can_view_today` | v1 |
| `Manager` | Cashier + `can_void_sale_same_shift`, `can_apply_small_correction`, `can_view_shift_summary`, `can_approve_cashier_request` | v1.x |
| `Shop owner` | Manager + `can_void_sale_7d`, `can_post_opening_balance`, `can_post_inventory_adjustment`, `can_edit_price`, `can_edit_party`, `can_invite_cashier`, `can_view_pnl`, `can_view_audit_log`, `can_edit_shop_settings` | v1 |
| `Stock clerk` | `can_post_receive`, `can_post_inventory_adjustment`, `can_view_stock`, `can_view_today` | v2 |
| `Shop viewer` | Read-only: `can_view_today`, `can_view_pnl`, `can_view_audit_log` | v2 |

### Org-scope roles

| Role | Capabilities (representative) | Shipped in |
|---|---|---|
| `Org owner` | Everything in the org. `can_invite_org_member`, `can_manage_billing`, `can_manage_shops`, `can_define_custom_role`, `can_grant_role`, `can_view_org_pnl`, `can_view_audit_log`, `can_export_data` | v1 |
| `Org admin` | Org owner minus `can_manage_billing`, minus `can_transfer_ownership` | v2 |
| `Org accountant` | Read-only across the org: `can_view_org_pnl`, `can_view_aging`, `can_view_audit_log`, `can_export_data` | v1.x |
| `Org auditor` | Org accountant + audit-log-level read (immutable, redaction-aware) | v2 |
| `Marketing manager` | Customer/segment management, promotions, outbound messaging. No transactional access. | future |

### Platform-scope roles

| Role | Capabilities (representative) | Shipped in |
|---|---|---|
| `Platform admin` | Everything. `can_impersonate_tenant_write`, `can_manage_secrets`, `can_publish_template`, `can_manage_feature_flag`, `can_manage_billing_plan`, `can_grant_platform_role` | v1 |
| `Platform engineer` | Observability + flags + migrations: `can_view_global_observability`, `can_manage_feature_flag`, `can_run_migration`, `can_manage_killswitch`. No PII, no billing, no impersonation. | v1.x |
| `Support — Tier 1` | `can_impersonate_tenant_read`, `can_manage_ticket`, `can_author_kb`. Read-only impersonation, audit-logged. | v1 |
| `Support — Tier 2` | Tier 1 + `can_impersonate_tenant_write` (time-boxed, ticket-bound), `can_edit_tenant_setup_data` | v1.x |
| `Customer Success` | `can_view_tenant_health`, `can_send_campaign`, `can_view_aggregated_analytics`. No per-transaction PII. | v2 |
| `Finance` | `can_manage_billing_plan`, `can_view_invoices`, `can_issue_refund`, `can_view_revenue_dashboard` | v1.x |
| `Catalog curator` | `can_edit_global_catalog`, `can_review_alias_contribution`. No tenant data. | v2 |
| `Localization manager` | `can_edit_translation`, `can_publish_translation`, `can_review_translation_contribution` | v2 |
| `Compliance / DPO` | `can_view_global_audit_log`, `can_export_tenant_data`, `can_approve_data_deletion` | v2 |
| `Partner manager` | Partner program management, marketplace, commissions | future |

## 6. Custom roles (clone-and-modify)

Org Owners (or anyone holding `can_define_custom_role`) can create roles tailored to their business — but only by **cloning** a platform-shipped role as the starting point. The clone is a new row owned by the org, with the org's chosen name and capability set.

Why clone-and-modify, not edit-in-place:

1. **Upgrade-safe.** When the platform ships a new capability (e.g., `can_apply_discount_with_approval`), it can be auto-added to the shipped `Cashier` role for everyone, without colliding with a customer's hand-tuned version.
2. **Audit trail.** Cloning records "this role derives from Cashier as of date X" so support can reason about it.
3. **Restore button.** The customer can always reset their clone back to the shipped baseline.

Custom roles live at org scope or shop scope, never platform scope. Platform-scope roles are platform-controlled.

## 7. Direct user grants

Sometimes a role is overkill. "Asha needs `can_view_audit_log` for two weeks while we trial it" doesn't justify a whole new role.

Direct grants are a sibling primitive: `(user_id, capability, scope, expires_at?)`. The effective-capability calculation unions them with role-derived capabilities exactly the same way. Direct grants are:

- **First-class in the model**, second-class in the UI — most flows go through roles, direct grants live in a "fine-grained access" panel for advanced admins.
- **Time-boxable by default.** UI nudges the admin to set an `expires_at`.
- **Audit-logged with a reason** (free-text or template, e.g., "trialling audit-log access for finance team").

## 8. Implied capabilities (capability composition)

Some capabilities imply others. `can_void_sale` is meaningless without `can_view_sale`. Modeling these implications keeps roles correct and the UI honest.

| Mechanism | Detail |
|---|---|
| `capability_implies(parent, child)` table | Reference-data: each parent implies a set of children. |
| Effective-capability calc | When computing what a user can do, walk the implication graph and add all transitive children. |
| Role editor UI | When an admin picks "Void sale", the UI auto-checks "View sale" and shows it as "(implied)" so they understand. |

Implications are platform-controlled. Customers cannot author them — they're part of the capability's semantics.

## 9. Enforcement — backend first

The same rules apply to every interface; they're enforced once, in the backend, then mirrored in each UI.

### 9.1 Authorization functions
Each capability has a check function: `auth_user_has_capability(p_capability text, p_scope_type text, p_scope_id uuid)`. Implementation walks role assignments + direct grants + capability implications, returns boolean.

For the common case, we keep the per-flow helpers that already exist (`auth_can_post_shop`, `auth_can_access_shop`, `auth_is_platform_staff`) — they wrap `auth_user_has_capability` for the most-common capability + scope combination. Inside an RPC, prefer the helper if one exists; fall back to the generic function otherwise.

### 9.2 RPC-level checks
Every posting RPC begins with a capability check that throws if missing. This is the canonical security boundary. RLS is the second line of defence (catches anything that bypasses the RPC by accident).

### 9.3 RLS
RLS policies use the same capability checks. Reading a sale row requires `can_view_sale` at the relevant shop scope. RLS is *gating data the user wasn't supposed to see*; RPC checks are *gating mutations the user wasn't supposed to make*.

### 9.4 UI
Each interface receives the user's effective-capability set at session start (and refreshes it on a role change). Buttons hide; menu items hide; entire routes redirect. **UI never relies on hiding as security** — the backend still rejects unauthorized calls.

## 10. Audit, elevation, and high-risk flows

High-risk capabilities (impersonation, data export, refund, void, role-grant) follow stricter rules.

| Mechanism | Applies to | What it does |
|---|---|---|
| **Audit log** | Every state change | Records `(user, capability, target, scope, timestamp, reason?, source IP, session id)`. |
| **Reason required** | `risk_level = high` capabilities | UI requires a free-text reason before the action fires. The reason is stored on the audit row. |
| **Time-boxed elevation** | Impersonate-write, role-grant, data-export | Default 1-hour window; UI prompts to confirm + extend; backend records `elevation_start` + `elevation_end`. |
| **Out-of-band confirmation** | `can_transfer_ownership`, `can_manage_secrets`, anything billing-material | Confirmation email or 2FA challenge before the write commits. |
| **Watch list** | All `risk_level = high` actions | Pushed to the system-admin Observability dashboard in real time so platform staff see them as they happen. |

## 11. Lifecycle

| Event | Behaviour |
|---|---|
| **Invite** | Whoever can grant the role at the scope can invite. Invitee gets a phone OTP / email link; on acceptance the assignment becomes active. |
| **Revoke** | Same person (or anyone superseding them) can revoke. Capability disappears immediately on next request. |
| **Expiry** | Assignment carries optional `expires_at`. Backend ignores expired assignments. Owner can renew before expiry without re-onboarding. |
| **Suspend** | Soft-disable an assignment without deleting it (e.g., cashier on leave). Reversible with one click. |
| **Last-owner protection** | The backend refuses to revoke / expire the last assignment that grants `can_grant_role` at any scope. Every org and shop always has at least one. |
| **Transfer ownership** | A dedicated flow that atomically adds a new owner and removes the old one. Requires out-of-band confirmation. |
| **User deletion** | When a user is deleted (GDPR or otherwise), assignments cascade-soft-delete; audit log entries do *not* (they redact the user's PII but preserve the action). |

## 12. Schema sketch

```
capability                ( code pk, label, label_translations,
                            valid_scopes text[],   -- {'platform','org','shop'}
                            risk_level, category, is_active )

capability_implies        ( parent_code fk, child_code fk )

role                      ( id pk, scope_kind, owner_org_id null,
                            code text, name text, name_translations,
                            is_platform_shipped boolean,
                            derived_from_role_id null,
                            is_active )

role_capability           ( role_id fk, capability_code fk )

role_assignment           ( user_id fk, role_id fk,
                            scope_kind, scope_id,
                            granted_by, granted_at, expires_at,
                            suspended_at )

direct_capability_grant   ( user_id fk, capability_code fk,
                            scope_kind, scope_id,
                            granted_by, granted_at, expires_at,
                            reason text )

capability_audit          ( user_id, capability_code, scope_kind, scope_id,
                            target_id, target_kind, action_at,
                            reason, source_ip, session_id, elevation_id null )

elevation                 ( id pk, user_id, capability_code,
                            scope_kind, scope_id,
                            granted_by, granted_at, expires_at,
                            reason, ticket_id null )
```

Standard rules:
- Every table has `created_by` / `created_at` / `updated_at` like every other v2 table.
- Capability `code` and role `code` are stable strings; ids are UUIDs but the codes are the contract.
- `is_platform_shipped` roles cannot be edited or deleted; they can only be cloned (which sets `derived_from_role_id` on the new row).

## 13. v1 minimum vs long-term

To honour the existing pre-pilot shape, the v1 implementation is the **minimum that's correct** and grows from there.

### v1 (now)
- Hardcoded role checks (`auth_can_post_shop`, etc.) — already in the codebase.
- Two shop roles: `Cashier`, `Shop owner`.
- One platform role: `Platform admin`.
- Direct grants table exists but unused in the UI.

### v1.x (next 1–2 releases)
- Data-driven capability registry + role/assignment tables; refactor existing helpers to call `auth_user_has_capability` under the hood.
- Ship `Manager` (shop), `Org accountant` (org), `Support — Tier 2` (platform).
- Org owner can clone shipped roles; basic role editor in shop admin portal.

### v2
- Full custom-role builder for org owners (clone-and-modify with capability picker).
- Audit-log UI in both web portals.
- Elevation + reason-required flow for high-risk capabilities.
- Last-owner protection enforced backend-wide.

### Long term
- Self-serve custom-role marketplace (a chain shares its "Weekend cashier" role with peer organizations).
- Capability-graph visualization in the role editor (shows implications).
- Per-org capability subscriptions (a paid tier might unlock advanced capabilities like `can_manage_loyalty`).

## 14. Naming conventions

| Object | Convention | Example |
|---|---|---|
| Capability `code` | `can_<verb>_<object>` | `can_post_sale` |
| Capability label (en) | Imperative, plain language | "Post a sale" |
| Role `code` (platform-shipped) | `kebab-case` | `shop-owner`, `org-accountant` |
| Role `name` (display) | Title case, plain language | "Shop owner" |
| Custom role `code` | Auto-generated from name, org-prefixed | `acme-weekend-cashier` |

Keep capability codes **stable forever** — they're the contract surface. Renaming `can_post_sale` to `can_record_sale` is a breaking change that requires data migration and client update.

## 15. The non-goals

Worth being explicit about what this model does *not* attempt.

- **No negative capabilities.** Roles only grant. If you want someone to lose a capability, remove (or downgrade) one of their assignments. Adding `cannot_void_sale` as a sibling of `can_void_sale` would create grant-vs-deny ambiguity that has burned every RBAC system that tried it.
- **No row-level capabilities.** "Asha can void her own sales but not Bashir's" is *not* a capability — that's row-level filtering, handled inside the void RPC's business logic, not in the permission model.
- **No time-of-day capabilities** at this level. "Cashiers can only sell during shop hours" is a business rule enforced inside `post_sale`, not in the capability model. (We may build a *schedule* concept later that nullifies an assignment outside its window; that's a separate primitive.)
- **No nested roles.** Roles do not inherit from other roles. Composition happens via capability bundles, not role-of-roles. This keeps the effective-capability calculation tractable.

## 16. Companion documents

- `docs/product-vision.md` — the three-component architecture this model serves.
- `docs/backend-schema.md` — concrete migrations + RLS policies.
- `docs/mobile-app.md` *(forthcoming)* — how mobile renders capability-gated UI.
- `docs/shop-admin-portal.md` *(forthcoming)* — role editor + invitation flow + audit-log UI.
- `docs/system-admin-portal.md` *(forthcoming)* — impersonation, elevation, platform-role administration.
- `docs/decisions.md` — record the capability-vs-role-enum decision here when v1.x lands.

## 17. Change log

| Date | Change | Author |
|---|---|---|
| 2026-06-11 | Initial draft establishing the capability/role/assignment/scope model and the standard role catalog. | — |
