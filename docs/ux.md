# UX — Dukan Shop Management App

> **North-star principle:** UX is the #1 success factor. The target user is a shopkeeper who is **not a tech-savvy user**. If a flow is not obvious in 5 seconds, or fast enough to beat their handwritten notebook, the design has failed — regardless of how correct the backend is.
>
> **Corollary — decision-free daily use:** every decision is made **once, at setup**, either by support staff or via a one-tap template. Daily flows (Sale, Receive, Payment, Expense) must contain **zero configuration questions**. If a setting could be asked daily, move it to setup; if it could be asked at setup, prefer a template default.

This doc is the canonical reference for product, design, and engineering. Any new feature must conform to the speed contract and interaction rules below, or get an explicit exception. See **`ux-screens.md`** for the complete screen inventory, Level A screen flows, and bottom-sheet patterns.

---

## 1. Who we are designing for

- Shopkeepers in small neighbourhood shops. Often one person serving customers, taking money, and tracking stock simultaneously.
- Primary language **Somali**, working knowledge of **English** varies widely.
- Low formal tech experience: comfortable with WhatsApp, voice notes, and a phone camera; less comfortable with forms, menus, and "wizards".
- Phone is **mid-range Android, often one-handed** while the other hand holds money, items, or a pen.
- Connectivity is mostly OK but not perfect — the app must feel instant regardless.

**Design implication:** every screen must work for someone who is busy, distracted, possibly mid-conversation with a customer, and not in the mood to read.

---

## 2. The speed contract (north-star metrics)

These are non-negotiable acceptance criteria for v1. A flow that misses them is broken.

| Flow | Target time | Max taps |
|---|---|---|
| Sale, 1 item, cash | **≤ 5 seconds** | 3 taps from home |
| Sale, 5 items, cash | **≤ 20 seconds** | 7 taps from home |
| Sale on debt (existing customer) | **≤ 12 seconds** | 5 taps |
| Receive, 10-line bono (manual) | **≤ 90 seconds** | — |
| Receive, 10-line bono (OCR draft, v1.5) | **≤ 30 seconds** | — |
| Record an expense | **≤ 10 seconds** | 4 taps |
| Record a customer payment | **≤ 10 seconds** | 4 taps |
| App cold start to home screen | **≤ 3 seconds** | — |
| Any tap → visible response | **≤ 100 ms** | — |

Measured on a real mid-range Android (e.g., a 2023 sub-$200 device), one-handed thumb use, with realistic data (200 items, 30 active customers).

---

## 3. Universal interaction rules

These apply to every screen.

1. **One screen per task.** No wizards. A sale, a receive line, an expense, a payment — each fits on one screen.
2. **Confirm IS the summary.** Don't add a separate review step; the live "cart" / total strip on the same screen is the review.
3. **Numeric input is always the OS big numpad**, never the alphanumeric keyboard.
4. **No typing of units, currency, dates, or category names — ever.** They are picked, defaulted, or auto-formatted.
5. **Defaults are sacred.** Today's date, this shop's currency, cash, "credit" for receives, item's default price. The fastest tap is no tap.
6. **Type-ahead everywhere** with **recents on top** and **aliases** (Somali + English + abbreviations). Two keystrokes should usually be enough.
7. **Tap = the normal path. Long-press = power.** Quantity > 1, price override, line notes, etc. live behind long-press so the simple path stays clean.
8. **Optimistic save with 10-second undo.** Never block on the network. A toast "Saved. Undo?" replaces blocking confirm dialogs.
9. **No icon without a text label.** Pictures help, but a labeled icon is faster to learn than a mystery glyph.
10. **Two languages always one tap away** at the top of every screen. *All* strings translated — button labels, errors, inline help — not just menus.
11. **Empty states teach.** First-time screens show a 3-step illustrated hint that disappears after the first successful action.
12. **Errors are warnings, not blockers, whenever possible.** "Bono says 220, lines add to 218 — that's OK?" beats a red modal that traps the user.
13. **Big tap targets** (≥ 56dp). Thumb-reach matters; primary actions live in the bottom third of the screen.
14. **No required fields that aren't truly required.** Items need name + unit, suppliers/customers need name + phone. Everything else is optional.
15. **Daily flows ask zero configuration questions.** Anything that could be a "setting" lives in Setup, not in the flow. Defaults come from the shop's template.
16. **Reduce clutter aggressively.** Daily screens show only the next obvious action and the live result. Secondary choices, search, filters, supplier/customer picking, and advanced options live in bottom sheets or focused modals so the main screen stays calm.

---

## 3a. Setup-first philosophy (decision-free daily use)

The single biggest UX lever is **removing decisions from the daily path**. Two mechanisms carry the load:

### One-tap templates (Settings → "Set up my shop")
A new shop picks **one** shop-kind template (Grocery, Restaurant, Pharmacy, Hardware, Electronics, Clothing). One tap seeds:
- 50–150 typical items (name in en + so, unit, suggested sale price, reorder threshold).
- Expense categories (Rent, Electricity, Salary, Water, Internet, Transport, Other).
- Units (piece, kg, gram, litre, ml, bag, box, carton, bottle, packet).
- Adjustment reasons (Opening stock, Spoilage, Correction).
- A default receipt layout.
- Default behaviours (cash for sales, credit for receives, warn-on-negative-stock, require-customer-for-debt).
- Fast-entry mappings: aliases, favorite sale buttons, supplier-item mappings, common quantity chips, and cost-entry defaults.

The shop can edit, rename, or disable any seeded row — but never has to invent from scratch. Templates are **versioned** so newly-onboarded shops always get the latest pack without disrupting existing ones.

After setup, Dukan should learn from confirmed shopkeeper choices: recent/frequent items move up, supplier-specific receive items appear first, corrected OCR text becomes an alias, and repeated quantities/prices become suggestions. Suggestions should be precomputed where practical so screens stay fast. These are suggestions only; learned data must never auto-post or silently change stock/money. See `templates-and-learning.md`.

### Concierge / support-assisted setup (and occasional follow-up support)
The same help channel is used for both **initial setup** and **occasional follow-up support** later (e.g., shopkeeper asks for help adding an expense category, renaming items, or fixing a setting). It is *not* a one-time onboarding feature.

- **V1 support channel:** a visible Help icon opens WhatsApp chat and email support.
- **No in-app support codes in v1:** do not build the 6-digit support-code flow for the pilot.
- Support guidance is out-of-band in v1; support can talk the shopkeeper through changes or update setup/template data through internal/admin tools where permitted.
- If in-app support sessions are added later, they must be time-bounded, setup-scoped only, and audit-logged. Support still cannot post sales/receives/payments/voids.

### What is decided at setup (and never asked again)
Shop name, currency, timezone, default language, default sale terms (cash/credit), default receive terms, negative-stock policy (warn vs block), whether to ask for a receipt photo after sale, low-stock threshold default, currency rounding rule, whether to require a customer for debt sales, optional single tax rate, opening stock.

### What is deliberately not configurable
No theme/color customisation, no layout/column choices on lists, no "advanced mode" toggle, no multiple receipt templates per shop, no custom transaction types. **Fewer settings = fewer ways to get stuck.**

---

## 4. Sale screen (the most frequent flow)

Single screen, three zones.

```
┌─────────────────────────────────────────┐
│  🔍 search                  EN | SO     │  top: search + language
├─────────────────────────────────────────┤
│  ⭐ Favorites — big icon grid           │
│  ┌─────┬─────┬─────┬─────┐              │
│  │Rice │Sugar│Oil  │Tea  │              │
│  │25kg │ 1kg │ 1L  │250g │              │  tap = +1 to cart
│  └─────┴─────┴─────┴─────┘              │  long-press = qty/price
│  ┌─────┬─────┬─────┬─────┐              │
│  │ ... │ ... │ ... │ ... │              │
│  └─────┴─────┴─────┴─────┘              │
├─────────────────────────────────────────┤
│  CART  3 items                  72.00   │  always-visible cart strip
│  [💵 CASH ✓]  [📝 DEBT]   [ CONFIRM ▶]  │
└─────────────────────────────────────────┘
```

**Interaction details:**
- Tap an item = +1 to cart. Picker stays open. Five items = five taps.
- Long-press an item = numpad for quantity (and optional per-line price override).
- Search is fuzzy + alias-aware (`bariis 25` → "Basmati Rice 25kg").
- **Cash is the default**; Debt is one tap that *also* opens inline customer search.
- **Partial payment** (cash + remainder on credit) is a power option: **long-press on the CASH/DEBT toggle** opens a slider for "amount paid now". Hidden from the simple path.
- Tap CONFIRM → optimistic save → toast "Saved. Undo?" (10s) → screen resets ready for next sale.
- Optional receipt photo via a small camera icon next to CONFIRM. Never required.
- Favorites auto-order by last-7-days frequency; manual pin override.

**Explicit non-features in the sale flow:**
- No category navigation.
- No unit picker (unit is fixed per item).
- No tax field.
- No customer required for cash.
- No multi-screen review.
- No barcode UI in v1.

---

## 5. Receive screen (batches of lines from a paper bono)

**Step 1 — supplier first** (≈ 5s). Most-recent suppliers as large chips at the top; type-ahead below. `+ New supplier` inline (name + phone only). *Why supplier-first and not camera-first: opening the camera on tap one triggers an OS permission prompt that derails first-time users and is jarring at every subsequent open. Picking the supplier first also lets us pre-rank items, aliases, and "repeat last bono" content for the next step.*

**Step 2 — snap the bono** (≈ 5s, optional but strongly defaulted). Large camera button at the top of the line-entry screen, labelled **"📷 Add bono photo"**. Photo attached to the receive (record in v1, OCR draft input in v1.5). **Skip path:** small "I don't have a bono" link beneath the camera button — never blocks the receive (rule: no truly-required fields). Suppliers/owners are reminded once that bonos enable OCR auto-fill later.

