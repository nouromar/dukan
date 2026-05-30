# Dukan admin portal reference

## 1. Purpose

The Dukan admin portal is a **setup, multi-shop administration, support, and configuration console** for organization owners/admins and Dukan staff. It is not a back-office ERP and not the primary app for shopkeepers.

The mobile-first Flutter app remains the daily tool for shopkeepers and cashiers. The admin portal exists because some administration work is too detailed for mobile daily flows: organization setup, multi-shop management, users/roles, templates, translations, aliases, supplier-item mappings, opening stock import, help-channel configuration, billing, audit, and OCR correction review.

## 2. Recommended product split

| Surface | Recommended tech | Users | Main job |
|---|---|---|---|
| Shop app | Flutter | Cashier, shopkeeper, owner on the floor | Sale, Receive, Payments, Expenses, stock view, simple reports |
| Owner mobile shortcuts | Flutter | Organization owner / shop owner | Shop switcher, all-shops summary, receivables/payables, simple staff invite, Help |
| Admin portal | React / Next.js | Organization owner/admin, Dukan admin/support | Org setup, multi-shop management, users/roles, templates, onboarding, configuration, audit |
| Backend | Supabase/Postgres + Edge Functions | Both apps | Auth, RLS, data, OCR pipeline, posting procedures |

React / Next.js is a good fit for the admin portal because it will be form-heavy, table-heavy, and owner/staff-facing. Flutter remains the right choice for the mobile-first shop app.

Administration split:

- **Mobile app:** daily operations plus light owner checks.
- **Web admin portal:** organization management, multi-shop setup, users/roles, imports, template/catalog cleanup, billing, audit, and cross-shop reporting.
- **Same backend:** both clients use the same Supabase RLS and RPCs, so there is one source of truth.

## 3. Non-negotiable boundary

Dukan platform admin/support users can configure setup data, but they must not become daily operators of the shop.

Dukan platform admin/support must **not**:

- Post sales.
- Post receives.
- Post payments.
- Post expenses.
- Post stock adjustments.
- Void transactions.
- Change accounting truth directly.

Dukan platform admin/support can:

- Configure templates.
- Configure shop setup data.
- Help import opening stock.
- Add/edit products, aliases, mappings, and categories during setup.
- Review OCR failures and create aliases.
- Configure help channels and support contact details.
- View audit logs.

If a change affects money, stock, receivables, or payables, it must go through the same owner/cashier-controlled posting flow as the shop app. Organization owners may operate a shop if allowed by policy, but they still post against one selected `shop_id`, not against the organization.

## 4. User roles

### 4.1 Platform Admin

Internal Dukan role with full platform configuration permissions.

Can:

- Manage starter templates.
- Manage reference data.
- Manage supported cities/currencies/languages.
- Manage support staff accounts.
- View all shops for operational support.
- Review audit logs.

### 4.2 Support Agent

Internal Dukan role focused on onboarding and occasional support.

Can:

- Help shopkeepers through WhatsApp/email support in v1.
- Configure setup-scoped shop data.
- Help apply templates.
- Help import opening stock.
- Add aliases and fix setup mistakes.
- Review OCR failures for a supported shop.

Cannot post or void shop transactions.

### 4.3 Organization Owner/Admin

Business owner role for companies with one or more shops under one organization.

Can:

- Create and manage shops under the organization.
- Invite/remove shop users.
- Assign shop roles.
- View all-shops dashboards and per-shop reports.
- Manage org-level billing/subscription.
- Manage products, customers/suppliers, aliases, and setup defaults where permitted.
- Export data.
- Review audit logs for their organization.

This role should use the web portal for heavy administration. The mobile app may expose light shortcuts, but the daily shop app must remain uncluttered for cashiers and shopkeepers.

## 5. Functional areas

### 5.0 Organization and multi-shop management

Manage the business container above shops.

Features:

- Create organization.
- Create/edit shops under the organization.
- Invite organization owners/admins.
- Invite shop users and assign them to one or more shops.
- Set shop currency, timezone, language, and template.
- Show per-shop setup status.
- Show all-shops dashboard for owners.
- Keep billing/subscription at organization level.

