# Bono OCR + Receive Prepopulate — Design

> **Design contract** for the bono-photo OCR pipeline and the prepopulate UX it powers in the Receive flow. This document is the source of truth for what gets extracted, who/what runs it, how the cashier interacts with the suggestions, and how the system learns supplier-specific quirks over time. The implementation lands as tasks `#260`–`#264` (see § 14). Companion documents:
>
> - `docs/mobile-app.md` § 7 — the Receive flow this design enhances.
> - `docs/ux.md` — the speed contract and binding interaction rules.
> - `docs/architecture.md` § OCR pipeline — high-level placement.
> - `docs/backend-schema.md` § documents/OCR — the `document` / `ocr_job` / `ocr_correction` tables.
> - `docs/templates-and-learning.md` — the `ocr-mappings.json` pack each template seeds with.

---

## 1. Purpose

The Receive flow's binding speed-contract entry is: **10-line bono manual entry in ≤ 90 s**. With a bono photo already on hand, the cashier is doing data entry the OCR could mostly do for them.

Concretely the cashier today does, line by line:

1. Read the supplier's printed/handwritten name for an item.
2. Mentally translate it to the shop's name (e.g. supplier writes "BSMTI 25KG" → cashier knows that's "Bariis Basmati 25 kg").
3. Type-search until the right item surfaces, tap it.
4. Pick the packaging (25kg bag).
5. Type the quantity.
6. Type the per-unit cost (or line total).
7. Repeat × 10.

A correctly OCR'd bono collapses steps 1–6 to "the line is already there; tap to accept, edit if wrong." Target: **10-line OCR'd bono in ≤ 15 s of cashier time** (most of which is glancing at each line to confirm).

This is the single highest-leverage UX gain available before pilot. It also produces a structured supplier-specific learning record that every subsequent bono from the same supplier benefits from.

---

## 2. Non-goals

Pinned upfront so scope creep gets caught:

1. **Not a perfect-vision system.** The cashier always reviews; we never post a receive without an explicit cashier tap-through. OCR is a draft, not a final.
2. **Not handwriting-perfect.** Vision handles printed bonos reliably and handwritten ones with degraded accuracy. We surface confidence honestly; we don't pretend.
3. **Not a no-photo path.** A cashier without a bono photo continues to enter manually — this design is additive.
4. **Not a returns / refunds path.** Bono OCR is only for `post_receive`. Returns are out of v1 entirely.
5. **Not a Sale-side feature.** Sales are point-of-sale; the customer rarely brings a "menu" the system can OCR.
6. **Not a multi-page PDF.** v1 is one image per bono. Multi-page bonos are stitched client-side or ignored.
7. **Not for shopkeeper KYC documents** or any non-bono image. Scope is locked to `document_type = 'bono'`.

---

## 3. Current state (honest accounting)

This is what exists today (as of `0053`):

| Layer | Status |
|---|---|
| Mobile bono capture (camera/gallery) | ✓ shipped — `lib/shared/bono_image_picker.dart` |
| Mobile upload to Storage | ✓ shipped — `ShopApi.uploadBonoImage()` |
| `create_bono_document` RPC | ✓ shipped — migration `0034` |
| Receive screen attaches `document_id` | ✓ shipped — `receive_screen.dart:462` |
| `document` table with `ocr_result jsonb` | ✓ shipped — migration `0008` |
| `ocr_status` reference table | ✓ shipped — migration `0008` |
| `ocr_job` queue table with attempts/locking | ✓ shipped — migration `0008` |
| `ocr_correction` for learning | ✓ shipped — migration `0008` |
| Template `ocr-mappings.json` seed | ✓ shipped — `templates/grocery/` |
| **Edge function calling Vision API** | ✗ **missing** |
| **Job dispatcher (trigger / cron)** | ✗ **missing** |
| **Result → suggested-line RPC** | ✗ **missing** |
| **Supplier-specific learning table** | ✗ **missing** |
| **Mobile prepopulate UX** | ✗ **missing** |
| **Backend harness coverage** | ✗ **missing** |

The schema is set up well. Everything from the network call upward is unbuilt.

---

## 4. Design overview

Six pieces, layered so the cashier path never blocks on the OCR path:

1. **Async pipeline.** Bono uploads → Claude Haiku 4.5 (multimodal) parses the image directly into structured JSON in the background → result lands in `document.ocr_result`. The cashier never waits.
2. **Progressive enhancement on Receive.** The cashier starts typing lines manually the moment they pick the supplier; if/when OCR finishes, a non-intrusive banner appears: *"5 lines suggested from the bono."* Tap to review; ignore to keep typing. Already-entered lines are merged, not overwritten.
3. **Supplier-aware mapping.** A new table `supplier_item_alias` learns "this supplier's text X maps to this shop's item Y" from cashier corrections. Subsequent OCR results from the same supplier auto-bind high-confidence suggestions.
4. **Confidence-driven UI.** Three states per suggested line: green (auto-checked, ready to accept), yellow (auto-checked but verify), red (unchecked, requires cashier choice).
5. **Correction → learning loop.** Every cashier correction writes one `ocr_correction` row. A nightly job (or live trigger) promotes high-confidence corrections into `supplier_item_alias`.
6. **Graceful degradation.** OCR fails / times out / returns garbage → the banner never appears → cashier enters manually. Silent fallback. Nothing breaks.

---

## 5. Pipeline architecture

```
Cashier taps "📸 Bono"
        │
        ▼
[Mobile] bono_image_picker → uploadBonoImage()
        │
        ▼
[Storage] PUT shop-documents/{shop_id}/documents/{doc_id}/image.jpg
        │
        ▼
[Backend] create_bono_document RPC
        │  • Inserts document row
        │  • Inserts ocr_job row (status='queued')
        │  • Returns doc_id immediately (mobile not blocked)
        ▼
[Edge Function] ocr-bono — invoked via:
        │  - pg_net call from create_bono_document trigger (preferred), or
        │  - Supabase Realtime → mobile triggers Edge via REST (fallback)
        │
        │ 1. Loads document row + shop context (name, top items,
        │    known supplier names) — passed into the prompt for priming.
        │ 2. Signs a 60s Storage URL for the image.
        │ 3. Calls Anthropic Messages API: model=claude-haiku-4-5,
        │    multimodal (image + text), forced tool-use with the
        │    BONO_SCHEMA so the response is strictly valid JSON.
        │ 4. Validates the returned JSON against the schema (defensive
        │    second-pass; the model is constrained by tool_choice but
        │    we validate anyway).
        │ 5. UPSERTS ocr_result jsonb on document.
        │ 6. UPDATE ocr_job SET status='success'.
        ▼
[Mobile] Receive screen polls (or Realtime-subscribes) document.ocr_status
        │
        ▼
When ocr_status flips to 'success':
        │
        ▼
[Mobile] suggest_receive_lines_from_bono(document_id) RPC
        │  Returns array of (suggestion):
        │    raw_text, suggested_shop_item_unit_id?, quantity, unit_price?,
        │    confidence ('high'|'med'|'low'), reason
        │
        ▼
[Mobile] Banner: "5 lines suggested" → tap → review sheet → accept/edit
```

**Why async + progressive:** Claude Haiku 4.5 vision latency is typically 3–7 seconds, 12 s p95. Blocking the cashier on that violates the 100 ms tap-response budget and the 90 s 10-line-bono ceiling. Asynchronous + progressive enhancement means the cashier is productive immediately; OCR catches up.

**Why an LLM and not Vision API + custom parser?**

| Concern | Vision + parser | LLM (Haiku 4.5) |
|---|---|---|
| Printed bonos, clean layout | Excellent | Excellent |
| Handwritten bonos | Text extracted but **table structure breaks** — column bboxes wander, parser fails | Handles natively — the model "sees" rows like a human |
| Supplier-template variation | Each new template either works or doesn't | Adapts per-image |
| Mixed Somali / English / Arabic | OK on text, brittle on layout | Native multilingual |
| Shop-context priming | None — pixels in, text out | We pass shop name, known suppliers, top item names as prompt context |
| Implementation surface | ~500 lines of TS (column detection, reconciliation, edge cases) | ~80 lines of TS (build prompt, call, validate schema, store) |
| Cost per bono | $0.0015 | $0.004 |
| Total at 30k bonos/month pilot | $45/month | $120/month |

The handwriting + layout-variation cases are the deciding factor. Small Somali shops will receive a mix of printed and handwritten bonos; the parser path silently degrades on the handwritten ones (no banner appears), the LLM path handles them.

**Why not synchronous OCR?** A connectivity blip → cashier locked staring at a spinner. Off-pattern from the rest of the app (which is optimistic-SAVE everywhere). Speed contract loss.

---

## 6. Backend changes

### 6.1 Schema — `supplier_item_alias`

New table. Learned per (shop, supplier_party, raw_text) → preferred item + packaging.

