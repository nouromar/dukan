# Dukan UX screen map

## 1. Purpose

This document maps the complete Dukan user experience across the shop app and admin portal. It does not replace `ux.md`; it expands it into a screen-by-screen reference.

The goal is to prevent accidental clutter, inconsistent flows, and hidden complexity. Every screen must support the north-star: **fast, simple daily use for shopkeepers who are not tech-savvy**.

## 2. Screen priority levels

| Level | Screens | Design depth now |
|---|---|---|
| A | Home, Sale, Receive, Customer selection for debt, Supplier selection, Payment, Expense | Full layout, tap flow, bottom sheets, empty/error states, speed target |
| B | Products, Customers, Suppliers, Reports, Settings, Setup checklist | Clear structure and main actions; detailed polish after Level A |
| C | Admin portal, Template editor, OCR review, advanced reports | Information architecture and key workflows only for now |

Level A screens must be prototyped and timed before backend wiring.

## 3. Navigation model

Primary navigation lives on the **Home** screen as large task buttons. Avoid hamburger navigation for primary tasks.

Primary tasks:

- Sale
- Receive
- Payment
- Expense
- Reports
- Setup / Settings

Secondary management screens are reachable from Settings or from contextual `+ New` actions:

- Products
- Customers
- Suppliers
- Expense categories
- Shop setup checklist

## 4. Shared screen rules

### 4.1 Daily screen layout

Daily screens should use three zones:

1. **Top context bar:** title, back, language toggle, optional small search.
2. **Main action area:** the thing the user is doing now.
3. **Bottom action/summary strip:** total, selected customer/supplier, primary save button.

Do not fill the middle with rarely used settings.

### 4.2 Bottom sheets

Use bottom sheets for focused selection/search:

- Supplier picker.
- Customer picker.
- Item picker.
- Expense category picker.
- Quantity picker.
- Price/cost override.
- Partial payment.
- Date override.

Rules:

- One bottom sheet at a time. No modal-on-modal.
- Sheet has one job.
- Search field at top only when needed.
- Recents/favorites first.
- `+ New` is always visible but not dominant.
- Selecting an item closes the sheet and returns to the main task.

### 4.2.1 Quantity picker

The quantity picker is more than a stepper. It should show:

- **Common chips** from the template or item config: `1 bag`, `2 bags`, `5 bags`, `10 bags`.
- **Learned chips** from the shop's history: the quantities and units this shop actually uses most.
- **Stepper** for small changes: `-  2 bags  +`.
- **Typed quantity** for unusual amounts.
- **Unit label** so the user never guesses whether they are entering bags, kg, bottles, or cartons.
- **Package chips** when configured, e.g. `1 bag`, even if the stock base unit is `piece`.

Source priority is precomputed into ready suggestions where practical:

1. Shop setup/manual values.
2. Shop-learned frequent quantities and units.
3. Supplier-item mapping, when receiving from a supplier.
4. Template quantity suggestions.
5. Item-level safe defaults.

The picker reads the top active suggestion by rank. If no safe suggestion exists, keep the safest default: quantity `1` in the item's default unit.

For split packages, the picker hides conversion math. Example: Candy ABC is stocked in pieces but received by bag (`1 bag = 100 pieces`). Receive shows bag chips; Sale defaults to piece chips and may include `1 bag` only if whole-bag sale is allowed.

### 4.3 Long-press power actions

Normal tap does the common action. Long-press opens power options:

- Item quantity > 1.
- Price override.
- Delete line.
- Partial payment.
- Manual allocation.
- Add note.

Do not make power actions visible as permanent buttons on daily screens.

### 4.4 Empty and error states

- First-time empty state teaches with 2-3 short steps.
- Warnings should be non-blocking when possible.
- Errors use plain action language.
- Offline saves go into a visible queue with `Saved on phone` wording.

## 5. Level A screens

## 5.1 Home

### Purpose

Get the shopkeeper to the next task in one tap.

### Layout

```
┌─────────────────────────────────────────┐
│ Dukan                      EN | SO      │
│ Today: Sales $124  Debt $18            │
├─────────────────────────────────────────┤
│ [  SALE  ]        [ RECEIVE ]           │
│ [ PAYMENT ]       [ EXPENSE ]           │
├─────────────────────────────────────────┤
│ Needs attention                         │
│ • 3 customers owe money                 │
│ • 5 low-stock items                     │
└─────────────────────────────────────────┘
```

### Rules

- Sale and Receive are visually largest.
- Show only 2-3 attention cards.
- No chart clutter on Home.
- If setup is incomplete, replace daily buttons with a simple setup checklist.

