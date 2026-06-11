# Adding items — the six flows

> **Status:** Locked design (2026-06-06). Source of truth for the Add-new-item
> + Add-packaging UX rewrite that ships in the next iteration.
> Pairs with `data-model-v2.md` §5 (shop overlay) and §8.5 (scenario coverage).

The cashier reaches a new-item or new-packaging surface in six combinations:

|   | Sale screen | Receive screen |
|---|---|---|
| **New item — not in global catalog** | 1A | 1B |
| **Item in global catalog — not yet activated** | 2A | 2B |
| **Activated item — add a new packaging** | 3A | 3B |

All six end with the cart line / receive line carrying exactly one
`shop_item_unit_id`. Posting RPCs and reports never need to know how
the item got there.

This document spells out each flow at the level of taps, RPC calls, and
DB state — plus the cross-cutting mechanics that are shared.

---

## 1. Cross-cutting mechanics

### 1.1 Multi-packaging atomic create

The new-item create RPC accepts an *optional* sold packaging in
addition to the base:

```
create_shop_item(
  p_shop_id,
  p_name,
  p_language_code,
  p_base_unit_code,                -- always required
  p_sale_price       default null,  -- price for the picked packaging
  p_category_id      default null,
  -- new in this iteration:
  p_sold_unit_code     default null,
  p_sold_conversion    default null,
  p_default_side       default 'sale'   -- 'sale' (1A) | 'receive' (1B)
) returns ( shop_item_id, default_shop_item_unit_id )
```

Behavior:

| Case | What the cashier picked | Rows inserted |
|---|---|---|
| Sold in base | "Loose, by kg" (1A) / "by bottle" (1B) | 1 row: base, conversion=1, priced. Both default flags or just one depending on side. |
| Sold packaged | "25-kg bag" (1A) / "12-bottle carton" (1B) | 2 rows: base (conversion=1, unpriced) and the sold packaging (conversion>1, priced). Default flags: see §1.4. |

Atomicity matters — the partial unique index requires exactly one
`conversion=1` row per shop_item, so a split insert that fails mid-way
would leave the item in an invalid state.

### 1.2 Category-aware suggestions

`suggest_item_packagings` and the new `suggest_new_item_options`:

- **Primary list:** only same-category source items.
- **Fallback:** if primary returns < 3 rows, fold in cross-category rows
  flagged `source='cross_category'`; UI sections them under "Less common".
- **Exclusion:** for `suggest_item_packagings`, exclude
  `(unit_code, conversion_to_base)` pairs that the current `shop_item`
  already has — prevents "pick suggestion, hit unique violation."

A per-category blocklist (`category.disallowed_unit_codes text[]`) is
deferred to v1.5; we'll add it when the first real shop reports noise.

### 1.3 Derived-price hint at first sale

A packaging that has no `sale_price` set always triggers the
priceRequired editor on its first use. If any sibling packaging on the
same `shop_item` is priced, the editor surfaces a **derived hint**:

```
$ [        ]

From your 25-kg bag at $25.00, one kg works out to $1.00.
Add your usual markup.
```

Math:
```
implied_unit_price = sibling.sale_price / sibling.conversion_to_base
```

The hint is **never** auto-filled. Real-world retail loose prices are
typically marked up over bulk pack prices in this market, but the
markup varies. The cashier types the actual price; we just save them
the division.

If no sibling is priced but `last_cost` exists for the current
packaging, the hint reads:
```
This packaging cost you $X.YY. Add your usual markup.
```

### 1.4 Default-flag conventions

Two flags, never both default at once across rows:

- `is_default_sale=true` — the packaging the Sale screen pre-selects.
- `is_default_receive=true` — the packaging the Receive screen
  pre-selects.

When the cashier creates a packaged item via **1A (Sale)**:
- Sold packaging row: `is_default_sale=true`, `is_default_receive=false`.
- Base row: `is_default_sale=false`, `is_default_receive=true` — receives
  later (if it's the base, supplier probably delivers in the base form
  too, e.g., individual items).

