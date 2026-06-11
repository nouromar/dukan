# Data Model v2 — Central Catalog with Shop Overlay

> **Status:** Locked design proposal. Source of truth for the v1 schema break.
> Supersedes the `catalog_*` + per-shop item layer described in `backend-schema.md`.
> Pre-pilot: migrations will be edited in place. Append-only resumes once we have hosted data.

## 1. Why this redesign

The current schema splits items across `catalog_item` (revisioned, platform-curated) and `item` (per-shop projection). Revisions were intended to let the catalog evolve without disturbing shops, but:

- Activation already copies catalog state into the shop's rows.
- Posting already snapshots name + unit + conversion onto `transaction_line`.
- Both already protect existing data; revisions add no further immutability for v1.

Revisions therefore cost ergonomics (composite FKs, extra joins) without buying anything. The redesign collapses them out, makes packagings first-class, and pushes pricing + inventory into a clean shop overlay where they belong.

## 2. Design principles

1. **Inventory is canonical in base units.** Stock is one pool per item. Selling a 25 kg bag decrements 25 kg; selling 1 kg loose decrements 1 kg. Same pool, no per-packaging counts.
2. **Pricing is per-packaging, per-shop.** A "25 kg bag" has its own retail price independent of "per kg" math. Each `shop_item_unit` row carries its own `sale_price`.
3. **Aliases absorb translations.** `item_alias.is_display=true` is the official name in a language; other rows are search nicknames + typos. One table, one query path.
4. **Shop overrides via nullable FKs.** `shop_item.item_id` and `shop_item_unit.item_unit_id` are nullable. Null = shop-only (cashier added it). FK present = activated from global catalog.
5. **The platform owns structure; the shop owns money + quantity.** Global rows never carry prices or stock. Shop rows never carry conversions for activated packagings (those come via FK).
6. **Composite FKs enforce tenant integrity.** Every shop-scoped table has a `(shop_id, id)` composite key so child rows can FK back with `shop_id` for cross-row tenant safety, not RLS alone.
7. **Posting RPCs are the only sanctioned writers** for `shop_item.current_stock`, `shop_item.avg_cost`, `shop_item_unit.last_cost`, `shop_item_unit.sale_price`, and the `supplier_item_unit_cost` cache. App code never touches these directly.

## 3. Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Catalog revisions | Removed | Activation + line snapshots already provide immutability. |
| `ref_translation` table | Dropped; inline `jsonb` on reference tables | Polymorphic translations don't earn their keep for 5–15 row reference tables. |
| Category hierarchy | `parent_id` nullable, unbounded depth in DB; admin UI restricts to 2 levels for v1 | Standard retail catalog pattern (Shopify/Square/Lightspeed). |
| Negative stock | Allowed; warn at posting, don't block | Real shops oversell briefly; blocking is worse UX than a toast. |
| Migration strategy | Edit existing migrations in place | Pre-pilot; cleanest reading diff. |
| `shop_item_barcode` | In v1 | Shops print local labels (repacks, custom packs); right tier from day one. |
| Base-unit guard | DB-level trigger on `item_unit` | Silent drift between `item.base_unit_code` and the conversion=1 row would corrupt stock math. |
| `item_alias.source` enum | `('platform','learned','ocr_correction')` | Global side only. |
| `shop_item_alias.source` enum | `('manual','ocr_correction','learned')`, default `'manual'` | Cashier-typed item creation is the dominant write. |
| Cashier global-catalog writes | Forbidden | Admin portal owns global rows; cashier only adds shop-local. |
| Items with services (no inventory) | Out of scope for v1 | Defer "kind" column until a service flow ships. |
| Setup item onboarding step | Optional skippable step after template apply | Recommend but don't force; lets shopkeeper add own items, set prices, browse catalog. Overrides CLAUDE.md's implicit "no item config at setup." |
| Sale of an unknown item (Scenario 2) | Force "+ Add new item" sheet with required unit + price | Keeps every transaction_line structured; reports stay clean. No "miscellaneous" line type in v1. |
| Per-shop unit configuration | Out of scope for v1 | Global `unit` table (12 entries) sufficient for grocery. Expand the global seed if a non-grocery vertical onboards. |
| Mid-sale add-item default packaging | Single packaging; base unit = sale unit; conversion = 1 | Shopkeeper can add additional packagings later via Products screen → "+ Add packaging." |
| Activation snapshot semantics | shop_item / shop_item_unit snapshot structure (base_unit, unit_code, conversion_to_base, default flags) at activation; `item_id` / `item_unit_id` become informational provenance pointers only | Critique #4 + #5. Platform-side changes to conversion or defaults never silently change a shop's stock math. Collapses the `local_*` dual-column CHECK pattern into single columns. |
| Reorder threshold display | Stored in base units; UI displays in the shop's default sale unit, format: "Alert when below 5 bags (125 kg)" | Critique #9. Edit accepts input in any active packaging; persisted as base units. |
| Posting-RPC-only writer rule | Posting + price-set + adjustment RPCs are the only sanctioned writers for `current_stock`, `avg_cost`, `last_cost`, `sale_price`, `supplier_item_unit_cost` | Critique #10. Convention only — service role bypasses RLS — so admin portal MUST go through these RPCs. |

## 4. Global layer

Platform-curated, admin-portal write, shop read-only.

### 4.1 `unit` (existing — adds `label_translations`)

```sql
unit (
  id                  uuid pk
  code                text unique check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$')
  default_label       text not null               -- English fallback
  label_translations  jsonb not null default '{}' -- {"so":"Jaakad"}
  is_active           bool not null default true
  created_at, updated_at
)
```

Seed unchanged: `piece, bag, carton, box, bottle, packet, sack, kg, gram, litre, ml, dozen`.

### 4.2 `category` (new)

```sql
category (
  id                 uuid pk
  code               text unique
  parent_id          uuid -> category.id      -- nullable; admin UI limits depth
  name               text not null            -- English fallback
  name_translations  jsonb not null default '{}'  -- {"so":"Cabbitooyin"}
  sort_order         int  not null default 0
  is_active          bool not null default true
  created_at, updated_at
)
-- index on (parent_id, sort_order, name)
```

### 4.3 `item` (new shape; replaces `catalog_item` + `catalog_item_revision`)

```sql
item (
  id              uuid pk
  code            text unique check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*$')
  category_id     uuid -> category.id  not null
  base_unit_code  text -> unit.code    not null
  is_active       bool not null default true
  created_at, updated_at
)
```

No name on the row — display name comes from `item_alias` where `is_display=true`. `code` is the slug for admin-debugging.