**Step 3 — lines.** One-screen line entry; after Add, focus jumps to the next line's item search so 10 lines feels like 10 quick rows.

```
┌─────────────────────────────────────────┐
│  ← Receive from XAWAASH                 │
│  📷 Bono attached                       │
├─────────────────────────────────────────┤
│  Item:   [ Bariis 25kg          ▼ ]     │  type-ahead, aliases, recents
│  Qty:    [   4   ]   Unit: bag (fixed)  │  big numpad
│  Cost:   [ 18.00 ] per bag  ⇄  line     │  per-unit ↔ line-total toggle
│  Line total:  72.00                     │  auto-computed
│  [   + ADD LINE   ]                     │  big primary action
├─────────────────────────────────────────┤
│  Lines so far: 3        Total: 218.00   │  running total
└─────────────────────────────────────────┘
```

**Speed tricks:**
- **"Repeat last bono from this supplier"** button on the supplier screen pre-fills the typical lines, ready for quantity edits. Collapses 10 typed lines into 10 quantity edits.
- **Cost toggle** (per-unit ↔ line-total) per line; the other side is auto-computed. Removes "is this per bag or total?" hesitation.
- After **Add line**, the form clears to the item search with focus already in the box.
- Bono total field on Confirm is **a soft check**, not a blocker. Mismatch → warning, not error.
- **Paid now / on credit** is one slider on Confirm — default **0 paid** (most receives are on credit). One tap to switch to "Paid all".
- Inline `+ New item` from the item search: name + unit + last cost (defaulted from the cost field). Nothing else required.

---

## 6. Payments, expenses, customers (secondary flows)

Same rules. Each is one screen.

- **Customer payment:** pick customer → type amount → CONFIRM. Default allocates to oldest debt; long-press to allocate manually (power user).
- **Supplier payment:** mirror of above.
- **Expense:** pick category (large icon chips: Rent, Power, Salary, Other) → type amount → CONFIRM. Optional photo.

---

## 7. Language & copy rules

- **Somali is a first-class language**, not a translation afterthought. All copy is reviewed by a native Somali shopkeeper before pilot, not just any translator.
- Plain words only. No accounting jargon ("receivable", "ledger", "post"); use "money customer owes", "saved", etc., in both languages.
- Numbers, dates, and currency are auto-formatted to the shop's locale — user never types separators or symbols.
- Error and warning copy is **action-oriented**: "Take a photo of the bono" beats "Document required".
- Button verbs over nouns: **SAVE**, **CONFIRM**, **ADD LINE**, not "Sale" or "Receipt".

---

## 8. Accessibility & device reality

- Designed for **one-handed thumb use**; primary actions in the bottom third of the screen.
- High contrast, large default font, system font scaling respected.
- Works in bright outdoor light (high-contrast theme, not minimal grey-on-grey).
- Tap targets ≥ 56dp; spacing prevents misfires.
- Works on a mid-range 2023 Android with 3 GB RAM and a 720p screen.
- Survives 30+ second network blips without losing the user's input.

---

## 9. Anti-patterns we will reject

- Multi-screen wizards for routine entry.
- Modal-on-modal dialogs.
- Required fields not strictly necessary for the operation.
- Alphanumeric keyboard popping up for numeric input.
- Confirm dialogs after every tap.
- "Are you sure?" before destructive actions — use undo instead.
- Generic icons without labels.
- Tiny tap targets on dense list rows.
- Synchronous "loading…" spinners on user actions — use optimistic saves.
- Side menus / hamburger navigation for primary tasks. Primary tasks live on the home screen as big buttons.

---

## 10. Process: how we keep UX honest

1. **Prototype before backend.** Sale and Receive flows are built as clickable Flutter prototypes wired to mock data **before** the posting backend (Phase 1.5 in the plan).
   - Use `ux-screens.md` as the screen inventory for prototype coverage.
2. **Real shopkeeper testing.** Sit with **2–3 actual shopkeepers** in Somali. Time them against the speed contract. Iterate until the metrics are hit.
3. **Speed audits per release.** Record a screen capture of a real sale and receive. Any hesitation > 2 seconds on a step is a bug, not a feature gap.
4. **No new feature ships** without checking it doesn't slow down the Sale or Receive flow. A "small addition" that adds one tap to a flow done 200 times a day is a major regression.
5. **Track the metrics in the field.** Instrument the app to log p50/p95 time-to-complete for Sale and Receive; review monthly.

---

## 11. Open UX decisions

- **Customer/supplier name display:** full name vs phone last-4 vs both?
- **Receipt photo storage:** show thumbnail on past sales list, or hide behind a "view" tap to keep the list dense?
- **Voice input** (e.g., quantity dictation) — likely useful for one-handed receive entry; assess after first usability test.
- **Daily close / cash count** screen for end-of-day reconciliation — add to v1 if shopkeepers ask for it in usability tests.
- **Print to thermal printer (Bluetooth)** — assess pilot demand.