When the cashier creates via **1B (Receive)**:
- Sold packaging row: `is_default_receive=true`, `is_default_sale=false`.
- Base row: `is_default_sale=true`, `is_default_receive=false` — the
  shop probably sells loose / by-base even if the supplier delivers
  packaged.

The conventions match the dominant retailer/wholesaler pattern. Either
flag can be flipped later via the Products screen.

When the same packaging serves both sides (single-packaging item),
both flags land on the one row.

### 1.5 Excluded-from-picker rules (sale-and-receive shared)

For the `AddPackagingSheet` picker (3A/3B):
- Exclude `(unit_code, conversion_to_base)` already on this `shop_item`.
- Custom mode: dropdown excludes the item's `base_unit_code` (would
  trip the base-unit guard trigger on insert).
- Custom mode: SAVE disabled when conversion ≤ 1 (the base packaging
  exists by construction; the cashier doesn't need to recreate it).

---

## 2. Scenario walkthroughs

### 2.1 · Scenario 1A — New item · Sale

1. Cashier types **"Kalsiumka"**. After 3 chars `search_items` returns
   no matches. Last result row: **+ Add new item: "Kalsiumka"**.
2. `AddNewItemSheet` opens in **Sale variant**:
   - Field order: Name (auto) → Category → **"How is it sold?"** → Sale price.
   - Price field is required.
3. Category picker. Once chosen, the sheet calls
   `suggest_new_item_options(category_id, locale)` → returns
   `{base_units, packaged_units}`.
4. **"How is it sold?"** renders grouped:
   ```
   ─── By packet ─────────────────
   ◯ By packet                          ← base only
   ◯ 12-packet box                       ← base=packet, conv=12
   ◯ 24-packet carton                    ← base=packet, conv=24
   ─── Loose, by kg ────────────────
   ◯ Loose, by kg                        ← base only
   ◯ 25-kg bag                            ← base=kg, conv=25
   ──────────────────────────────────
   ◯ + Custom packaging
   ```
5. Pick → price field appears with packaging-named label
   ("Sale price per 25-kg bag" / "Sale price per packet").
6. SAVE → `create_shop_item(..., p_default_side='sale')`:
   - Sold-in-base pick: 1 row inserted, priced, both default flags set
     opposite per §1.4.
   - Sold-packaged pick: 2 rows. Sold = `is_default_sale=true`,
     priced. Base = `is_default_sale=false`, `is_default_receive=true`,
     unpriced.
7. RPC returns `(shop_item_id, default_shop_item_unit_id)`.
8. Cart appends a line at qty=1 against the default packaging.

### 2.2 · Scenario 1B — New item · Receive

1. Supplier already picked → cashier types name → no match →
   **+ Add new item**.
2. Same sheet, **Receive variant**:
   - **Question changes:** "How did the supplier deliver?"
   - Sale price field is **hidden**. Cost comes from the bono line.
3. Category + "How did the supplier deliver?" picker as above.
4. SAVE → `create_shop_item(..., p_default_side='receive')`:
   - Sold-in-base pick: 1 row, both default flags.
   - Sold-packaged pick: 2 rows. Sold = `is_default_receive=true`,
     unpriced. Base = `is_default_sale=true`, `is_default_receive=false`,
     unpriced.
5. RPC returns `(shop_item_id, default_shop_item_unit_id)`.
6. Receive screen rebinds its inline form against the returned default
   packaging. Cashier types qty + line total.
7. ADD LINE → SAVE → `post_receive` writes the line, populates
   `shop_item_unit.last_cost`, upserts
   `supplier_item_unit_cost`. Sale prices remain null.
8. First time the shop tries to sell loose (or any other packaging on
   this item), the priceRequired editor fires with the derived hint
   from `last_cost`.

### 2.3 · Scenario 2A — Catalog item, not activated · Sale

1. Search hits global `item_alias`. Result row:
   `shopItemId=null, itemId=<global>, isActivated=false`.
2. Cashier taps → tile shows "Activating…" spinner.
3. `ensure_shop_item(shop_id, item_id)` snapshots the global into the
   shop overlay (idempotent on `(shop_id, item_id)`):
   - `shop_item` (base_unit, category from global).
   - One `shop_item_unit` per active global `item_unit` (full
     structural snapshot including conversion + defaults).
   - One `shop_item_alias` per global `is_display=true` alias.
4. RPC returns `shop_item_id`. Client refreshes the result row to
   surface `defaultShopItemUnitId` + `defaultUnitSalePrice` (both
   resolved from `list_shop_item_units`).
5. Tap proceeds:
   - If default packaging has a `sale_price` → cart appends.
   - Otherwise (the common case — money never snapshots from catalog) →
     priceRequired editor pops with derived hint per §1.3.
6. Cashier confirms price → cart appends → SAVE triggers
   `set_shop_item_unit_sale_price` so future taps fast-add.

### 2.4 · Scenario 2B — Catalog item, not activated · Receive

1. Same activation path: tap → `ensure_shop_item` snapshots global.
2. Client then calls `list_shop_item_units(shop_id, shop_item_id,
   screen='receive')` to surface the default receive packaging.
3. Receive screen pre-fills the inline form. `last_cost` is null on
   first receive; `supplier_item_unit_cost` is empty.
4. Cashier types qty + line total → ADD LINE → SAVE → `post_receive`
   populates `last_cost` and `supplier_item_unit_cost`.
5. If supplier delivered a packaging the catalog didn't ship (e.g.,
   50-kg bag when only 25-kg is in catalog), cashier hits the packaging
   chip → **Scenario 3B**.

