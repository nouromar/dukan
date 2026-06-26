# Dukan shop starter templates

Templates are **composable operating profiles**, not one large product list.

Each shop-kind template is a folder with a `manifest.json` plus independent configuration packs. The packs are applied together during onboarding, but each pack can be managed, reviewed, versioned, and improved separately.

## Current templates

The only shipped templates are the two Dukaan Cunto starters below. (Grocery was
removed as a shop-starter; its multi-unit catalog now lives solely as a backend-harness
test fixture at `scripts/fixtures/grocery_fixture.sql`, never shipped.)

```text
templates/
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

Two sibling starter templates whose content is a **deletable/editable seed**, not a migration:
`supabase/seeds/templates/dukaan_cunto.sql`.

- **`test_dukaan_cunto`** — full catalog (~77 items + quick actions), for seeding test shops.
- **`empty_dukaan_cunto`** — settings + expense categories only, **no inventory / no quick
  actions**, for onboarding a real shop from scratch.

Both appear in the in-app "Choose your shop type" setup step (they're `is_active`), so testers
pick one during signup — no pre-created shops needed.

**Why a seed, not a migration:** template content is something you add, edit, and *delete*,
unlike the append-only migration stream. Seeds load after migrations on local `supabase db
reset` (via `config.toml [db.seed]`), but **`db push` to hosted does NOT run seeds** — so load
these test templates explicitly per environment (staging/beta only, never production). To drop
them: delete the seed file and `delete from public.template where code like '%dukaan_cunto'`.

The catalog is authored in `dukaan-cunto-catalog-review.csv`; after editing it (e.g. prices),
re-run `python3 templates/tools/gen_dukaan_cunto.py` to regenerate the seed + JSON specs (output
is deterministic). The apply path is covered by `§DC` in `scripts/test-backend-migrations.sh`.

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
for d in test_dukaan_cunto empty_dukaan_cunto; do
  for f in "$d"/*.json; do python3 -m json.tool "$f" >/dev/null || exit 1; done
done
```

## Update rules

- Increment the relevant pack `version` when changing a pack.
- Increment `manifest.json` when adding/removing packs or changing the composed template.
- Treat item `code` values as idempotency keys; do not rename them casually.
- Template updates do **not** silently overwrite shop-edited rows.
- Learned shop behavior can improve shop-specific suggestions first, then be promoted to catalog/template packs only after review.
