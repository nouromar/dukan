# Dukan templates and shop learning reference

## 1. Principle

Dukan templates are **shop operating profiles**, not product lists.

A template should preload the shop with the products, settings, shortcuts, aliases, and mappings that make daily entry fast for a low-literacy shopkeeper. The shopkeeper should mostly **tap, confirm, correct, or repeat**. They should rarely type and should almost never make configuration choices during Sale, Receive, Payment, or Expense.

The template is the starting point. The shop then learns from real usage and quietly tunes the profile for that shop.

Performance rule: **compute once, read fast**. If a suggestion or fact can be prepared during posting or a scheduled rebuild, store the ready result instead of making the mobile app repeat threshold/ranking checks on every screen load.

## 2. Modular template pack structure

A shop starter template is a folder of configuration packs composed by `manifest.json`. Do not grow one giant JSON file.

Recommended structure:

```text
templates/grocery/
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
```

| Pack | Contains |
|---|---|
| `manifest.json` | Template identity, version, locale/currency defaults, list of packs |
| `catalog.json` | Product concepts, catalog items, units, base/sale/receive units, conversions |
| `settings.json` | Shop defaults and behavior flags |
| `quick-actions.json` | Sale favorites, expense shortcuts, category ordering |
| `supplier-mappings.json` | Supplier types mapped to likely items and receive defaults |
| `quantity-suggestions.json` | Sale/Receive quantity chips |
| `aliases.json` | Item/supplier aliases for search and OCR |
| `ocr-mappings.json` | Bono labels, matching order, confidence thresholds |
| `expense-categories.json` | Starter expense categories |
| `dashboard.json` | Default dashboard cards and report ordering |

The admin portal should manage these packs as separate areas, even when the end user experiences them as one "Apply Grocery template" action.

## 3. What template packs should contain

### 3.1 Product catalog seed

- Products with English and Somali names for the **product concept** only.
- Natural local Somali product names, not English transliteration.
- Brand, quantity, size, and package/unit attributes are structured fields, not translated name text.
- Base unit, default sale unit, default receive unit, allowed unit conversions, category, suggested sale price, reorder threshold.
- Search aliases in English and Somali.
- Optional visual hints later: icon, color, or simple category image.

Example display-name composition:

- Product concept: `Sugar` → `Sonkor`.
- Quantity/package: `1kg` stays `1kg`.
- Brand: `ABC` stays `ABC`.
- Display: `Sonkor 1kg ABC`, not a fully translated free-text string.

This keeps translations reusable and avoids maintaining separate Somali strings for every brand/pack-size combination.

Template/item setup must also define whether a received package can be split for sale:

- **Not split:** base unit = package unit. Example: a sealed bag sold only as a bag.
- **Split:** base unit = smallest sellable unit. Example: candy received by bag but sold by piece; `1 bag = 100 pieces`.

Daily screens use these settings but do not ask the shopkeeper to configure them.

### 3.2 Setup settings

These are chosen once and not asked again in daily flows:

- Default language.
- Currency.
- Timezone.
- Default sale mode: usually Cash.
- Default receive mode: usually Credit / Pay Later.
- Negative-stock policy: warn vs block.
- Whether debt sale requires a customer.
- Rounding rule.
- Default low-stock threshold.
- Whether to suggest bono photo on Receive.
- Whether to suggest receipt photo on Sale.
- Expense categories.
- Payment methods visible to the shop.

### 3.3 Fast-entry layout

Templates should define what the user sees first:

- Sale favorites grid: top items and their order.
- Receive favorites by supplier.
- Expense shortcut buttons.
- Customer quick list rules: recent debt customers first.
- Category ordering.
- Search ranking defaults.

The goal is that a new grocery shop opens to useful buttons immediately, before it has any history.

### 3.4 Item aliases and matching terms

Each item should have multiple names because users and suppliers will not type consistently:

- Somali name.
- English name.
- Short name.
- Common misspellings.
- Supplier wording from bonos.
- OCR-friendly variants.
- Abbreviations.

These aliases power:

- Type-ahead search.
- OCR matching.
- Duplicate prevention when adding items.
- Future voice or assisted input.

### 3.5 Supplier and customer aliases

