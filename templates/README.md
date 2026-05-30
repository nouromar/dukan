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
```

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