### 4.4 `item_unit` (new shape)

```sql
item_unit (
  id                  uuid pk
  item_id             uuid -> item.id  on delete cascade
  unit_code           text -> unit.code  not null
  conversion_to_base  numeric(14,6) not null check (conversion_to_base > 0)
  is_default_sale     bool not null default false
  is_default_receive  bool not null default false
  sort_order          int  not null default 0
  created_at, updated_at
  unique (item_id, unit_code, conversion_to_base)
)
-- partial unique: exactly one row per item_id where conversion_to_base = 1   (the base unit)
-- partial unique: at most one is_default_sale = true per item_id
-- partial unique: at most one is_default_receive = true per item_id
-- trigger: on insert/update, the conversion=1 row's unit_code must equal item.base_unit_code
```

The same `unit_code` ('bag') can appear multiple times on one item with different conversions (10 kg, 25 kg, 50 kg bags).

### 4.5 `item_alias` (new shape; absorbs translations)

```sql
item_alias (
  id             uuid pk
  item_id        uuid -> item.id  on delete cascade
  alias_text     text not null check (length(btrim(alias_text)) > 0)
  language_code  text -> language.code      -- nullable = language-neutral
  is_display     bool not null default false
  source         text not null check (source in ('platform','learned','ocr_correction'))
  weight         int  not null default 0
  is_active      bool not null default true
  created_at, updated_at
  unique (item_id, language_code, alias_text)
)
-- partial unique: at most one is_display = true per (item_id, language_code)
-- index on (lower(alias_text)) where is_active   -- prefix search
```

### 4.6 `item_barcode` (new)

```sql
item_barcode (
  id            uuid pk
  item_unit_id  uuid -> item_unit.id  on delete cascade
  barcode       text not null check (length(btrim(barcode)) > 0)
  symbology     text                                 -- 'ean13','upc_a','gtin14','code128',...
  source        text not null check (source in ('manufacturer','platform','learned'))
  is_primary    bool not null default false
  is_active     bool not null default true
  created_at, updated_at
  unique (item_unit_id, barcode)
)
-- partial unique: at most one is_primary = true per item_unit_id where is_active
-- index on (barcode) where is_active             -- scan lookup; NOT globally unique
```

## 5. Shop overlay

Per-shop, owner+cashier writable through posting/activation RPCs only.

### 5.1 `shop_item` (renamed from `item`)

```sql
shop_item (
  id                    uuid pk
  shop_id               uuid -> shop  on delete cascade

  -- provenance (informational): null = shop-only, not-null = activated from catalog
  item_id               uuid -> item.id  on delete restrict

  -- structural snapshot (copied from global at activation; not a live FK)
  base_unit_code        text -> unit.code   not null
  category_id           uuid -> category.id

  -- inventory state (mutable; written only by posting RPCs)
  current_stock         numeric(14,3) not null default 0
  avg_cost              numeric(14,4) not null default 0  check (avg_cost >= 0)
  reorder_threshold     numeric(14,3) check (reorder_threshold is null or reorder_threshold >= 0)

  is_active             bool not null default true
  created_by            uuid -> auth.users  on delete set null
  created_at, updated_at
  unique (shop_id, id)
  unique (shop_id, item_id) where item_id is not null
)
```

Activation semantics: `ensure_shop_item` copies `base_unit_code` (from `item`) and `category_id` into this row. Once written, platform-side changes to the source `item` never touch the shop's snapshot. The `item_id` FK remains for provenance / future analytics — it is not used as a live data source.

`reorder_threshold` is stored in base units. UI displays it in the shop's default sale packaging: e.g., `5 bags (125 kg)`. Edit accepts input in any active packaging and converts on save.

Negative stock allowed; posting RPC raises a NOTICE (surfaced as a warning toast in the app).

### 5.2 `shop_item_unit` (renamed)

```sql
shop_item_unit (
  id                  uuid pk
  shop_id             uuid -> shop  on delete cascade
  shop_item_id        uuid                                 -- composite FK below

  -- provenance (informational): null = shop-only packaging
  item_unit_id        uuid -> item_unit.id

  -- structural snapshot (copied from global at activation; never updated post-activation)
  unit_code           text -> unit.code   not null
  conversion_to_base  numeric(14,6) not null check (conversion_to_base > 0)

  -- money (always shop-owned, mutable via posting + price RPCs)
  sale_price          numeric(14,2) check (sale_price is null or sale_price >= 0)
                      -- NULL is meaningful: cashier hasn't priced this packaging;
                      --                    the priceRequired editor fires on first use
  last_cost           numeric(14,4) check (last_cost is null or last_cost >= 0)
                      -- NULL = no receive yet against this packaging

  -- shop-owned defaults (initialized from global flags at activation; mutable after)
  is_default_sale     bool not null default false
  is_default_receive  bool not null default false
  sort_order          int  not null default 0
  is_active           bool not null default true
  created_at, updated_at

  foreign key (shop_id, shop_item_id) references shop_item (shop_id, id) on delete cascade
  unique (shop_id, id)
  unique (shop_id, shop_item_id, item_unit_id) where item_unit_id is not null
)
-- partial unique: exactly one row per shop_item_id where conversion_to_base = 1  (the base unit)
-- partial unique: at most one is_default_sale    = true per (shop_id, shop_item_id)
-- partial unique: at most one is_default_receive = true per (shop_id, shop_item_id)
-- trigger: on insert/update, the conversion=1 row's unit_code must equal shop_item.base_unit_code
```

Activation copies four things from each global `item_unit` into a new `shop_item_unit`:
`unit_code`, `conversion_to_base`, `is_default_sale`, `is_default_receive`. After activation, these fields are owned by the shop; the platform can change the global rows freely and existing activations are untouched.

Shop-only packagings (cashier hits "+ Add packaging") use the same shape — `item_unit_id` stays null, but `unit_code` + `conversion_to_base` are populated directly from the cashier's input.

The "exactly one conversion=1 row per shop_item" invariant is now enforceable at the DB level by a partial unique index — no application-side guard needed.

### 5.3 `shop_item_alias` (renamed)

```sql
shop_item_alias (
  id             uuid pk
  shop_id        uuid -> shop  on delete cascade
  shop_item_id   uuid                                            -- composite FK below
  alias_text     text not null
  language_code  text -> language.code                           -- nullable
  is_display     bool not null default false
  source         text not null default 'manual'
                 check (source in ('manual','ocr_correction','learned'))
  weight         int  not null default 0
  is_active      bool not null default true
  created_at, updated_at
  foreign key (shop_id, shop_item_id) references shop_item (shop_id, id) on delete cascade
  unique (shop_id, shop_item_id, language_code, alias_text)
)
-- partial unique: at most one is_display = true per (shop_id, shop_item_id, language_code)
```