Important boundaries:

- Sales, receives, payments, expenses, stock, customers, suppliers, and balances remain shop-scoped.
- The web portal can aggregate across shops, but posting always requires one selected `shop_id`.
- Cross-shop stock transfers are deferred; do not hide them as normal adjustments.

### 5.1 Template management

Create and maintain shop-kind operating templates.

Features:

- Template list: Grocery, Restaurant, Pharmacy, Hardware, Electronics, Clothing.
- Versioning.
- Draft / published status.
- Copy template version.
- Import/export JSON.
- Validate template completeness.
- Preview what will be created in a shop.

Template content:

- `catalog.json`: products, units, package/brand fields, unit conversions.
- `settings.json`: default language/currency and behavior settings.
- `quick-actions.json`: sale favorites, expense shortcuts, category order.
- `supplier-mappings.json`: supplier types, likely items, receive defaults.
- `quantity-suggestions.json`: quantity chips.
- `aliases.json`: item and party aliases.
- `ocr-mappings.json`: OCR labels and matching hints.
- `expense-categories.json`: starter expense categories.
- `dashboard.json`: default dashboard cards and report order.

The portal should show these as separate template areas, while applying them as one composed starter template.

Validation should flag:

- Duplicate codes.
- Missing Somali names.
- Missing aliases.
- Invalid unit codes.
- Products without category.
- Products without reorder threshold.
- Conflicting quick-action positions.
- Supplier mappings to missing items.

### 5.2 Product and translation management

Manage reusable catalog seed data.

Features:

- Product grid with English/Somali **product concept** names.
- Structured brand, quantity, size, and package/unit fields that are not translated as part of the product name.
- Category, base unit, default sale unit, default receive unit, allowed unit conversions, default price, reorder threshold.
- Aliases in English/Somali.
- Enable/disable products per template.
- Bulk edit.
- CSV import/export.
- Missing-translation filter.

Design goal: support staff should be able to improve the base templates without touching production shop transactions. Translation work should happen once per product concept (`Sugar` → `Sonkor`), while brand/pack-size combinations reuse that concept translation.

### 5.3 Fast-entry configuration

Configure what makes daily Sale and Receive fast.

Features:

- Sale favorites layout editor.
- Category ordering.
- Receive favorites by supplier type.
- Quantity chips per item/category.
- Default cost-entry mode: unit cost vs line total.
- Split-package configuration, e.g. `1 candy bag = 100 pieces`, set once during setup/template management.
- Default payment mode: cash/debt.
- Expense shortcut buttons.

This is the most important admin area after product templates because it directly affects shopkeeper speed.

### 5.4 Supplier-item mapping

Configure which items usually come from which supplier type or specific supplier.

Features:

- Supplier type management: grocery wholesaler, beverage supplier, dairy supplier, household supplier.
- Map likely items to supplier type.
- Optional map specific supplier to likely items.
- Usual unit.
- Usual quantity chips.
- Usual cost-entry mode.
- Sort order.

Receive flow should use this mapping to show the right items after supplier selection.

### 5.5 Shop onboarding workspace

A guided setup workspace for one shop.

Setup steps:

1. Create shop.
2. Choose template.
3. Apply template.
4. Review products.
5. Add suppliers.
6. Add customers if needed.
7. Import or enter opening stock.
8. Configure quick actions.
9. Confirm language/currency/settings.
10. Mark shop as ready.

Show setup state clearly:

`not_started -> template_applied -> opening_stock_done -> ready`

Daily shop flows should stay gated until setup reaches `ready`.

### 5.6 Opening stock import

Support staff may help preload inventory before launch.

Features:

- CSV upload.
- Manual paste grid.
- Match CSV item names to template items.
- Create missing products with confirmation.
- Validate quantities and costs.
- Preview stock movements before posting.
- Owner confirmation before final posting.

Important: opening stock should still create proper stock movements via the approved inventory adjustment/opening stock flow. The admin portal should not directly edit `current_stock`.

### 5.7 Alias and OCR correction review

Improve matching based on real usage.

Features:

- List OCR jobs with low confidence.
- Show original bono image and parsed text.
- Show suggested supplier/item matches.
- Let support add aliases after shopkeeper confirmation.
- Track correction source.
- Promote repeated corrections into template aliases later.

This area feeds the learning loop described in `templates-and-learning.md`.

### 5.8 Help channels and future support sessions

V1 does not use in-app support codes. The admin portal should configure the support contact options shown by the shop app Help icon.

V1 features:

- Configure WhatsApp support link/number.
- Configure support email.
- Configure Help icon copy in English and Somali.
- View support requests if they are later logged manually or imported.
- Keep setup/admin changes audit-logged.

Future/deferred features:

- Time-bounded in-app support sessions.
- Owner-granted support access.
- Session revocation/expiry.
- Session-specific audit tagging.

If future support sessions are added, the permission boundary is the same every time: setup-only. Support still cannot post transactions or voids.

### 5.9 Audit log

Every admin/support action should be traceable.

Show:

- Actor.
- Shop.
- Action.
- Entity type.
- Before/after values where safe.
- Timestamp.
- Support session id, if applicable.
- Reason/note for sensitive changes.

Audit is critical because support can affect shop setup even though they cannot post transactions.

### 5.10 Reference data management

Manage platform-level reference data.

Examples:

- Languages.
- Cities/regions.
- Currencies.
- Units.
- Payment methods.
- Adjustment reasons.
- Expense category defaults.
- Shop kinds.

Use reference tables, not PostgreSQL enums, for user-visible categories.

### 5.11 Reporting for operations

Internal Dukan operational reports:

- New shops by setup status.
- Shops stuck in setup.
- Template usage.
- OCR failure rate.
- Missing translation count.
- Most common unmatched aliases.
- Support sessions by agent.
- Audit exceptions.

These are platform operations reports, not shop financial reports.

## 6. Suggested navigation

```
Dashboard
Shops
  Shop detail
  Setup workspace
  Products
  Parties
  Opening stock
  Quick actions
  Audit log
Templates
  Template detail
  Products
  Aliases
  Fast-entry layout
  Supplier mappings
  Settings
OCR Review
Help Channels
Reference Data
Users & Roles
```

## 7. Security and RLS

The admin portal must use the same Supabase authorization model as the rest of Dukan:

- Do not trust a JWT shop claim for authorization.
- RLS checks `auth.uid()` plus `organization_membership`, `shop_membership`, and future support-session tables directly.
- Support permissions are setup-scoped.
- Platform admins are separate from organization/shop owners.
- All writes go through approved stored procedures or constrained tables.
- Composite foreign keys enforce same-shop integrity.

The admin UI can hide forbidden actions, but the backend must enforce the boundary.

## 8. Data model additions / emphasis

The architecture already includes:

- `template`
- `template_application`
- `organization_membership`
- `shop_membership`
- `support_session` (future hook; disabled in v1)
- `audit_log`
- `shop.setup_status`
- alias tables
- template settings and mappings
- shop learning profile tables
- precomputed shop suggestion rows

The admin portal is the main user interface for managing those platform-layer tables.

## 9. MVP scope

Build only what is needed to onboard and support pilot shops.

MVP admin portal:

- Login.
- Organization list/detail for authorized owners and platform staff.
- Shop list and shop detail.
- Create/edit shops under an organization.
- Invite users and assign organization/shop roles.
- Apply template.
- Setup checklist/status.
- Product/alias editor for a shop.
- Supplier/customer editor for setup.
- Opening stock import or grid entry.
- Quick-sale layout editor.
- Template JSON viewer/import.
- Help channel configuration.
- Audit log viewer.

Defer:

- Full visual template builder.
- Advanced analytics.
- Cross-shop ML dashboards.
- Cross-shop inventory transfers.
- Complex approval workflows.
- Public owner web portal.

## 10. Success criteria

The admin portal succeeds if:

- A grocery shop can be set up in under one hour with support help.
- Daily Sale and Receive screens are useful immediately after setup.
- Support can fix setup issues without touching transaction truth.
- Every support/admin change is auditable.
- Template improvements can be made once and reused for future shops.
- The shopkeeper app stays simple because complexity lives in setup.