### Speed target

- Sale starts in 1 tap.
- Receive starts in 1 tap.

## 5.2 Sale

### Purpose

Record a cash or debt sale faster than handwriting.

### Layout

```
┌─────────────────────────────────────────┐
│ ← Sale                       EN | SO    │
│ Search item...                          │
├─────────────────────────────────────────┤
│ Favorites                               │
│ [Rice] [Sugar] [Oil] [Tea]              │
│ [Milk] [Water] [Soap] [Pasta]           │
│                                         │
│ Ready suggestions                       │
├─────────────────────────────────────────┤
│ Cart: 3 items              $7.50        │
│ Cash ✓   Debt              [ SAVE ]     │
└─────────────────────────────────────────┘
```

### Main flow: cash sale

1. Tap Sale from Home.
2. Tap item card. Item is added with quantity 1.
3. Repeat as needed.
4. Tap Save.
5. Show toast: `Saved. Undo?`

### Debt sale flow

1. Build sale normally.
2. Tap `Debt`.
3. Customer bottom sheet opens.
4. Select customer or create new customer.
5. Main Sale screen shows chip: `Debt: Ahmed - owes $12.50`.
6. Tap Save.

### Rules

- Customer is hidden for cash sales.
- Customer is required only after choosing Debt.
- Quantity defaults to 1.
- Long-press item opens quantity/price sheet.
- Cart strip is the review; no separate review screen.
- Price override is hidden behind long-press.

### Speed target

- 1-item cash sale: <= 5 seconds / 3 taps from Home.
- 5-item cash sale: <= 20 seconds / 7 taps from Home.
- Existing-customer debt sale: <= 12 seconds / 5 taps.

## 5.3 Customer selection bottom sheet

### Purpose

Choose the customer only when needed, especially for debt sales.

### Opens from

- Sale: when user taps Debt.
- Payment: when recording customer payment.
- Reports: when filtering receivables.

### Layout

```
┌─────────────────────────────────────────┐
│ Choose customer                         │
│ Search name or phone                    │
├─────────────────────────────────────────┤
│ Recent debt customers                   │
│ Ahmed        owes $12.50                │
│ Asha         owes $8.00                 │
│ Hassan       owes $31.25                │
├─────────────────────────────────────────┤
│ All customers                           │
│ ...                                     │
├─────────────────────────────────────────┤
│ + New customer                          │
└─────────────────────────────────────────┘
```

### Ranking

1. Customers with current debt.
2. Recent debt customers.
3. Frequent customers.
4. Search/alias matches.

### `+ New customer`

Minimal fields:

- Name.
- Phone optional but encouraged.

After save, the customer is selected automatically and the sheet closes.

### Rules

- No full customer form in the Sale screen.
- Show debt amount so the user recognizes the person.
- Do not show address, notes, or history in the picker.

## 5.4 Receive

### Purpose

Record stock received from supplier using a paper bono, with minimal typing.

### Flow

1. Tap Receive from Home.
2. Supplier bottom sheet opens.
3. Pick supplier.
4. Receive screen opens with supplier context.
5. Add bono photo or tap `I don't have a bono`.
6. Add lines.
7. Save Receive.

### Layout after supplier selection

```
┌─────────────────────────────────────────┐
│ ← Receive from Xawaash       EN | SO    │
│ [ Add bono photo ]                     │
├─────────────────────────────────────────┤
│ Item: Search or choose likely item      │
│ Qty: [  ]  Unit: bag                    │
│ Cost: [  ] per bag  ⇄ line total        │
│ [ + ADD LINE ]                          │
├─────────────────────────────────────────┤
│ Lines: 4                 Total $218.00  │
│ Credit ✓   Paid now       [ SAVE ]      │
└─────────────────────────────────────────┘
```

### Rules

- Supplier first, not camera first.
- Bono photo is strongly suggested but not required.
- After supplier selection, likely items for that supplier appear first.
- `Repeat last bono` appears if previous receive exists for this supplier.
- Default receive payment = Credit / Pay Later.
- Cost-entry mode defaults from template/learning: per-unit or line-total.
- If a receive unit is a package, conversion to base unit is already configured in setup; the user enters `10 bags`, not `1000 pieces`.
- Bono total mismatch is a warning, not a blocker.

### Speed target

- Manual 10-line receive: <= 90 seconds.
- OCR-assisted receive later: <= 30 seconds after draft appears.

## 5.5 Supplier selection bottom sheet

### Purpose

Choose supplier without cluttering the Receive screen.