### 2.5 · Scenario 3A — Activated item, add packaging · Sale

The rarer entry point — usually a customer asks for a non-standard
size at the till.

1. **Tile/cart long-press** → `LineEditorSheet`.
2. Tap packaging chip → `UnitPickerSheet` lists this item's existing
   packagings.
3. Bottom of the picker: **+ Add packaging** → `AddPackagingSheet`.
4. Picker-first layout:
   - Suggestions from
     `suggest_item_packagings(shop_id, shop_item_id, base_unit_code,
     category_id)` with the tightened rules (§1.2): category-only
     primary, cross-category fallback only when sparse, current
     packagings on this `shop_item` excluded.
   - Last entry: **+ Custom packaging**.
5. Pick suggestion → only the sale price field appears, packaging-named.
   Pick custom → unit dropdown (base unit filtered), conversion field
   (must be > 1), price field.
6. ADD PACKAGING → `create_shop_item_unit`.
7. UnitPickerSheet pops with synthesized `ReceiveUnitOption`.
   LineEditorSheet's chip rebinds to the new packaging. Cart line uses
   the new `shop_item_unit_id`.

**Out-of-band variant:** Products → `ShopItemDetailScreen` → **+ Add
packaging**. Same sheet, no cart context.

### 2.6 · Scenario 3B — Activated item, add packaging · Receive

The **common** packaging-addition entry — suppliers routinely deliver
in sizes the shop hasn't configured.

1. Cashier taps item → inline form pre-fills against current default.
2. Tap packaging chip → `UnitPickerSheet` lists existing packagings
   with supplier-scoped `last_cost` annotation per row.
3. **+ Add packaging** → `AddPackagingSheet`. Same picker-first layout.
4. Pick suggestion → sale price field appears optional (cost is what
   matters here). Pick custom → full form.
5. ADD PACKAGING → `create_shop_item_unit`.
6. UnitPickerSheet pops; receive screen rebinds the inline form against
   the new packaging. Per-unit cost field re-pre-fills from
   `last_cost` (null on first time).
7. Cashier finishes the line → SAVE → `post_receive` populates
   `last_cost`, upserts `supplier_item_unit_cost`.

---

## 3. RPC contract changes

### 3.1 `create_shop_item` (extend)