### 5.4 `shop_item_barcode` (new)

```sql
shop_item_barcode (
  id                    uuid pk
  shop_id               uuid -> shop  on delete cascade
  shop_item_unit_id     uuid                                    -- composite FK below
  barcode               text not null
  symbology             text
  is_primary            bool not null default false
  is_active             bool not null default true
  created_at, updated_at
  foreign key (shop_id, shop_item_unit_id) references shop_item_unit (shop_id, id) on delete cascade
  unique (shop_id, shop_item_unit_id, barcode)
)
-- partial unique: at most one is_primary = true per (shop_id, shop_item_unit_id) where is_active
-- index on (shop_id, barcode) where is_active   -- scan lookup
```

Used for shop-printed labels (repacks, custom packs). Scan lookup checks both `item_barcode` (global) and `shop_item_barcode` (shop) — first hit wins, ranked by `is_primary` then `is_active`.

### 5.5 `supplier_item_unit_cost` (replaces `learned_supplier_item_cost`)

```sql
supplier_item_unit_cost (
  id                   uuid pk
  shop_id              uuid -> shop  on delete cascade
  party_id             uuid                                     -- composite FK below
  shop_item_unit_id    uuid                                     -- composite FK below
  last_unit_cost       numeric(14,4) check (last_unit_cost is null or last_unit_cost >= 0)
  last_received_at     timestamptz
  created_at, updated_at
  foreign key (shop_id, party_id)          references party (shop_id, id) on delete cascade
  foreign key (shop_id, shop_item_unit_id) references shop_item_unit (shop_id, id) on delete cascade
  unique (shop_id, party_id, shop_item_unit_id)
)
-- index on (shop_id, shop_item_unit_id, last_received_at desc)
```

## 6. Translations strategy

`ref_translation` dropped. Per-table `jsonb` columns on entities that have user-facing labels:

| Table | Translatable field |
|---|---|
| `unit` | `label_translations jsonb` |
| `category` | `name_translations jsonb` |
| `payment_method` | `label_translations jsonb` |
| `adjustment_reason` | `label_translations jsonb` |
| `party_type` | `label_translations jsonb` |
| `expense_category` (per shop) | `name_translations jsonb` |
| `supplier_type` (per shop) | `label_translations jsonb` |

Lookup helper:

```sql
create function public.tr(value text, translations jsonb, locale text)
  returns text language sql immutable as $$
  select coalesce(translations->>locale, translations->>'en', value)
$$;
```

Items + shop items resolve their display name via the alias chain (see section 8.1).

## 7. Posting & projections

### Sanctioned-writers rule

The following columns are **projections** — cached state computed from transactions and adjustments. They may **only** be written by the sanctioned RPCs below. Service role bypasses RLS, so this is a convention enforced by code review, not by the database. Admin portal MUST go through these RPCs for any state change.

| Column | Sanctioned writer(s) |
|---|---|
| `shop_item.current_stock` | `post_sale`, `post_receive`, `void_sale`, `void_receive`, `inventory_adjustment` |
| `shop_item.avg_cost` | `post_receive`, `void_receive`, `inventory_adjustment` |
| `shop_item_unit.last_cost` | `post_receive`, `void_receive` |
| `shop_item_unit.sale_price` | `set_shop_item_unit_sale_price`, `post_sale` (on cashier override) |
| `supplier_item_unit_cost.last_unit_cost` | `post_receive`, `void_receive` |

If a feature needs to change one of these columns, it MUST go through (or extend) the existing RPC — never a direct UPDATE.

### Locking + computation

Every posting RPC continues to use `SELECT FOR UPDATE` on the `shop_item` row to serialize concurrent stock decrements. Cached projections written only by these RPCs:

- `shop_item.current_stock` — base units, signed delta from `stock_movement`.
- `shop_item.avg_cost` — weighted average **per base unit**, recomputed on each receive line.
- `shop_item_unit.last_cost` — set on receive lines (the per-packaging unit cost).
- `shop_item_unit.sale_price` — set when a cashier overrides the price on a sale line (long-press editor).
- `supplier_item_unit_cost` — upsert per receive line, keyed on (shop_id, supplier_party_id, shop_item_unit_id).

Line shape on `transaction_line` (additive change):

```
transaction_line (
  ...,
  item_id              uuid -> shop_item.id      -- existing
  shop_item_unit_id    uuid -> shop_item_unit.id -- NEW (composite FK)
  unit_id              uuid -> unit              -- snapshotted from shop_item_unit
  unit_amount          numeric                   -- per packaging, what cashier typed
  base_quantity        numeric                   -- in base units, computed at posting
  unit_code_snapshot, unit_conversion_to_base_snapshot   -- existing
)
```

`stock_movement` is unchanged in shape (still keyed on `item_id` = `shop_item.id`, `quantity_delta` in base units).

## 8. Daily flow walkthroughs

### 8.1 Search (Sale + Receive)

`search_items(shop_id, query, screen, locale, party_id?)` walks **four** sources and returns one row per matching `shop_item`:

```
1.  shop_item_alias   (per-shop, locale match, is_active)
2.  global item_alias (via shop_item.item_id, locale match, is_active)
3.  shop_item_alias   (any language)
4.  global item_alias (any language)
```

Rank: locale + `is_display=true` first, then prefix match, then by `weight`, with a final boost for "appears in this shop's last N transactions."

Display name resolved per row by the `shop_item_display_name(shop_item_id, locale)` SQL function, which mirrors the search chain.

If the query looks like a barcode (digits-only, ≥ 8 chars), the RPC also probes `shop_item_barcode` then `item_barcode`. A hit returns a row pre-locked to a specific `shop_item_unit_id`.

Each row carries the screen's default unit info:

```
shop_item_id,
display_name,
base_unit_label,
default_shop_item_unit_id,        -- screen-specific (sale or receive)
default_unit_packaging_label,     -- "25 kg bag"
default_unit_sale_price,          -- if screen='sale'
default_unit_last_cost,           -- if screen='receive' (party-scoped via supplier_item_unit_cost when party_id set)
current_stock_in_base
```

### 8.2 Receive: 40 × 25 kg bag of rice at $20/bag

Catalog state:

```
item (Rice, base_unit_code='kg')
item_unit:  IU_kg  (conversion=1)
            IU_b10 (unit='bag', conversion=10)
            IU_b25 (unit='bag', conversion=25, is_default_receive=true)
            IU_b50 (unit='bag', conversion=50)
```

Shop has activated:

```
shop_item SI1 (item_id=Rice, current_stock=0, avg_cost=0)
shop_item_unit:
  SIU_kg   (item_unit_id=IU_kg,  sale_price=$1.20)
  SIU_b10  (item_unit_id=IU_b10)
  SIU_b25  (item_unit_id=IU_b25, is_default_receive=true)
  SIU_b50  (item_unit_id=IU_b50)
```

Cashier flow: pick Hodan → search "rice" → tap → form pre-fills `Qty 1, [ 25 kg bag ▾ ], Per Bag empty, Total empty` → cashier types `40` and `800` → ADD LINE → SAVE.

`post_receive` payload:

```json
{
  "shop_id": "<shop>",
  "party_id": "<Hodan>",
  "lines": [
    { "shop_item_unit_id": "SIU_b25", "quantity": 40, "line_total": 800 }
  ],
  "paid_amount": 0,
  "client_op_id": "..."
}
```

Rows written:

```
txn        (T1)
transaction_line (TL1):
  item_id            = SI1
  shop_item_unit_id  = SIU_b25
  quantity           = 40
  unit_id            = <bag>
  unit_amount        = 20.00          -- per bag
  base_quantity      = 1000           -- kg
  line_total         = 800
  snapshots          (unit_code='bag', conversion_to_base=25, item_name='Rice')

stock_movement:
  item_id            = SI1
  quantity_delta     = +1000
  unit_cost          = 0.80           -- per base unit
```

Projections:

```
shop_item SI1:        current_stock 0 → 1000;   avg_cost 0 → 0.80
shop_item_unit SIU_b25: last_cost → 20.00
supplier_item_unit_cost (Hodan, SIU_b25): {last_unit_cost: 20.00, last_received_at: now}
```

### 8.3 Sale: 1 kg loose from the same pool

After the receive above, cashier rings up 1 kg loose at $1.20.

Line payload: `{ shop_item_unit_id: SIU_kg, quantity: 1, unit_price: 1.20 }`.

```
transaction_line (TL2): base_quantity = 1, unit_amount = 1.20, line_total = 1.20
                        cogs_unit_cost = 0.80 (= shop_item.avg_cost at posting)
                        cogs_total     = 0.80

stock_movement:         quantity_delta = -1, unit_cost = 0.80

shop_item SI1:          current_stock 1000 → 999;  avg_cost unchanged
```

Selling a 25 kg bag instead: `{ shop_item_unit_id: SIU_b25, quantity: 1, unit_price: 25 }`. Decrements 25 kg from the same pool, cogs snapshots 25 × 0.80 = $20.

### 8.4 Void

`void_sale(shop_id, txn_id, client_op_id, refund_amount?)` writes a reversing `txn` with mirrored lines. Each reversing line copies `shop_item_unit_id`, negates `base_quantity`, snapshots `cogs_unit_cost` from the original.

Same for `void_receive`. The packaging stays correct on receipt re-renders post-void.

### 8.5 Scenario coverage

#### Sale of an item that's in the global catalog but not yet activated

1. Cashier types → `search_items` walks global `item_alias`, returns the row marked `shopItemId = null`.
2. Cashier taps → client calls `ensureShopItem(shopId, itemId)` → server creates `shop_item` + a `shop_item_unit` row for every active global packaging in one transaction.
3. Returns `shopItemId` + default `shopItemUnitId`.
4. Cart appends a line; if `sale_price` is null, the priceRequired editor fires.

Report impact: line has a real `shop_item_id` → resolves to a global `item` → category, brand, all available. Identical to a long-activated item.

#### Sale of an item not in the global catalog and not added locally

1. Cashier types → no matches.
2. After ≥ 3 chars typed, search shows `"+ Add new item: '{query}'"` as the last result.
3. Tap → bottom sheet with **required** unit + **required** price + auto-filled name (optional category).
4. Save → `createShopItem` creates a shop-local `shop_item` (`item_id` null) plus a single `shop_item_unit` (`item_unit_id` null, `local_conversion_to_base = 1`, `local_unit_code = local_base_unit_code`).
5. Returns `shopItemUnitId` → cart appends line.

Report impact: line has a real (shop-local) `shop_item_id`. Grouping by name works (via `shop_item_alias`). Grouping by category puts it under "Uncategorized" unless the cashier picked one. Grouping by global catalog → it appears in the "shop-local items" slice.

#### Sale of an item where the cashier doesn't know the price

The priceRequired editor opens on tap (existing behavior, unchanged). Editor enforces a positive numeric value before allowing ADD LINE.

#### Sale that would drive stock negative

Sale completes; posting RPC raises `NOTICE` carrying the post-decrement stock value. Client surfaces a non-blocking toast:

> ⚠ Rice stock is now −3 kg. Receive soon.

Does not block save. Auto-dismisses after 4 s.

#### Receive of a packaging that's not in the global catalog

1. Cashier opens unit picker → "+ Add packaging" entry at the bottom.
2. Sheet asks for unit code + conversion-to-base + optional price.
3. Save → `createShopItemUnit` creates a shop-local `shop_item_unit` (`item_unit_id` null).
4. Returns `shopItemUnitId` → receive line uses it.

#### No "miscellaneous" line type in v1

Every `transaction_line` of `type='sale'|'receive'` points to a real `shop_item_unit`. The CHECK constraint enforces it. If a cashier truly can't classify a sale (rare in grocery), they create a shop-local item like "Miscellaneous service charge" — a real row, with a real price, appearing in reports as such.

## 9. Migration plan (edit existing files in place)