### Opens from

- Receive start.
- Supplier payment.
- Receive report filter.

### Layout

```
┌─────────────────────────────────────────┐
│ Choose supplier                         │
│ Search supplier                         │
├─────────────────────────────────────────┤
│ Recent suppliers                        │
│ Xawaash Trading     owe $420            │
│ Hodan Wholesale     owe $95             │
├─────────────────────────────────────────┤
│ Supplier types                          │
│ Grocery  Beverage  Dairy  Household     │
├─────────────────────────────────────────┤
│ + New supplier                          │
└─────────────────────────────────────────┘
```

### Ranking

1. Recent suppliers.
2. Suppliers with unpaid payable.
3. Supplier-item mapping relevant to last receive.
4. Search/alias matches.

### `+ New supplier`

Minimal fields:

- Name.
- Phone optional.
- Supplier type optional, suggested from template.

After save, supplier is selected automatically and the sheet closes.

### Rules

- Do not ask for supplier address/tax/bank fields in v1.
- Do not show full payable history in the picker.
- The picker returns one supplier and closes.

## 5.6 Item picker bottom sheet

### Purpose

Find or create an item quickly without forcing category navigation.

### Opens from

- Sale search.
- Receive line item field.
- Product mapping in setup.

### Layout

```
┌─────────────────────────────────────────┐
│ Choose item                             │
│ Search Somali or English                │
├─────────────────────────────────────────┤
│ Suggested                               │
│ Rice 25kg      bag      $26.00          │
│ Sugar 1kg      kg       $1.20           │
├─────────────────────────────────────────┤
│ + New item                              │
└─────────────────────────────────────────┘
```

### Ranking by context

- Sale: favorites, frequent sale items, recent items.
- Receive: selected supplier's likely items, recent received items, OCR candidates.
- Setup: template items first.

### `+ New item`

Minimal fields:

- Name.
- Unit.
- Optional sale price.

In Receive, if a cost is already typed, use it as last cost.

## 5.7 Payment

### Purpose

Record money received from customer or paid to supplier.

### Entry point

Home -> Payment.

### First screen

```
┌─────────────────────────────────────────┐
│ Payment                      EN | SO    │
├─────────────────────────────────────────┤
│ [ Customer paid me ]                    │
│ [ I paid supplier ]                     │
└─────────────────────────────────────────┘
```

### Customer payment flow

1. Tap `Customer paid me`.
2. Customer bottom sheet opens.
3. Select customer.
4. Amount screen appears with balance visible.
5. Type amount.
6. Save.

### Supplier payment flow

1. Tap `I paid supplier`.
2. Supplier bottom sheet opens.
3. Select supplier.
4. Amount screen appears with payable visible.
5. Type amount.
6. Save.

### Amount layout

```
┌─────────────────────────────────────────┐
│ Ahmed owes $12.50                       │
├─────────────────────────────────────────┤
│ Amount paid                             │
│ [        10.00 ]                        │
│ [ Pay full $12.50 ]                     │
├─────────────────────────────────────────┤
│ Oldest debts first ✓       [ SAVE ]     │
└─────────────────────────────────────────┘
```

### Rules

- Default allocation = oldest debt first.
- Manual allocation is long-press/power action.
- Do not expose accounting words like allocation or receivable.

### Speed target

- Existing customer/supplier payment: <= 10 seconds / 4 taps.

## 5.8 Expense

### Purpose

Record small shop expenses quickly.

### Layout

```
┌─────────────────────────────────────────┐
│ Expense                      EN | SO    │
├─────────────────────────────────────────┤
│ What was it for?                        │
│ [ Rent ] [ Electricity ] [ Salary ]     │
│ [ Water ] [ Transport ]   [ Other ]     │
├─────────────────────────────────────────┤
│ Amount                                  │
│ [        0.00 ]                         │
│ Optional photo                          │
├─────────────────────────────────────────┤
│ Today ✓                    [ SAVE ]     │
└─────────────────────────────────────────┘
```

### Rules

- Expense categories are chips, not dropdowns.
- Date defaults to today; date override in bottom sheet.
- Photo is optional.
- Notes hidden behind `Add note`.

### Speed target

- Expense: <= 10 seconds / 4 taps.

## 6. Level B screens

## 6.1 Products

Purpose: manage item setup, not daily selling.

Main actions:

- Search products.
- Add product.
- Edit name, unit, sale price, reorder threshold.
- Add aliases.
- Disable product.

Rules:

- Product list is not the sale screen.
- Stock correction goes through adjustment/opening stock flow, not direct stock edit.
- Advanced fields hidden under `More`.