```sql
create_shop_item(
  p_shop_id            uuid,
  p_name               text,
  p_language_code      text,
  p_base_unit_code     text,
  p_sale_price         numeric default null,
  p_category_id        uuid default null,
  p_sold_unit_code     text default null,         -- new
  p_sold_conversion    numeric default null,      -- new
  p_default_side       text default 'sale'        -- new ('sale' | 'receive')
)
returns table (
  shop_item_id              uuid,
  default_shop_item_unit_id uuid
)
```

Body:
- Validate inputs (existing).
- Insert `shop_item`.
- Always insert the base `shop_item_unit` (unit=base, conversion=1).
- If `p_sold_unit_code` is given AND
  `(p_sold_unit_code, p_sold_conversion) != (p_base_unit_code, 1)`:
  insert the second `shop_item_unit`.
- Apply default flags per §1.4 using `p_default_side`.
- Sale price: rest of price logic moves to applying `p_sale_price` to
  the row matching the "sold" pick. For sold-in-base picks, base row
  gets the price. For sold-packaged picks, sold row gets the price; base
  row's `sale_price` stays null.
- Add the display alias as today.
- Return `(shop_item_id, sold_row_id_if_packaged_else_base_id)`.

### 3.2 `suggest_item_packagings` (tighten)

```sql
suggest_item_packagings(
  p_shop_id          uuid,                        -- new
  p_shop_item_id     uuid,                        -- new
  p_base_unit_code   text,
  p_category_id      uuid default null,
  p_locale           text default 'en',
  p_limit            int default 8
)
returns table (
  unit_code, unit_label, conversion_to_base, uses, source
)
```

Body:
- Same source query but exclude rows where the SAME
  `(unit_code, conversion_to_base)` already exists on
  `shop_item_unit` for this `(p_shop_id, p_shop_item_id)`.
- Primary list: only `source='category'` matches if `p_category_id`
  given.
- If primary length < 3: backfill with `source='cross_category'`
  rows up to `p_limit`.

### 3.3 `suggest_new_item_options` (new)

```sql
suggest_new_item_options(
  p_category_id uuid,
  p_locale      text default 'en'
)
returns jsonb
```

Returns:
```json
{
  "base_units": [
    {"unit_code": "packet", "unit_label": "Packet", "uses": 5},
    {"unit_code": "kg",     "unit_label": "Kg",     "uses": 2}
  ],
  "packaged_units": [
    {
      "unit_code": "box", "unit_label": "Box",
      "conversion_to_base": 24,
      "base_unit_code": "packet", "base_unit_label": "Packet",
      "uses": 1, "source": "category"
    },
    {
      "unit_code": "bag", "unit_label": "Bag",
      "conversion_to_base": 25,
      "base_unit_code": "kg", "base_unit_label": "Kg",
      "uses": 1, "source": "category"
    }
  ]
}
```

Body:
- `base_units`: equivalent of `suggest_category_units(p_category_id)`.
- `packaged_units`: for each base_unit in `base_units`, run the
  packaging suggestion query and union. Each row carries the implied
  base. Same primary/fallback logic.
- Single round trip → the new-item sheet has everything it needs to
  render the grouped picker.

### 3.4 Helpers (no change)

`suggest_category_units` stays as-is; it's still used by the editor
screen and the new RPC may call it internally for reuse.

---

## 4. UI contract changes

### 4.1 `AddNewItemSheet` (rewrite)

- **Variant enum**: `AddNewItemVariant.sale | .receive`.
- **Layout** (5 sections, vertically):
  1. Name (auto-filled from search query).
  2. Category dropdown.
  3. "How is it sold?" (sale) / "How did the supplier deliver?"
     (receive) — picker grouped by base unit per §2.1, suggestions from
     `suggestNewItemOptions(category_id)`.
  4. Sale price field — only when variant is `sale` AND a packaging
     is picked. Label is packaging-aware.
  5. CANCEL / ADD TO SALE | ADD TO RECEIVE.