Supplier and customer names are often informal. The template should support:

- Formal name.
- Common nickname.
- Phone label.
- Common spelling variants.
- Bono header wording.

This lets the system match `Xawaash`, `Xawash`, a phone number, or an OCR fragment to the same supplier.

### 3.6 Supplier-item mappings

For each common supplier type, the template can preload likely items:

- Supplier category: wholesaler, dairy supplier, beverage supplier, household supplier.
- Items usually bought from that supplier.
- Usual receive unit.
- Conversion to the item's base unit when the receive unit is a package.
- Usual quantity suggestions.
- Usual cost-entry mode: per unit or line total.

This makes Receive faster:

1. Pick supplier.
2. System shows likely items first.
3. Tap "Repeat last bono" or choose from likely items.
4. Edit quantities/costs.
5. Confirm.

### 3.7 Quantity and price chips

For each item or category, the template can suggest common values:

- Sale quantity chips: `1`, `2`, `5`, `0.5 kg`, `1 kg`.
- Receive quantity chips: `1 bag`, `5 cartons`, `10 packets`.
- Unit choices and quantity chips come from item config, template defaults, and supplier-item mappings.
- Price/cost defaults.
- Common override values.

This reduces numeric keypad use. Quantity chips are also a strong candidate for shop-specific adaptation: if a shop repeatedly sells `0.5 kg` sugar or receives `5 cartons` water, those choices should move up and become the default suggestions for that shop.

For split packages, chips should hide the conversion math:

- Receive candy: `1 bag`, `5 bags`, `10 bags`.
- Sale candy: `1 piece`, `2 pieces`, `5 pieces`, `1 bag`.
- System converts all chips to base stock units before posting.

### 3.8 OCR mappings

The template should prepare OCR to be useful before AI is perfect:

- Common bono labels: supplier, date, item, qty, price, total.
- Supplier aliases.
- Item aliases.
- Unit aliases.
- Confidence thresholds for auto-select vs show as suggestion.

OCR should create a draft, never auto-post. The user confirms.

### 3.9 Dashboard and report defaults

Templates should hide reports that are not useful for the shop kind and show the important ones first:

- Today sales.
- Cash collected.
- Customer debts.
- Supplier payables.
- Low stock.
- Simple profit.

## 4. How the system learns from shopkeeper choices

Start with simple deterministic techniques. They are easier to debug, safer for trust, and usually enough for v1.

### 4.1 Recency and frequency ranking

Show what the shop used recently and often:

- Recent sale items first.
- Frequent sale items in the favorites grid.
- Recent suppliers first on Receive.
- Recent debt customers first when choosing Debt.

Technique: maintain counts and last-used timestamps per shop, then write ready-to-read suggestion rows with a precomputed rank.

### 4.2 Adaptive defaults

Remember the user's repeated choices and make them defaults:

- Last sale price for an item.
- Usual quantity sold.
- Usual receive cost for an item from a supplier.
- Whether this item is normally entered by unit cost or line total.
- Whether this supplier is usually paid now or later.

Technique: update a per-shop profile after each confirmed transaction. Promote learned defaults into the ready suggestion list only after simple repeated-use checks; the app should not run those checks during screen loading.

### 4.3 Human-in-the-loop correction learning

When the user corrects a suggestion, save the correction:

- OCR text `sonkor cad` matched to Sugar.
- Supplier spelling corrected to a known supplier.
- New alias entered during search.
- Item selected after a failed search.

Technique: write the correction to `item_alias`, `party_alias`, or an OCR correction table so the same mistake is not repeated.

### 4.4 Fuzzy matching

Match imperfect text:

- Misspellings.
- Somali/English variants.
- OCR errors.
- Missing spaces or punctuation.

Techniques:

- Text normalization: lowercase, trim spaces, remove punctuation.
- PostgreSQL `pg_trgm` similarity.
- Levenshtein distance for short strings.
- Alias tables per shop.
- Confidence scoring with safe thresholds.

### 4.5 Contextual ranking

The best suggestion depends on where the user is:

- In Sale, show items sold often.
- In Receive, show items bought from the selected supplier.
- In Expense, show recent expense categories.
- For Debt, show customers who recently bought on debt.