## 6.2 Customers

Purpose: view customers and debts.

Main actions:

- Search customer.
- Add customer.
- View amount owed.
- Record payment.
- View sales history.

Rules:

- Customer profile stays simple: name, phone, balance, history.
- Do not show ledger/accounting terminology.

## 6.3 Suppliers

Purpose: view suppliers and payables.

Main actions:

- Search supplier.
- Add supplier.
- View amount owed.
- Record supplier payment.
- View receive history.
- Manage aliases.

Rules:

- Supplier-item mapping is setup/admin function, not daily Receive clutter.

## 6.4 Reports

Purpose: answer owner questions without spreadsheet complexity.

MVP reports:

- Today summary.
- Customer debts.
- Supplier payables.
- Sales list.
- Receives list.
- Low stock.
- Profit by day/month/custom date.

Rules:

- Reports use plain labels.
- Filters open in bottom sheet.
- Default date = today or this month.
- Export is owner-only.

## 6.5 Settings

Purpose: setup and rare configuration.

Sections:

- Shop profile.
- Language.
- Products.
- Customers.
- Suppliers.
- Expense categories.
- Users.
- Active devices / sessions.
- Help icon: WhatsApp chat and email support.
- Export data.

Rules:

- No settings needed during Sale/Receive.
- Use setup checklist for incomplete shops.
- Active devices must support "logout other devices" for lost-phone and suspicious-login cases.

## 6.6 Setup checklist

Purpose: make a new shop ready without confusion.

Steps:

1. Apply template.
2. Review products.
3. Add suppliers.
4. Add customers if needed.
5. Enter opening stock.
6. Check quick sale buttons.
7. Confirm settings.
8. Mark ready.

Rules:

- Each step has one primary button.
- Support can help only through setup-scoped session.
- Daily flows unlock when setup status is `ready`.

## 7. Level C screens

## 7.1 Admin portal

Defined in `admin-portal.md`.

For now, only the information architecture and security boundary are locked:

- React / Next.js setup/support console.
- Template management.
- Shop onboarding workspace.
- Opening stock import.
- Alias/OCR review.
- Help channels / support contact configuration.
- Audit log.

Never post shop transactions from the admin portal.

## 7.2 Template editor

Purpose: maintain shop operating profiles.

Must support:

- Products.
- Translations.
- Aliases.
- Settings.
- Quick actions.
- Supplier-item mappings.
- Quantity chips.
- Entry preferences.

This is staff-facing, not shopkeeper-facing.

## 7.3 OCR review

Purpose: improve matching and templates.

Must support:

- View bono image.
- View parsed OCR text.
- Accept/correct supplier and item matches.
- Add aliases.
- Promote common corrections into templates.

OCR review improves suggestions; it never posts transactions.

## 8. Bottom-sheet inventory

| Bottom sheet | Trigger | Returns |
|---|---|---|
| Customer picker | Debt sale, customer payment, report filter | `customer_id` |
| Supplier picker | Receive, supplier payment, report filter | `supplier_id` |
| Item picker | Sale search, Receive line | `item_id` |
| Quantity picker | Long-press item/line | quantity |
| Price override | Long-press sale line | unit price |
| Cost entry mode | Receive line toggle | unit cost or line total |
| Partial payment | Long-press Cash/Debt | paid amount |
| Date picker | Expense/payment/report date | date/range |
| Filter sheet | Reports/lists | filter values |
| Add note | Any transaction | note text |

## 9. Screen states required for every screen

Each screen must define:

- Empty state.
- Loading state, only if unavoidable.
- Offline state.
- Saved state.
- Warning state (e.g., a background post failed and the cart was restored).
- Hard error state.

(An in-app "Undo" state was originally listed here. It was dropped in
favor of post-server Void via Sales history; see `ux.md` § 4 rule 8 and
`decisions.md` Q12.)

Do not ship a screen that only works in the happy path.

## 10. Prototype acceptance checklist

Before backend wiring, the Flutter prototype must demonstrate:

- Sale cash, 1 item, <= 5 seconds.
- Sale debt with existing customer, <= 12 seconds.
- Receive with existing supplier and 10 lines, <= 90 seconds.
- Customer and supplier bottom sheets feel uncluttered.
- User can complete each Level A flow without reading long instructions.
- Somali labels fit on buttons.
- Tap targets are >= 56dp.
- No daily screen contains settings or configuration questions.
- No modal-on-modal behavior.

If the test user hesitates more than 2 seconds, the screen is not obvious enough.