- **Custom packaging** is the last entry in the picker; opens an
  inline form (base unit dropdown + sold unit dropdown + conversion +
  price).
- **Return record**: includes `shop_item_id`,
  `default_shop_item_unit_id`, `display_name`, `packaging_label`,
  `base_unit_code`, `base_unit_label`, `sale_price`.

### 4.2 `AddPackagingSheet` (small tweak)

- Pass `p_shop_id` + `p_shop_item_id` to `suggestItemPackagings` so
  already-added packagings get excluded.
- "Less common" section header when cross-category fallback rows are
  returned.
- Custom mode: disable SAVE when conversion ≤ 1 (with an inline hint:
  "That's the base packaging — already created automatically.").

### 4.3 `LineEditorSheet` priceRequired mode (small tweak)

- When entering price for a `shop_item_unit` that has any sibling
  packaging with a non-null `sale_price`: surface the derived hint
  copy under the input.
- When no priced sibling but `last_cost` is set on the current
  packaging: show the cost-based hint.
- Hint is **read-only text**, never pre-fills the input.

### 4.4 New shared utility

`String packagingLabel(num conversion, String baseLabel, String unitLabel)` —
mirror of the server's `_format_conversion` formatting. Already exists
inline in `add_packaging_sheet.dart`; lift to `lib/shared/`.

---

## 5. Test plan

### 5.1 Backend

- `create_shop_item`: sold-in-base path; sold-packaged path with
  `p_default_side='sale'` vs `'receive'` — assert correct flag
  assignment on both rows. Base-unit guard trigger still rejects
  malformed inputs (conversion=1 with mismatched unit).
- `suggest_item_packagings`: excludes existing packagings on
  `shop_item_id`; primary-only when 3+ category matches; falls back to
  cross-category when sparse.
- `suggest_new_item_options`: returns both arrays correctly formatted;
  no entries for irrelevant base units.

### 5.2 Flutter

- `AddNewItemSheet`:
  - Sale variant, sold-in-base → cart receives base packaging id with
    price set.
  - Sale variant, sold-packaged → cart receives non-base packaging id;
    base row exists unpriced.
  - Receive variant, sold-packaged → no sale price field shown;
    receive screen rebinds against the sold packaging.
  - Custom path → conversion ≤ 1 disables SAVE.
- `AddPackagingSheet`:
  - Suggestions excluding already-added rows.
  - Custom mode conversion=1 disabled.
- `LineEditorSheet` priceRequired mode:
  - Sibling-derived hint shows when a priced sibling exists.
  - Cost-derived hint shows when only `last_cost` is set.
  - Hint never pre-fills the input.

---

## 6. Implementation order

Each step ends with `flutter analyze`, `flutter test`, and the backend
harness still green.

| # | Backend / Flutter | Scope |
|---|---|---|
| 1 | Backend | Extend `create_shop_item` with `p_sold_*` + `p_default_side`. |
| 2 | Backend | Tighten `suggest_item_packagings` (add `p_shop_id`/`p_shop_item_id`, exclusion + primary-only-with-fallback). |
| 3 | Backend | Add `suggest_new_item_options` jsonb RPC. |
| 4 | Backend | Harness coverage for #1–#3 (allow + deny + exclusion + flag assignment). |
| 5 | Flutter | DTO + ShopApi additions: `NewItemOptions`, `PackagedUnitSuggestion`, extended `createShopItem`, new `suggestNewItemOptions`, updated `suggestItemPackagings` signature. |
| 6 | Flutter | Lift `packagingLabel(...)` helper to `lib/shared/`. |
| 7 | Flutter | `AddPackagingSheet` tweak — pass shop_id + shop_item_id; conversion=1 guard; "Less common" section. |
| 8 | Flutter | `AddNewItemSheet` rewrite — variant-aware, grouped picker, custom form, multi-packaging atomic create. |
| 9 | Flutter | `LineEditorSheet` priceRequired hint. |
| 10 | Flutter | Update all callers + fakes + tests. |