| File | Change |
|---|---|
| `0002_reference_data.sql` | DROP `ref_translation` table. Add `label_translations jsonb` / `name_translations jsonb` to `unit`, `payment_method`, `adjustment_reason`, `party_type`. Update seed inserts to populate jsonb. Add the `tr(value, translations, locale)` SQL helper. |
| `0006_catalog_templates.sql` | DROP `catalog_product_concept`, `catalog_item_revision`, `catalog_product_translation`. Rewrite `catalog_item` → `item` (slim shape per §4.3). Rewrite `catalog_item_unit` → `item_unit` (per §4.4) including base-unit guard trigger. Rewrite `catalog_item_alias` → `item_alias` (per §4.5). Add `category` table (§4.2) before `item`. Add `item_barcode` (§4.6). Templates table shape unchanged — they reference items by `item_id`. |
| `0007_items_parties.sql` | Rename `item` → `shop_item` (per §5.1). Rename `item_unit` → `shop_item_unit` (per §5.2). Rename `item_alias` → `shop_item_alias` (per §5.3). Add `shop_item_barcode` (per §5.4) and `supplier_item_unit_cost` (per §5.5). All in this single file since they form one tenant cluster. |
| `0008_documents_ocr.sql` | Update FKs that pointed at old `item` to `shop_item`. |
| `0009_transactions_stock_payments.sql` | Add `shop_item_unit_id uuid` column to `transaction_line` with composite FK `(shop_id, shop_item_unit_id) -> shop_item_unit (shop_id, id)`. Add index `transaction_line(shop_id, shop_item_unit_id)`. Update `stock_movement` FK target name (`item` → `shop_item`). No shape change to `stock_movement` itself. |
| `0010_posting_rpcs.sql` | Rewrite `post_sale`, `post_receive` to: (a) take `shop_item_unit_id` per line; (b) resolve conversion + base_unit on the server; (c) compute `base_quantity` and `unit_cost_per_base`; (d) write `transaction_line.shop_item_unit_id`; (e) update `shop_item_unit.last_cost` (receives) and `shop_item_unit.sale_price` (sale overrides); (f) upsert `supplier_item_unit_cost`; (g) emit `NOTICE` when stock would go negative. |
| `0011_catalog_activation.sql` | Rewrite `ensure_shop_item(shop_id, item_id, client_op_id?)`. Idempotent; returns `shop_item.id`. Activation copies every active `item_unit` of the source item into `shop_item_unit` with `item_unit_id` set, no local fields, no prices yet. |
| `0012_apply_template.sql` | Rewrite to batch-call `ensure_shop_item` for each global item the template references. Templates no longer carry their own item definitions — they're curated subsets of the global catalog. |
| `0013_reports_reconciliation.sql` | Update view definitions for renamed tables/columns (`item` → `shop_item`, etc.). |
| `0014_learning_profiles.sql` | DROP `learned_supplier_item_cost` (replaced by `supplier_item_unit_cost` in 0007). Keep any other learning artifacts that aren't about supplier costs. |
| `0015_rls_storage.sql` | Update RLS policies for renamed tables. Add policies for `shop_item_barcode`, `supplier_item_unit_cost`. Global tables (`item`, `item_unit`, `item_alias`, `item_barcode`, `category`) get `select to authenticated; no insert/update/delete except via service role` (admin portal). |
| `0016_seed_grocery_template.sql` | Rewrite to seed global catalog directly (categories + items + item_units + item_aliases + item_barcodes), then create a `template` row whose payload is a list of global item codes. |
| `0017_apply_template_lazy.sql` | Adapt to new `apply_template` (mostly minor). |
| `0018_ensure_shop_item.sql` | Fold into 0011. Either repurpose this file to add the related indexes or leave a comment noting the function moved. |
| `0019_search_items.sql` | Rewrite as the consolidated `search_items(shop_id, query, screen, locale, party_id?)` matching §8.1. |
| `0020_search_parties.sql` | Unchanged. |
| `0021_search_items_screen_param.sql` | Fold into 0019; the file becomes a no-op or notes the consolidation. |
| `0022_search_items_locale.sql` | Same as 0021. |
| `0023_set_item_sale_price.sql` | Rename function → `set_shop_item_unit_sale_price(shop_id, shop_item_unit_id, price, client_op_id?)`. New signature; idempotent. |
| `0024_search_items_party.sql` | Fold into 0019. |
| `0025_search_items_receive_unit.sql` | Fold into 0019. |
| `0026_list_item_units.sql` | Rewrite as `list_shop_item_units(shop_id, shop_item_id, screen)` returning `shop_item_unit` rows with derived packaging labels ("25 kg bag"). |
| `0027_create_party.sql` | Unchanged. |
| `0028_sale_history_and_void.sql` | `get_sale_lines` returns `shop_item_unit_id` + the derived packaging label. `list_sales`/`get_sale` unchanged. |
| `0029_void_with_refund.sql` | Reversal-RPC change: copy `shop_item_unit_id` from original lines to reversing lines. |
| `0030_receive_history_and_void.sql` | Same as 0028/0029 for receives. |

**New tables that need new migrations** — none. Everything fits into existing files via edits.

**New RPCs** to add (probably folded into the migration where they semantically belong):

- `create_shop_item(shop_id, name, language_code, category_id?, base_unit_code, packagings jsonb)` — shop-local item creation. Folded into `0011_catalog_activation.sql` since it's a sibling of `ensure_shop_item`.
- `create_shop_item_unit(shop_id, shop_item_id, unit_code, conversion_to_base, sale_price?)` — shop-local packaging. Folded into `0011`.
- `add_shop_item_alias(shop_id, shop_item_id, alias_text, language_code, is_display, source)` — used by OCR + cashier corrections. Folded into `0019` (search domain).
- `shop_item_display_name(shop_item_id, locale)` — SQL function, used by search and reports. Folded into `0019`.
- `tr(value, translations, locale)` — generic translation helper. Folded into `0002`.

## 10. Backend RPC changes (summary)

| RPC | Status | Signature change |
|---|---|---|
| `ensure_shop_item` | Rewritten | `(shop_id, item_id, client_op_id?)` → `shop_item.id` |
| `create_shop_item` | New | `(shop_id, name, language_code, category_id?, base_unit_code, packagings jsonb)` → `shop_item.id` |
| `create_shop_item_unit` | New | `(shop_id, shop_item_id, unit_code, conversion_to_base, sale_price?)` → `shop_item_unit.id` |
| `set_shop_item_unit_sale_price` | Renamed from `set_item_sale_price` | `(shop_id, shop_item_unit_id, price, client_op_id?)` |
| `add_shop_item_alias` | New | `(shop_id, shop_item_id, alias_text, language_code, is_display, source)` |
| `search_items` | Rewritten | `(shop_id, query, screen, locale, party_id?)` — payload includes `shop_item_unit_id` + packaging label |
| `list_shop_item_units` | Rewritten from `list_item_units` | `(shop_id, shop_item_id, screen)` |
| `post_sale` | Modified | Line shape: `{ shop_item_unit_id, quantity, unit_price }` |
| `post_receive` | Modified | Line shape: `{ shop_item_unit_id, quantity, line_total }` |
| `void_sale`, `void_receive` | Modified | Reversing lines copy `shop_item_unit_id` |
| `list_sales`, `get_sale`, `list_receives`, `get_receive` | Unchanged signatures | Underlying rows include new column |
| `get_sale_lines`, `get_receive_lines` | Payload extended | Include `shop_item_unit_id` + derived packaging label |
| `apply_template` | Rewritten | Batch `ensure_shop_item` against globally-curated catalog |
| `create_party`, `search_parties` | Unchanged | — |
| `create_organization`, `create_shop` | Unchanged | — |

