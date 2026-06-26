# Dukan shop starter templates

Templates are **composable operating profiles**, not one large product list.

Each shop-kind template is a folder with a `manifest.json` plus independent configuration packs. The packs are applied together during onboarding, but each pack can be managed, reviewed, versioned, and improved separately.

## Current templates

```text
templates/
  grocery.json                 # legacy v1 single-file snapshot
  grocery/
    manifest.json
    catalog.json
    settings.json
    quick-actions.json
    supplier-mappings.json
    quantity-suggestions.json
    aliases.json
    ocr-mappings.json
    expense-categories.json
    dashboard.json
    _legacy-grocery-v1.json    # copy of the old single-file template
  test_dukaan_cunto/           # Somali dukaan cunto — full catalog (~77 items)
    manifest.json
    catalog.json
    settings.json
    expense-categories.json
    quick-actions.json
  empty_dukaan_cunto/          # Somali dukaan cunto — config only, no inventory
    manifest.json
    settings.json
    expense-categories.json
  dukaan-cunto-catalog-review.csv  # authoring source for the dukaan cunto catalog
  tools/
    gen_dukaan_cunto.py        # regenerates 0017 + dukaan cunto specs from the CSV
```

## Dukaan Cunto templates (Somali grocery)

Two sibling starter templates seeded by `supabase/migrations/0017_seed_dukaan_cunto.sql`:

- **`test_dukaan_cunto`** — full catalog (~77 items + quick actions), for seeding test shops.
- **`empty_dukaan_cunto`** — settings + expense categories only, **no inventory / no quick
  actions**, for onboarding a real shop from scratch.

Both appear in the in-app "Choose your shop type" setup step (they're `is_active`), so testers
pick one during signup — no pre-created shops needed. The catalog is authored in
`dukaan-cunto-catalog-review.csv`; after editing it (e.g. prices), re-run
`python3 templates/tools/gen_dukaan_cunto.py` to regenerate the migration + JSON specs (output
is deterministic). The `0017` apply path is covered by `§DC` in `scripts/test-backend-migrations.sh`.

## Pack responsibilities

| Pack | Purpose |
|---|---|
| `manifest.json` | Template identity, version, locale/currency defaults, and list of packs to apply |
| `catalog.json` | Product concepts, catalog items, units, base/sale/receive units, and unit conversions |
| `settings.json` | Shop defaults: language, USD, sale/receive payment defaults, negative-stock policy |
| `quick-actions.json` | Sale favorite buttons, expense shortcuts, and category ordering |
| `supplier-mappings.json` | Supplier types mapped to likely receive items and cost-entry defaults |
| `quantity-suggestions.json` | Sale/Receive quantity chips, seeded by template and later adapted per shop |
| `aliases.json` | Item aliases and supplier alias examples for search/OCR matching |
| `ocr-mappings.json` | Bono label hints, matching order, and confidence thresholds |
| `expense-categories.json` | Starter expense categories in English and Somali |
| `dashboard.json` | Default dashboard cards and reports |

## Grocery pack status

- Catalog items: **131**
- Unit-conversion examples: **2**
- Sale favorites: **40**
- Quantity suggestions: **949**
- Supplier-item mappings: **110**
- Expense categories: **10**

## Catalog naming rule

Translate only the **product concept** and description.

Brand, quantity, size, and package/unit attributes stay structured and are not translated as full free-text names.

Example:

```text
Concept EN: Sugar
Concept SO: Sonkor
Brand: ABC
Package: 50kg
Display SO: Sonkor ABC 50kg
```

## Unit conversion rule

Stock is tracked in the item's **base unit**.

- If a package is never split, base unit can be the package unit.
- If a package is split for sale, base unit is the smallest unit the shop sells.

Example:

```text
Candy ABC
Base unit: piece
Receive unit: bag
Sale units: piece, bag
Conversion: 1 bag = 100 pieces
```

The shopkeeper enters `10 bags` on Receive or `3 pieces` on Sale. The system handles conversion behind the scenes.

## Validation

Run:

```bash
cd ~/dukan/templates
python3 -m json.tool grocery/manifest.json >/dev/null
for f in grocery/*.json; do python3 -m json.tool "$f" >/dev/null || exit 1; done
```

## Update rules

- Increment the relevant pack `version` when changing a pack.
- Increment `manifest.json` when adding/removing packs or changing the composed template.
- Treat item `code` values as idempotency keys; do not rename them casually.
- Template updates do **not** silently overwrite shop-edited rows.
- Learned shop behavior can improve shop-specific suggestions first, then be promoted to catalog/template packs only after review.