```sql
create table public.supplier_item_alias (
  id                  uuid primary key default extensions.gen_random_uuid(),
  shop_id             uuid not null references public.shop(id) on delete cascade,
  supplier_party_id   uuid not null,
  raw_text_norm       text not null,   -- normalized (upper/strip-punct/collapse-ws)
  shop_item_id        uuid not null,
  shop_item_unit_id   uuid not null,
  confirm_count       integer not null default 1 check (confirm_count >= 1),
  last_confirmed_at   timestamptz not null default pg_catalog.now(),
  created_at          timestamptz not null default pg_catalog.now(),
  updated_at          timestamptz not null default pg_catalog.now(),
  unique (shop_id, supplier_party_id, raw_text_norm),
  foreign key (shop_id, supplier_party_id) references public.party(shop_id, id) on delete cascade,
  foreign key (shop_id, shop_item_id)      references public.shop_item(shop_id, id) on delete cascade,
  foreign key (shop_id, shop_item_unit_id) references public.shop_item_unit(shop_id, id) on delete cascade
);

create index supplier_item_alias_lookup_idx
  on public.supplier_item_alias (shop_id, supplier_party_id, raw_text_norm);
```

`confirm_count` lets us rank conflicting mappings ("supplier called this BSMTI 25 four times → rice; called it BSMTI once → couscous" — rice wins).

### 6.2 Edge function — `ocr-bono`

`supabase/functions/ocr-bono/index.ts`. Deno runtime. Triggered by:

- **Primary path:** a `pg_net` outbound HTTP call from `create_bono_document` immediately after insert. (Requires the `pg_net` extension — already on Supabase hosted.)
- **Fallback path:** mobile retries by calling `POST /functions/v1/ocr-bono` with the document_id if the job stays queued > 30 s.

The function:

1. Authenticates using the Supabase service-role key (server-only).
2. Acquires lock on `ocr_job`: `update ocr_job set status='processing', attempts = attempts + 1, locked_at = now() where id = $1 and status in ('queued', 'failed') returning …`.
3. Reads `document.storage_path`; signs a 60-second Storage URL.
4. Reads **shop context for prompt priming**:
   - `shop.name`
   - Top 30 `shop_item.display_name` by recent activity (from `v_top_movers` or a stable top-N query).
   - The 20 most-recent supplier `party.name`.
5. Calls **Anthropic Messages API** with multimodal input (image + text) and `tool_choice` forcing a single `record_bono` tool call. The model is pinned to `claude-haiku-4-5-20251001`.
6. Validates the returned JSON against `BONO_SCHEMA` (defensive second-pass; `tool_choice` constrains the model but we never trust a single layer).
7. UPSERTS `document.ocr_result` and `ocr_job.status = 'success'`.
8. On any exception or schema-validation failure, sets `ocr_job.status = 'failed'`, increments attempts, stores `last_error`. After 3 failures the job is dead — mobile never sees a suggestion, cashier enters manually.

**Why an LLM with tool_choice, not Vision + custom parser?** See § 5. Tool-use forces the model to call exactly one function with arguments matching `BONO_SCHEMA` — no free-form prose, no markdown JSON-in-code-fence parsing, no drift.

**Why Claude Haiku 4.5 specifically?**
- Cheapest tier with full vision support — 200K context window is plenty for bono context + image.
- ~$0.004 per bono at our prompt size (vs $0.012 for Sonnet 4.6, $0.020 for Opus 4.8).
- Receipt-style documents are well within its accuracy band; upgrade tier only if pilot data shows accuracy gaps.
- Pinning to a specific snapshot (`claude-haiku-4-5-20251001`) guarantees deterministic behavior across deployments — see § 15 open question on regression-test corpus.