## 11. Frontend changes (Flutter)

### 11.1 DTOs — `lib/api/types.dart`

| DTO | Change |
|---|---|
| `ItemSearchResult` | Drop `catalogItemId`, `isActivated`. Add `shopItemId`, `defaultShopItemUnitId`, `packagingLabel`. Keep `name`, `baseUnitLabel`, `salePrice`, `lastCost`, `currentStock`. |
| `ReceiveUnitOption` | Sources from `shop_item_unit`. Carries `shopItemUnitId`, `packagingLabel` (e.g. "25 kg bag"), `conversionToBase`, `isDefault`, `salePrice` (when sale screen), `lastCost`. |
| `SaleLine` | Replace `itemId + unitId` with `shopItemUnitId`. Quantity + unit_price stay. |
| `ReceiveLinePayload` | Replace `itemId + unitId` with `shopItemUnitId`. Quantity + line_total stay. |
| `SaleLineDetail`, `ReceiveLineDetail` | Add `shopItemUnitId`, `packagingLabel`. Keep existing name + unit snapshots. |
| `ShopSummary` | Unchanged. |
| `PartySearchResult`, `ExpenseCategoryOption`, `UnitOption`, `ReferenceOption` | Unchanged. |
| `SaleSummary`, `ReceiveSummary` (typedef) | Unchanged (header-level — they don't reference items). |
| `ShopItemSummary` (new) | For Products screen list rows: `shopItemId`, `displayName`, `categoryName`, `baseUnitLabel`, `currentStock`, `unitCount`. |
| `ShopItemUnitDetail` (new) | For per-item unit list / editor: `shopItemUnitId`, `packagingLabel`, `unitCode`, `conversionToBase`, `salePrice`, `lastCost`, `isDefaultSale`, `isDefaultReceive`, `isActive`. |

### 11.2 ShopApi — `lib/api/shop_api.dart`

Methods that **change signature or payload**:

- `searchItems(shopId, query, screen, locale, partyId?)` — same arguments, payload now includes `shopItemId`, `defaultShopItemUnitId`, `packagingLabel`.
- `ensureShopItem(shopId, itemId, clientOpId?)` — return type changes from `String itemId` to `String shopItemId`.
- `setShopItemUnitSalePrice(shopId, shopItemUnitId, price)` — replaces `setItemSalePrice`.
- `listShopItemUnits(shopId, shopItemId, screen?)` — replaces `listItemUnits`. Returns `ShopItemUnitDetail[]`.
- `postSale(shopId, lines, paidAmount, ...)` — `lines[i]` is `{ shopItemUnitId, quantity, unitPrice }`.
- `postReceive(shopId, partyId, lines, paidAmount, ...)` — `lines[i]` is `{ shopItemUnitId, quantity, lineTotal }`.
- `getSaleLines(shopId, txnId)` — returns rows including `shopItemUnitId` + `packagingLabel`.
- `getReceiveLines(shopId, txnId)` — same.

Methods that **are new**:

- `createShopItem(shopId, name, languageCode, categoryId?, baseUnitCode, packagings)` → `shopItemId`. `packagings` is a list of `{ unitCode, conversionToBase, salePrice? }`.
- `createShopItemUnit(shopId, shopItemId, unitCode, conversionToBase, salePrice?)` → `shopItemUnitId`.
- `addShopItemAlias(shopId, shopItemId, aliasText, languageCode, isDisplay, source)` → void. Used by OCR feedback + cashier rename.
- `listShopItems(shopId, categoryId?, query?)` → `ShopItemSummary[]`. For the Products screen.
- `getShopItem(shopId, shopItemId)` → full detail (item + units + barcodes + aliases). For the editor.

Methods that are **unchanged**:

- `listAvailableTemplates`, `applyTemplate`, `completeSetup` — same surface, RPC internals change.
- `searchParties`, `createParty` — items not involved.
- `listUnits`, `listLanguages`, `listCurrencies`, `currencySymbols` — reference lookups.
- `listExpenseCategories`, `postExpense` — expenses don't touch items.
- `postPayment` — payments don't touch items.
- `listSales`, `getSale`, `voidSale` — header-level, unchanged signatures.
- `listReceives`, `getReceive`, `voidReceive` — header-level, unchanged signatures.
- `updateShopDefaults`, `fetchShop` — shop settings, unchanged.

### 11.3 Controllers

| File | Change |
|---|---|
| `lib/sale/cart_controller.dart` | Line model: `{ shopItemUnitId, quantity, unitPrice, packagingLabel, baseUnitLabel }`. `addLine(shopItemUnitId, qty, unitPrice)` replaces the dual-key version. Unit-switch on a cart line replaces `shopItemUnitId` and recomputes the display. |
| `lib/receive/receive_controller.dart` | Same shape: `{ shopItemUnitId, quantity, lineTotal, unitCost, packagingLabel }`. Two-way bind logic (per-unit ⇄ total) unchanged. |
| `lib/payment/payment_controller.dart` | **No change.** Payments are item-free. |
| `lib/expense/expense_controller.dart` | **No change.** Expenses key off `expense_category_id`. |
| `lib/auth/auth_controller.dart` | **No change.** |

### 11.4 Screens — daily flows

| Screen | Change |
|---|---|
| `lib/sale/sale_screen.dart` | Search-result tile uses `defaultShopItemUnitId` + `packagingLabel`. Long-press → `line_editor_sheet` operating on shop_item_unit. Tile renders "Rice — 25 kg bag — $25" when packaging size matters; just "Rice — $1.20" when base-unit and only one packaging exists. Add "+ Add new item" as the last search result. |
| `lib/sale/line_editor_sheet.dart` | Operates on `ShopItemUnitDetail`. Long-press price override writes `setShopItemUnitSalePrice`. Unit chip opens `unit_picker_sheet` for switching packaging mid-edit. |
| `lib/receive/receive_screen.dart` | Same as sale: tile + packaging label. Plus: unit picker exposes "+ Add packaging" entry. Search bar shows "+ Add new item" when no match. |
| `lib/receive/unit_picker_sheet.dart` | Lists `shop_item_unit` rows with derived labels ("10 kg bag" / "25 kg bag" / "50 kg bag" / "kg"). Selected row marked. Bottom button: "+ Add packaging" → opens `add_packaging_sheet`. |

### 11.5 Screens — history + detail

| Screen | Change |
|---|---|
| `lib/sale/sale_history_screen.dart` | **No structural change.** Row shows date + total + cash/debt subtitle. Doesn't reference items. |
| `lib/sale/sale_detail_screen.dart` | Per-line render now includes `packagingLabel`: "Rice · 25 kg bag · 2 × $25 = $50". Cash/debt rows unchanged. VOID button unchanged. |
| `lib/receive/receive_history_screen.dart` | **No structural change.** Header-level rows only. |
| `lib/receive/receive_detail_screen.dart` | Per-line render now includes `packagingLabel`: "Rice · 25 kg bag · 40 × $20 = $800". Supplier label + VOID button unchanged. |

### 11.6 Screens — voiding

Void RPCs unchanged on the client; the schema change is server-side (reversal lines copy `shop_item_unit_id`). The void confirm dialogs in `sale_detail_screen.dart` + `receive_detail_screen.dart` need no changes.

### 11.7 Screens — non-flow

| Screen | Change |
|---|---|
| `lib/payment/payment_screen.dart` | **No change.** Posts payments against a party + amount; items not involved. |
| `lib/expense/expense_screen.dart` | **No change.** Category chip + amount only. |
| `lib/home/home_screen.dart` | **No change.** |
| `lib/settings/settings_screen.dart` | **No change.** Optionally surface a "Manage products" link to Products screen (already there). |
| `lib/setup/shop_type_setup_screen.dart` | Template-apply RPC payload unchanged from client side. Server-side semantics change (now batches `ensure_shop_item`). |

### 11.8 Screens — auth

All unchanged:

- `lib/auth/phone_login_screen.dart`
- `lib/auth/otp_verification_screen.dart`
- `lib/auth/owner_onboarding_screen.dart`
- `lib/auth/shop_picker_screen.dart`

### 11.9 Screens — shared / chrome

All unchanged:

- `lib/shared/dukan_app_bar.dart`
- `lib/shared/feedback.dart`
- `lib/shared/formatting.dart`
- `lib/shared/friendly_error_screen.dart`
- `lib/shared/l10n.dart`
- `lib/shared/loading_screen.dart`
- `lib/shared/locale_controller.dart`
- `lib/shared/money.dart`
- `lib/shared/navigation.dart`
- `lib/shared/party_picker_sheet.dart`
- `lib/shared/add_party_sheet.dart`
- `lib/shared/supabase_config_screen.dart`
- `lib/shared/fallback_localizations.dart`
- `lib/app/auth_bootstrap.dart`
- `lib/main.dart`
- `lib/config/app_config.dart`

### 11.10 Screens — new

| New file | Purpose |
|---|---|
| `lib/products/shop_item_editor_screen.dart` | Create or edit a shop-local item: name (per language), category, base unit, packagings (each with sale_price). On save → `createShopItem` or batched mutate. |
| `lib/receive/add_packaging_sheet.dart` | Bottom sheet to add a packaging to the current item. Inputs: unit code, conversion-to-base, optional sale_price. On save → `createShopItemUnit`. Used from both unit_picker_sheet and shop_item_editor_screen. |
| `lib/products/shop_item_detail_screen.dart` | Full shop_item view: packagings + barcodes + aliases. Reached from Products screen list row. |
| `lib/sale/add_new_item_sheet.dart` | Bottom sheet launched from Sale/Receive search when no match. Required: name (auto-filled), unit (global dropdown, no default), price. Optional: category. Returns `shopItemUnitId`; sale flow appends a cart line. |
| `lib/products/catalog_picker_screen.dart` | Browse global catalog grouped by category. Multi-select via checkboxes. "ADD N ITEMS" calls `ensureShopItem` in a batch. |
| `lib/setup/setup_item_onboarding_screen.dart` | Step 3 of setup, after template apply. Three optional cards: Add my items, Set prices, Browse catalog. Primary CTA: "SKIP — START SELLING." Skippable; persists `shop.onboarding_completed_at` once dismissed. |

### 11.11 Products screen — refactor

| Old | New |
|---|---|
| `lib/products/products_screen.dart` lists global catalog items with isActivated flags | Lists `shop_item` rows the shop carries. Tap → `shop_item_detail_screen`. "+ Add new item" → `shop_item_editor_screen` in create mode. "Browse catalog" button → catalog picker that calls `ensureShopItem` on tap. |

### 11.12 Mock / prototype

| File | Change |
|---|---|
| `lib/mock/mock_data.dart` | Update mock catalog shapes to the new model so the prototype mode still runs. |
| `lib/prototype/_widgets.dart`, `lib/prototype/inline_party_search.dart` | **No change** unless they reference the old item shape. Review during implementation. |

### 11.13 Localization

Add new ARB keys for:

- "Add new item" / "Item cusub"
- "Add packaging" / "Ku dar baakad"
- "Packaging" / "Baakad"
- "Choose category" / "Dooro nooca"
- "Stock low" warning / "Kayd hoos u dhacay" (for the negative-stock toast at receive/sale time)
- Add packaging size labels like "{quantity} {base} bag" — already covered by `unitPickerConversion`, may need a packaging-aware variant.

### 11.14 Tests — updates

- `test/shared/fakes.dart` — update `FakeShopApi` with new signatures + add stubs for `createShopItem`, `createShopItemUnit`, `addShopItemAlias`, `listShopItems`, `getShopItem`. Update DTO fixture builders.
- Every existing flow test that constructs `SaleLine`, `ReceiveLinePayload`, or `ItemSearchResult` — update for new field shape.

### 11.15 Tests — new

- `test/sale/sale_screen_packaging_test.dart` — search returns multi-packaging item, default sale unit pre-fills, long-press switches packaging.
- `test/receive/receive_screen_packaging_test.dart` — same for receive; "+ Add packaging" path.
- `test/receive/add_packaging_sheet_test.dart` — sheet validation + RPC call.
- `test/products/shop_item_editor_screen_test.dart` — create shop-local item with multiple packagings.
- `test/products/shop_item_detail_screen_test.dart` — render packagings + barcodes + aliases; edit price.
- `test/sale/sale_detail_screen_packaging_test.dart` — line renders with packaging label.
- `test/receive/receive_detail_screen_packaging_test.dart` — same for receives.
- `test/sale/negative_stock_warning_test.dart` — toast appears when posting goes below zero.

## 12. Test plan

### Backend (`scripts/test-backend-migrations.sh`)

Add coverage for:

- `ensure_shop_item` idempotency + concurrent activation race (insert ON CONFLICT path).
- `create_shop_item` + `create_shop_item_unit` happy + denied (admin trying to write global rows).
- Base-unit guard trigger: insert with `conversion_to_base=1` but a different `unit_code` than `item.base_unit_code` → rejected.
- `post_receive` with multiple packagings of the same item: `current_stock` rolls up correctly in base units; `avg_cost` weights properly; `shop_item_unit.last_cost` updated per packaging; `supplier_item_unit_cost` upserted.
- `post_sale` with mixed packagings drawing from one pool.
- `void_sale` + `void_receive` reverse lines carry `shop_item_unit_id`.
- `search_items` walks all four sources with the right ranking.
- Negative-stock path: warning fired (verified via session-level `set client_min_messages=NOTICE`).
- Drop ref_translation: all consumers query jsonb.
- shop_item_barcode + item_barcode: scan lookup returns the right shop_item_unit_id, prefers shop barcode over global on conflict.

### Flutter (`flutter test`)

- Sale flow: cart line carries `shop_item_unit_id`; long-press unit switch updates it; SAVE posts correctly.
- Receive flow: 40 × 25 kg bag → SAVE → stock projection visible in product screen.
- Add new item: cashier creates "Eggs", picks unit "piece", adds a "tray of 30" packaging, prices it, sells one.
- Search: typing Somali alias finds item; barcode lookup short-circuits to packaging.
- Void: detail screen renders packaging label on each reversing line.

### Speed contract (per CLAUDE.md)

- Sale 1 item: still ≤ 5 s, 3 taps. The packaging change doesn't add a step.
- Receive 10 lines: still ≤ 90 s. Unit picker now shows packaging size — confirm picker tap latency stays < 100 ms on mid-range Android.

## 13. Risk register

| # | Risk | Trigger | Mitigation |
|---|---|---|---|
| 1 | **Activation race** — two cashiers activate the same item concurrently | `ensure_shop_item` called twice in parallel | Unique index on `(shop_id, item_id)`; RPC retries on conflict and returns the existing row |
| 2 | **`stock_movement.unit_cost` semantics drift** — code accidentally divides by `quantity` instead of `base_quantity` | New posting RPC written from scratch | Harness assertion: 40×25 kg bag at $20 → stock_movement unit_cost = $0.80 |
| 3 | **Avg-cost across packagings** corrupts if keyed on `shop_item_unit_id` | Refactor accident | Schema review: `avg_cost` lives only on `shop_item`. No exceptions |
| 4 | **Default sale unit changed → stale price** — switching default to a packaging with no price | Cashier picks an alternate packaging | `sale_price IS NULL` triggers priceRequired editor (same UX as today) |
| 5 | **Long-press price override scope** | Cashier overrides on a sale line | Override persists on `shop_item_unit`, not `shop_item` — `setShopItemUnitSalePrice` is the writer |
| 6 | **Reverse-entry loses packaging** | Void RPC writes lines without `shop_item_unit_id` | Test: reversal lines copy `shop_item_unit_id` from original |
| 7 | **OCR pipeline mismatch** — current OCR matches text → item_id | OCR processes a bono | Audit pass before pilot. Match should resolve to (shop_item_id, shop_item_unit_id) by combining alias hit + size hint from the line ("25 kg bag") |
| 8 | **Unactivated item missed in search** | Search filters to shop_item only | Search RPC traverses global `item_alias` too; tap auto-activates via `ensure_shop_item` |
| 9 | **`item.is_active` vs `shop_item.is_active` confusion** | Platform deactivates an item the shop still carries | Search filters: `item.is_active AND (shop_item.is_active OR shop_item.id IS NULL)` |
| 10 | **Negative stock toast doesn't fire on web/iOS** | Platform notice handling | RPC raises NOTICE; client surface in Dart `LogConsoleHandler`-style listener |
| 11 | **Reports/reconciliation view break** | Renamed tables | Migration 0013 view update is mandatory; harness asserts view returns rows |
| 12 | **Template-apply explosion** — applying a 200-item template via 200 ensure_shop_item calls is slow | Setup flow | Batch RPC or single transaction with bulk INSERT...ON CONFLICT |
| 13 | **Opening stock entry needs packaging** — cashier counts in "bags" or "kg" | Setup wizard | Inventory adjustment lines take `shop_item_unit_id`, same shape as transaction lines |
| 14 | **Concurrent stock decrement** | Two sales on same item simultaneously | `SELECT FOR UPDATE` on shop_item already in place; harness covers two parallel txns |
| 15 | **Per-supplier last-cost join cost** | Receive search with many suppliers | Index `supplier_item_unit_cost(shop_id, shop_item_unit_id, party_id)`; LATERAL join, not subquery |
| 16 | **Base-unit guard trigger ignored on activation** | Activation copies item_unit rows | Trigger fires on insert too; activation will fail loudly if it ever drifts |
| 17 | **Shop-local item duplication** — cashier types "Eggs" twice creates two `shop_item` rows | No dedup check | UI hint: if `shop_item_display_name` already matches the typed name, warn before create |
| 18 | **Translation jsonb keys uncontrolled** — typos like `"sm"` instead of `"so"` | Admin input | CHECK constraint: `jsonb keys must be in (select code from language)` (enforced via trigger) |
| 19 | **Shop_item_barcode collision with global** | Same EAN scanned | Search rank: shop first, then global, by `is_primary` then `last_used_at` |
| 20 | **Existing data on hosted Supabase** | Pilot already started | Pre-pilot — confirm no real data before edit-in-place. If pilot data exists, switch to additive migrations |

## 14. Open questions for future iteration

These are NOT v1 blockers; they're things to revisit once we have pilot data:

- **Item kind** (`goods` / `service`) — defer until first service flow ships.
- **Variants** (color, flavor) — currently fold into the alias system or use separate `item` rows; revisit if shopkeepers ask.
- **Stock locations** (`location_id` on `stock_movement` already inert) — when multi-location ships.
- **Returns workflow** — separate redesign, builds on void.
- **Promotions / pricing rules** — out of v1 scope.
- **Item bundles / kits** — out of scope.
- **Catalog supply-chain hints** (`platform suggests this supplier for that item`) — future feature; not in v1 schema.
- **Multi-currency per shop** — not in v1.
- **Time-bounded prices** (sale events) — out of scope.
- **Alias auto-promotion** — when 50+ shops have learned the same alias, suggest promoting to global. Background job, post-pilot.