Technique: ranking rules include context: screen, supplier, customer, time of day, transaction type.

### 4.6 Exponential decay / weighted moving averages

Old behavior should slowly matter less than new behavior:

- If a shop stops selling an item, it should drift down.
- If a supplier changes prices, the latest costs should matter more.

Technique: use exponentially weighted moving averages for quantities, prices, costs, and item popularity.

### 4.7 Active learning prompts

Ask tiny questions only when they pay off:

- "Always use this name for this item?"
- "Move this item to favorites?"
- "Use line total for this supplier next time?"

These prompts should be rare, plain-language, and dismissible. Never interrupt a busy Sale or Receive.

### 4.8 Anomaly warnings

Warn when an entry looks unusual:

- Receive cost much higher than usual.
- Selling price below average cost.
- Quantity unusually high.
- Supplier total does not match line total.

Technique: compare against the shop's learned averages and use non-blocking warnings unless data would be impossible.

### 4.9 Cross-shop template improvement

Later, aggregate anonymized learnings across pilot shops to improve the base templates:

- New common aliases.
- Better default favorite grids.
- Better category ordering.
- More realistic prices.
- Common supplier types.

This should be opt-in or privacy-safe aggregate telemetry. Do not expose one shop's private supplier/customer behavior to another shop.

### 4.10 Machine learning / recommender systems

More advanced options exist, but they should come later:

- Collaborative filtering: shops like this also use these products.
- Contextual bandits: test which shortcut ordering saves the most taps.
- Learning-to-rank: rank item suggestions from many signals.
- OCR model fine-tuning: improve text extraction or parsing from real bonos.

For Dukan v1, prefer transparent rules first. ML is only useful if it reduces taps without reducing trust.

## 5. Recommended v1 implementation

### 5.1 Template-backed defaults

Add these concepts to the platform template layer:

- `template_setting`: default shop settings.
- `template_quick_action`: Sale/Receive/Expense shortcut layouts.
- `template_item_alias`: extra names and OCR terms.
- `template_party_alias`: supplier/customer aliases where known.
- `template_supplier_item`: likely item mappings by supplier type.
- `template_quantity_suggestion`: common quantity chips.
- `template_entry_preference`: default cost-entry mode and behavior hints.

These seed shop-scoped rows when `apply_template()` runs.

### 5.2 Shop learning profile

Keep learned data shop-scoped:

- `shop_item_usage`: sale/receive counts, last used, rank score.
- `shop_item_entry_profile`: usual sale quantity/unit, usual price, usual receive quantity/unit/cost.
- `shop_supplier_item_profile`: items usually received from supplier, usual quantities, cost mode.
- `shop_party_usage`: recent/frequent customers and suppliers.
- `shop_suggestion`: precomputed active suggestions for each screen/context, with source, rank, usage count, and last used time.
- `shop_quick_action`: manual/setup-pinned favorites grid overrides.
- `ocr_correction`: raw text, accepted match, confidence, source document.

These are not accounting truth. They are UX acceleration data only.

### 5.3 Precomputed suggestion rule

The app should read suggestions with a simple query:

```
where shop_id = current shop
  and screen/context matches
  and is_active = true
order by rank
limit small number
```

Ranks are computed during posting RPCs or scheduled rebuild jobs. Use simple ordering for v1: manual/setup-pinned rows first, learned rows after repeated use, template rows as fallback, and most-recently-used as a tie-breaker. Keep the rule explainable so support can understand why an item appears.

### 5.4 Safety rules

- Never auto-post a transaction from learned data.
- Never silently change price, cost, quantity, stock, or balance.
- Learned suggestions are defaults, not truth.
- Shopkeeper confirmation wins.
- Corrections should improve future suggestions.
- Support can tune setup/profile data, but cannot post transactions.

## 6. UX acceptance criteria

The learning system is successful only if it reduces work:

- Sale: common items appear without search.
- Receive: after supplier selection, likely items appear first.
- OCR: corrected aliases improve future matching.
- Expense: common categories are one tap.
- The user can ignore suggestions and still complete the task.
- No daily flow becomes a settings screen.

If a learning feature is hard to explain to a shopkeeper, it is probably too complex for v1.