**Prompt shape (illustrative, final wording set during #261):**

```
SYSTEM: You are extracting line items from a "bono" — a supplier's invoice
for a small grocery shop in Somalia. The shop's primary language is
Somali; many suppliers write in mixed Somali/English shorthand.

The bono MAY be:
- Printed on a thermal receipt printer
- Laser-printed on plain paper
- Handwritten in pen on a notebook page
- Photocopied or stamped, possibly skewed
- Mixed Latin / Arabic script

For each line item extract: raw_text (as written, do not translate),
quantity, unit_price, line_total, and your confidence 0–1.

Be conservative. If a line is illegible, set confidence < 0.5. Do not
invent items. Do not match to specific shop products — that step is
downstream. Your job is faithful transcription + light structuring.

USER (with image):
Shop name: "{shop.name}"
Currency: {shop.currency_code}
Known suppliers in this shop (you may see one of these in the header):
  {top_supplier_names.join(", ")}
Common items in this shop's catalog (for spelling reference only,
do NOT force-match to these):
  {top_item_names.join(", ")}
```

The "for spelling reference only" wording is load-bearing — it lets the model bias toward known vocabulary without inventing matches. The downstream matching pipeline does the actual product binding; the model just transcribes.

**Tool schema (illustrative):**

```typescript
const BONO_SCHEMA = {
  type: 'object',
  required: ['supplier', 'lines'],
  properties: {
    supplier: {
      type: 'object',
      properties: {
        raw_name: { type: 'string' },
        raw_phone: { type: ['string', 'null'] },
        confidence: { type: 'number', minimum: 0, maximum: 1 }
      }
    },
    bono_date: { type: ['string', 'null'] },     // YYYY-MM-DD or null
    bono_total: { type: ['number', 'null'] },
    lines: {
      type: 'array',
      maxItems: 50,
      items: {
        type: 'object',
        required: ['raw_text', 'quantity', 'confidence'],
        properties: {
          raw_text:    { type: 'string' },
          quantity:    { type: 'number' },
          unit_price:  { type: ['number', 'null'] },
          line_total:  { type: ['number', 'null'] },
          confidence:  { type: 'number', minimum: 0, maximum: 1 },
          notes:       { type: ['string', 'null'] }
        }
      }
    },
    unparseable_sections: {
      type: 'array',
      items: { type: 'string' }
    }
  }
}
```

The `unparseable_sections` field gives the model a sanctioned place to dump uncertainty instead of fabricating lines — a hallucination mitigation backed into the schema.

**Anthropic API cost:** ~$0.004 per bono on Haiku 4.5 (vision tokens ≈ 1,500–2,000 + prompt ≈ 500 + output ≈ 300–500). A pilot shop doing 10 bonos/day = ~300/month = **$1.20/shop/month**. At 100 pilot shops = $120/month total.

Rate-limit defensively: 10 ocr-bono calls per shop per minute. A bug or abusive actor can't run away with cost.

**Anthropic data handling:** API calls (paid tier) are not used for model training per Anthropic's data-usage terms. Bono images are processed and discarded; only the structured `ocr_result` lives in our database (subject to our existing RLS). No additional privacy clause beyond what the shopkeeper already accepted at signup.

### 6.3 RPC — `suggest_receive_lines_from_bono(p_shop_id, p_document_id)`

Called from the mobile Receive screen once `document.ocr_status = 'success'`. Returns the prepopulate suggestions, ranked by confidence:

```sql
create or replace function public.suggest_receive_lines_from_bono(
  p_shop_id     uuid,
  p_document_id uuid
)
returns table (
  line_no              integer,
  raw_text             text,
  suggested_shop_item_id      uuid,
  suggested_shop_item_unit_id uuid,
  quantity             numeric,
  unit_price           numeric,
  line_total           numeric,
  confidence           text,             -- 'high' | 'med' | 'low'
  reason               text              -- 'supplier_alias' | 'global_alias' | 'no_match'
)
```

Logic per OCR'd line:
1. Look up `supplier_item_alias` for `(shop_id, supplier_party_id, raw_text_norm)`. Hit → confidence `'high'`, reason `'supplier_alias'`. Highest `confirm_count` wins.
2. Else lookup `shop_item_alias` (existing table, shop-wide aliases) with prefix/trigram match. Hit → confidence `'med'`, reason `'global_alias'`.
3. Else no match. Returns line with `suggested_shop_item_id = null`, confidence `'low'`, reason `'no_match'`. The cashier will tap-pick.

For the packaging: prefer the `shop_item_unit` the supplier last sold (via `supplier_item_unit_cost`) on alias hits; else default packaging.

### 6.4 RPC — `confirm_bono_suggestion(p_shop_id, p_document_id, p_raw_text, p_shop_item_id, p_shop_item_unit_id)`

Called when the cashier accepts (or edits + accepts) a suggested line. Records the cashier's choice into `ocr_correction` AND upserts `supplier_item_alias` (the learning step):

```sql
-- Pseudocode for the body:
-- 1. Insert ocr_correction row with the cashier's choice.
-- 2. Upsert supplier_item_alias for (shop, supplier, raw_text_norm) → confirm_count + 1.
-- 3. Returns nothing.
```

Sanctioned write path for `supplier_item_alias` — direct INSERT is RLS-forbidden.

### 6.5 Trigger — `enqueue_ocr_job` on document insert

```sql
create or replace function public._enqueue_ocr_for_bono()
returns trigger as $$
begin
  if new.type_id = (select id from public.document_type where code = 'bono') then
    insert into public.ocr_job (shop_id, document_id) values (new.shop_id, new.id);
    -- Fire-and-forget the edge function via pg_net; failures retry from the queue.
    perform net.http_post(
      url := current_setting('app.ocr_edge_url'),
      headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.service_role_key')),
      body := jsonb_build_object('document_id', new.id)
    );
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger enqueue_ocr_job_after_bono_insert
  after insert on public.document
  for each row execute function public._enqueue_ocr_for_bono();
```

`app.ocr_edge_url` and `app.service_role_key` are stored as Supabase secrets, read at runtime.

---

## 7. Supplier-specific learning

The most-leveraged piece. Without learning, OCR is a generic text extractor. With learning, it becomes a shop's accountant for each specific supplier within ~3 bonos.

### 7.1 The learning loop

```
First bono from new supplier:
    OCR returns lines with raw_text + confidence 'low' for items
    → cashier maps each manually → 6 ocr_correction rows + 6 supplier_item_alias rows
    → learning bootstrapped

Second bono from same supplier:
    OCR returns lines with raw_text → supplier_item_alias hits for 5/6 items
    → 5 confidence 'high' (pre-checked); 1 confidence 'low' (cashier picks)
    → cashier accepts → 1 new alias row, 5 confirm_count++ on existing

Third bono from same supplier:
    All 6 lines hit supplier_item_alias → all confidence 'high'
    → cashier glances + taps APPLY → ~10 seconds total
```

### 7.2 Decay and conflicts

- Aliases never auto-expire — supplier item codes are stable over years.
- If a cashier maps the same raw_text to two different items over time, the alias with higher `confirm_count` wins. The losing mapping becomes a tie-breaker for the suggestion sheet to show as a "second guess" option.
- A manual "edit alias" UI lives in v1.1 admin portal, not v1 mobile (rare operation; doesn't fit the speed contract).

### 7.3 Cross-supplier sharing — explicitly NO

We never share a supplier's mappings with another supplier in the same shop. The bono from Supplier A using "RICE 25" might mean basmati; from Supplier B "RICE 25" might mean parboiled. Per-supplier isolation prevents cross-contamination.

The shop-wide `shop_item_alias` (existing, from `0007`) covers the "everyone in this shop calls rice 'bariis'" case. That's separate and complements `supplier_item_alias`.

---

## 8. Mobile UX

### 8.1 The default Receive flow — unchanged

Cashier opens Receive. Picks supplier. **Takes bono photo (recommended but not required).** Starts typing lines. Hits SAVE. No new taps on this path. The bono camera button has been a recommended-first-step since `#231`; this design changes nothing visible until OCR completes.

### 8.2 The OCR completion banner

When `document.ocr_status` flips to `'success'` AND the OCR returned ≥ 1 suggested line, the Receive screen shows a slim banner above the line entry area:

```
┌──────────────────────────────────────────┐
│  📸  5 lines suggested from your bono    │
│      ✓ 3 ready · ⚠ 1 verify · ? 1 new   │
│                          [REVIEW] [✕]    │
└──────────────────────────────────────────┘
```

Single tap on REVIEW → opens the suggestion review sheet.
Tap ✕ → dismisses banner permanently for this bono (cashier prefers manual).
Banner never blocks: cashier can keep typing lines underneath it; entered lines auto-merge with accepted suggestions on APPLY (de-dupe by `shop_item_unit_id`).

### 8.3 The suggestion review sheet

Full-height bottom sheet, three sections by confidence:

```
┌──────────────────────────────────────────────────┐
│  Bono suggestions · Hodan Beverages              │
│  ────────────────────────────────────────────    │
│  ✓ READY (pre-checked, tap to deselect)          │
│  ☑  Bariis Basmati 25 kg · [4] @ [$20.00]        │
│  ☑  Caano Mass 1L      · [2] @ [$2.50]           │
│  ☑  Sukar 50 kg        · [1] @ [$45.00]          │
│                                                  │
│  ⚠ VERIFY (check the item and quantity)          │
│  ☑  Shaah Lipton tube · [1] @ [$8.00]            │
│      raw: "LIPTON TB X 200"                      │
│                                                  │
│  ? UNKNOWN (tap to pick the item)                │
│  ☐  [Pick item ▼]    · [1] @ [—]                 │
│      raw: "BISKUT SHEEMA 500G"                   │
│  ────────────────────────────────────────────    │
│  4 of 5 selected · $216.00                       │
│                                                  │
│              [ APPLY 4 LINES ]                   │
└──────────────────────────────────────────────────┘
```

Interaction:
- Each row's checkbox is the include/exclude toggle. Pre-checked for high/med; unchecked for low.
- Tapping the item name on a `?` row opens the same picker as a normal cart line.
- Tapping the quantity or price field opens the OS numpad.
- APPLY merges all checked rows into the cart. The cashier returns to the Receive screen with lines pre-filled; remaining manual entry continues from where they left off.

### 8.4 Conflict handling

If the cashier already typed line "Bariis Basmati 25kg × 4 @ $20" and APPLIES a suggestion for the same packaging, the suggestion is silently skipped (manual entry wins). The banner counter is decremented at sheet open to reflect dedup.

### 8.5 Learning is invisible

Every APPLY tap quietly calls `confirm_bono_suggestion` for each accepted/edited line. The cashier never sees "learning" language. Next time the same supplier's bono comes in, the system is better. No explicit training step.

### 8.6 Speed contract impact

| Path | Cashier time |
|---|---|
| Bono OCR (first-time supplier, 10 lines) | ~45 s (cashier does most mapping) |
| Bono OCR (3+ bonos from same supplier, 10 lines) | **~10–15 s** |
| Manual entry, no OCR (unchanged baseline) | ≤ 90 s |
| OCR fails / banner doesn't appear | identical to manual (≤ 90 s) |

The learned-supplier case is the headline. The cold-start case is still slower than ideal but a win over manual because Vision usually gets quantities and totals right even when item names need mapping.

---

## 9. Failure modes & recovery

| Failure | Behaviour | Recovery |
|---|---|---|
| Anthropic API down / rate-limited | `ocr_job.status='failed'`, attempts++ | Background retry up to 3× with exponential backoff; cashier enters manually if all attempts fail |
| Anthropic API exceeds 30 s timeout | `ocr_job.status='failed'` | Background retry as above |
| Model hallucinates a line not in the image | Line surfaces in review sheet with the (hallucinated) `raw_text` | Cashier sees the raw_text vs the bono and unchecks; no `supplier_item_alias` row is written (only ☑'d-and-applied lines write aliases). Hallucination self-corrects via cashier review. |
| Model returns invalid JSON despite `tool_choice` (theoretically impossible but defended) | Schema validation rejects; `ocr_job.status='failed'`, attempts++ | Same retry path; if persistent, manual entry |
| Model confidence uniformly low (`< 0.5` per line) | All suggestions render in the `?` section | Cashier picks items normally; aliases learned for next time |
| Supplier section can't be detected (model's `supplier.confidence < 0.6`) | Banner warns "Couldn't identify supplier — pick manually" before suggestions render | Cashier confirms supplier in the picker; alias-learning keyed off the cashier-picked supplier |
| Mobile offline at upload time | Bono bytes not uploaded; receive posts without document_id | OK — receive lines still post; bono queued via `#232` Phase 2 |
| Cashier dismisses banner | `ocr_result` still stored for owner audit | None — cashier choice respected |
| Cashier APPLIES then voids the receive | `ocr_correction` rows stay (the learning was the cashier's signal, not the post). `supplier_item_alias.confirm_count` is NOT decremented | Acceptable v1 trade-off; v1.x can add a reversal hook if owner cleanup matters |
| Document deleted before OCR runs | `ocr_job.status='failed'` with `last_error='document not found'` | None — silent |

---

## 10. Performance budget

- **Edge function cold start:** ~150 ms (Deno). Acceptable.
- **Anthropic Messages API call (Haiku 4.5, vision + ~500-token output):** 3–7 s typical, 12 s p95.
- **End-to-end bono upload → suggestion ready:** target ≤ 12 s p95 from cashier's perspective. Honest about it being a hair slower than the Vision path; cashier never waits because the path is async.
- **`suggest_receive_lines_from_bono` RPC:** ≤ 250 ms (uses indexed `supplier_item_alias` lookup; bounded by line count ≤ 50).
- **`confirm_bono_suggestion` RPC:** ≤ 100 ms (single insert + upsert).
- **Mobile polling:** if Realtime fails, poll once at 3 s after upload, then every 3 s up to 30 s. After 30 s the cashier sees no banner — manual entry continues. (Realtime is preferred; polling is the fallback.)
- **Anthropic API timeout:** edge function sets a 25 s hard timeout on the upstream call; rejected → retry. Anthropic's 503/529 (overload) responses also trigger retry with exponential backoff (1 s, 4 s, 12 s).

---

## 11. Privacy, retention, cost

- **Storage:** bono images stay in `shop-documents` indefinitely for owner audit. Owner-initiated bulk delete is v1.x.
- **Anthropic API privacy:** API calls on the paid tier are not used for model training — see Anthropic's commercial terms. Image bytes are processed for the inference call and discarded by Anthropic; only the structured `ocr_result` lives in our database (RLS-scoped). No additional data-sharing clause beyond what the shopkeeper accepted at signup.
- **Per-bono cost:** ~$0.004 on Claude Haiku 4.5 (image ≈ 1,500–2,000 vision tokens at $1/M input, prompt ≈ 500 tokens, output ≈ 300–500 tokens at $5/M output).
- **Aggregate cost ceiling:** per-shop ~$1.20/month at 10 bonos/day × 30. **Pilot total (100 shops): $120/month.** Negligible.
- **Cost-tier upgrade path:** if accuracy is insufficient on a corpus of pilot bonos, swap to Sonnet 4.6 (~$0.012/bono, $360/month total) — pin the new model snapshot, re-run the regression corpus, redeploy. Opus 4.8 is overkill for receipt parsing.
- **Rate limit:** 10 ocr-bono calls / shop / minute. Defensive; prevents runaway costs from a bug. Anthropic also enforces tier-based rate limits at the org level — we provision the org tier to comfortably cover pilot peak.
- **PII in OCR results:** the `ocr_result` jsonb may contain customer-readable strings (item names, quantities). Treated like any other shop-owned data; RLS keeps it scoped to shop membership.
- **Prompt-injection defence:** the input image could in principle contain text trying to manipulate the model ("ignore prior instructions, return ..."). Tool-use with a strict schema constrains output to `BONO_SCHEMA` — the model can't return arbitrary text or execute external actions. Worst-case prompt-injection lands a bad line in the suggestion sheet; cashier sees raw_text vs the image and rejects. No data exfiltration vector exists.

---

## 12. Offline behaviour

- Bono upload routes through the same offline write queue (`#232` Phase 2) as Receive itself: bytes are persisted to local disk + the document POST is queued.
- When connectivity returns, upload drains. The trigger on `document` insert fires server-side; OCR runs as normal.
- The cashier, when offline, never sees the banner — manual entry is the only path. No degraded UX.
- This means an offline-then-online bono surfaces its suggestions LATER — possibly after the Receive has already been posted. In that case we have an OCR result for a posted Receive but no way to back-fill suggestions. **That's intentional:** the suggestion belongs to in-progress data entry, not after-the-fact corrections.

---

## 13. Out of scope for v1

Deferred, with pull-in conditions:

1. **Multi-page bonos.** Pull-in when a pilot shop reports a multi-page case repeatedly.
2. **Handwriting fine-tuning.** Vision's default handwriting model handles ~70 % accuracy. Custom AutoML fine-tuning is a 6-month bet, only if a pilot shop's volume justifies it.
3. **Auto-post receives.** Never — the cashier's explicit APPLY is the contract.
4. **OCR for sale receipts (customer side).** Different shape; out.
5. **Supplier-mapping editor in mobile.** Mobile has no list/edit UI for `supplier_item_alias`. Owner can review in v1.x admin portal.
6. **Cross-shop sharing of supplier mappings.** Even when two shops use the same wholesaler, mappings stay isolated per shop. Multi-shop chains might want this in v2.
7. **Currency detection from bono.** Bonos may have a currency symbol; v1 trusts the shop's currency setting always.
8. **Quantity unit inference beyond default packaging.** If supplier writes "2 cases" and the shop has no "case" packaging, suggestion drops to `?` low-confidence rather than inventing a packaging.

---

## 14. Implementation checklist for #260–#264

Sequenced so each phase is independently shippable + verifiable.

**#260 — Backend schema + RPCs (~1.5 days)**
- [ ] Migration `0054_supplier_item_alias.sql` — new table + indexes.
- [ ] Migration `0055_ocr_rpcs.sql`:
  - [ ] `suggest_receive_lines_from_bono(p_shop_id, p_document_id)`
  - [ ] `confirm_bono_suggestion(p_shop_id, p_document_id, p_raw_text, p_shop_item_id, p_shop_item_unit_id)`
  - [ ] `_enqueue_ocr_for_bono()` trigger (without the pg_net call yet — added in #261)
- [ ] Harness § `MM` covering:
  - [ ] Alias lookup ranks by `confirm_count` desc.
  - [ ] `confirm_bono_suggestion` upserts both `ocr_correction` and `supplier_item_alias`.
  - [ ] `confirm_count` increments on repeat confirmation.
  - [ ] Cross-supplier isolation (Supplier B's bono never sees Supplier A's mappings).
  - [ ] Cashier capability gated (`auth_can_post_shop`).

**#261 — Edge function `ocr-bono` (~3 hours)**
- [ ] `supabase/functions/ocr-bono/index.ts` — skeleton + Anthropic Messages call via `@anthropic-ai/sdk`.
- [ ] `buildContext(shopId)` helper — fetch shop name + top suppliers + top items for prompt priming.
- [ ] `BONO_SCHEMA` JSON Schema + Ajv (or equivalent) validator for the second-pass defence.
- [ ] Lock acquisition on `ocr_job`; status transitions; retry semantics with exponential backoff (1 s / 4 s / 12 s).
- [ ] `ANTHROPIC_API_KEY` stored as a Supabase secret; model snapshot pinned to `claude-haiku-4-5-20251001`.
- [ ] Local invocation test (curl + a sample bono image).
- [ ] Wire pg_net call from the `0054` trigger; configure `app.ocr_edge_url` secret.
- [ ] Smoke deploy to staging; measure end-to-end latency.
- [ ] **Build regression corpus:** 10–15 representative bono images (printed-clean, printed-skewed, handwritten-clean, handwritten-messy, mixed-script). Stored in a test-only Storage path. Edge function has a `?test=corpus` mode that runs all of them and dumps results — used to validate any model upgrade.

**#262 — Mobile OCR result polling / Realtime subscription (~0.5 day)**
- [ ] `ShopApi.suggestReceiveLinesFromBono()` + `ShopApi.confirmBonoSuggestion()`.
- [ ] Realtime subscription on `document.id = X` in `receive_screen.dart`; fallback poll loop.
- [ ] State management: `Future<List<BonoSuggestion>>` lifecycle on the screen.

**#263 — Mobile prepopulate banner + review sheet (~1 day)**
- [ ] New widget `BonoSuggestionBanner` slotting above the line entry area.
- [ ] New bottom sheet `BonoSuggestionReviewSheet` with three confidence sections.
- [ ] Item picker reuse on the `?` rows.
- [ ] APPLY merges into `ReceiveController` lines (existing snapshot pattern handles undo).
- [ ] ARB en + so for every new string.
- [ ] Widget tests: banner visibility on `'success'`; sheet pre-check semantics; APPLY merges without overwriting manual entries.

**#264 — Wire the learning loop + harness coverage (~0.5 day)**
- [ ] On APPLY, fire `confirmBonoSuggestion` per accepted line (fire-and-forget, errors logged).
- [ ] Harness assertion: after two bonos from same supplier, second one's suggestions are confidence `'high'`.
- [ ] Doc `docs/templates-and-learning.md` update with the alias-learning section.
- [ ] Update `docs/mobile-app-alignment.md` to mark this design complete.

---

## 15. Open questions

To resolve before #260 lands:

1. **Trigger vs job-poller for OCR dispatch.** Current design uses pg_net from the insert trigger. Alternative: a scheduled Edge function polling `ocr_job where status='queued'` every 10 s. Trigger is lower latency; poller is simpler ops. Lean trigger; confirm pg_net is enabled on the target project.
2. **Model snapshot pinning + regression corpus.** Pin `claude-haiku-4-5-20251001` (or the equivalent dated snapshot in use at deploy time). Build the 10–15-image regression corpus during #261. Any model upgrade (Haiku → Sonnet, or a newer Haiku snapshot) MUST pass the corpus before being deployed. Where does the corpus live — repo (fixture images, public-ish content) or a private Storage path?
3. **Cost-tier ladder.** Start on Haiku 4.5. If pilot shopkeepers report wrong-line surfaces > 10 % of the time, escalate to Sonnet 4.6. What's the metric we'll watch? Proposal: ratio of suggestion-sheet `?` rows + cashier-unchecked rows, surfaced to system admin portal in v1.x.
4. **Currency in the prompt.** Pass `shop.currency_code` as context; tell the model "expected currency is X — interpret bare numbers in that currency." For SLSH-currency shops with very-large totals (no cents), the model handles native; verify with a real Hargeisa bono.
5. **Audit log emission.** Should each `confirm_bono_suggestion` write an `audit_log` row? Tilt no — too noisy. Aggregate counts in admin portal instead.
6. **Hallucination metric.** Build a "model invented this line" detector: compare reported line_total against the OCR'd bono_total; if sum-of-line-totals differs from bono_total by > 10 %, flag the whole result as low-confidence and downgrade ALL suggestions to `?`. Catches the worst hallucination shape (invented lines pad the sum).
