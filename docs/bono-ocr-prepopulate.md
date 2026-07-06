# Bono OCR + Receive Prepopulate — Design

> **Design contract** for the bono-photo OCR pipeline and the prepopulate UX it powers in the Receive flow. This document is the source of truth for what gets extracted, who/what runs it, how the cashier interacts with the suggestions, and how the system learns supplier-specific quirks over time. The implementation lands as tasks `#260`–`#264` (see § 14). Companion documents:
>
> - `docs/mobile-app.md` § 7 — the Receive flow this design enhances.
> - `docs/ux.md` — the speed contract and binding interaction rules.
> - `docs/architecture.md` § OCR pipeline — **superseded by this doc.** That section describes the older Google Cloud Vision + heuristic-parser approach; this design uses an LLM (Claude Haiku 4.5 multimodal, forced tool-use) instead — see § 5.
> - `docs/backend-schema.md` § documents/OCR — the `document` / `ocr_job` / `ocr_correction` tables.
> - `docs/templates-and-learning.md` — note: the `ocr-mappings.json` template pack described there is **not shipped** (the grocery template was removed). Supplier-specific mapping is learned at runtime via `supplier_item_alias` (§ 6.1 / § 7), not seeded from a template pack.
>
> **Status:** this is the *robust + scalable-by-config* revision. The pipeline scales to thousands of bonos/month out of the box and to tens of thousands by configuration + Anthropic-tier changes only (§ 6a) — no re-architecture.

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

This is what exists today (as of migration head `0100`):

| Layer | Status |
|---|---|
| Mobile bono capture (camera/gallery, OCR-tuned compression) | ✓ shipped — `lib/shared/bono_image_picker.dart` (maxWidth 1600, q70) |
| Mobile upload to Storage + client-minted document UUID | ✓ shipped — `ShopApi.uploadBonoImage()` (`shop_api.dart:~1880`) |
| `create_bono_document` RPC | ⚠ shipped but **inert** — migration `0034` inserts the `document` with `ocr_status='pending'` and **does NOT enqueue an `ocr_job`**, so a bono is captured/stored/linked and then nothing happens; `ocr_status` sits `pending` forever |
| Receive screen attaches `document_id` → `post_receive` | ✓ shipped — `receive_screen.dart` (`_onAttachBono` ~`:473`, upload `:507`, threaded at `:820/:886/:942`) |
| `document` table with `ocr_result jsonb` + `ocr_status_id` | ✓ shipped — migration `0008` |
| `ocr_status` reference table (`pending/processing/success/failed/manual`) | ✓ shipped — migrations `0002` + `0008` |
| `ocr_job` queue table (attempts / `locked_at` / `last_error` / status index) | ✓ shipped — migration `0008` (built, but **nothing writes to it yet**) |
| `ocr_correction` for learning | ✓ shipped — migration `0008` |
| Storage bucket `shop-documents` + RLS + path-shape constraint | ✓ shipped — migration `0015` |
| ~~Template `ocr-mappings.json` seed~~ | ✗ **removed** — grocery is no longer a shop starter (harness fixture only, see `templates/README.md`); no `ocr-mappings.json` exists |
| **Edge function calling the AI** | ✗ **missing** — `supabase/functions/` does not exist; zero AI/OCR code in the repo |
| **Job dispatcher (trigger + poller)** | ✗ **missing** |
| **Result → suggested-line RPC** | ✗ **missing** |
| **Supplier-specific learning table** (`supplier_item_alias`) | ✗ **missing** |
| **Config knobs + secrets wiring for the AI key** | ✗ **missing** (`platform_config` exists — `0067` — but holds no OCR keys/tunables yet) |
| **Mobile prepopulate UX** | ✗ **missing** |
| **Backend harness coverage** | ✗ **missing** |

The schema + capture are set up well. **Everything from the AI call up is unbuilt**, and the shipped `create_bono_document` doesn't yet enqueue a job. New migrations land at `0101+`.

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
[Backend] create_bono_document RPC + after-insert trigger on `document`
        │  • Inserts document row (ocr_status='pending')
        │  • Trigger enqueues ocr_job (status='queued')
        │  • Trigger fires a BEST-EFFORT pg_net kick to the edge fn (fast path)
        │  • Returns doc_id immediately (mobile not blocked)
        ▼
[Dispatch] two layers — see § 6.5 + § "Scalability by configuration":
        │  - FAST PATH: the trigger's pg_net kick (low latency, common case)
        │  - BACKBONE: a pg_cron poller (~10s) claims a bounded batch of
        │    'queued' jobs under a lease (SKIP LOCKED), reclaims stale
        │    'processing' jobs, enforces rate + daily-cost budgets, and
        │    invokes ocr-bono. If the fast-path kick ever fails, the poller
        │    catches the job — nothing is stranded, and bursts get absorbed.
        ▼
[Edge Function] ocr-bono
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
7. **Hallucination guard (baked in, not optional):** if `bono_total` is present and `abs(sum(line_total) − bono_total) / bono_total > 0.10` (threshold `ocr_hallucination_tolerance`, config), stamp a `result_warning` on `ocr_result` and downgrade EVERY line to `low` confidence — the classic "invented line pads the sum" shape can't slip through pre-checked. `unparseable_sections` gives the model a sanctioned place to dump uncertainty instead of fabricating.
8. UPSERTS `document.ocr_result` and `ocr_job.status = 'success'`.
9. On any exception or schema-validation failure, sets `ocr_job.status = 'failed'`, increments attempts, stores `last_error`. After `ocr_max_attempts` (config, default 3) the job is dead-lettered — the owner sees "OCR unavailable, enter manually"; the cashier is never blocked.

**Why an LLM with tool_choice, not Vision + custom parser?** See § 5. Tool-use forces the model to call exactly one function with arguments matching `BONO_SCHEMA` — no free-form prose, no markdown JSON-in-code-fence parsing, no drift.

**Why Claude Haiku 4.5 specifically?**
- Cheapest tier with full vision support — 200K context window is plenty for bono context + image.
- ~$0.004 per bono at our prompt size (vs $0.012 for Sonnet 5, $0.020 for Opus 4.8).
- Receipt-style documents are well within its accuracy band; upgrade tier only if pilot data shows accuracy gaps.
- Pinning to a specific snapshot (`claude-haiku-4-5-20251001`) guarantees deterministic behavior across deployments — see § 15.2 (regression corpus). Model swaps go through the `ocr_model` config knob (§ 6a), not a code change.

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

`app.ocr_edge_url` and `app.service_role_key` are stored as Supabase secrets, read at runtime. The `pg_net` call is **best-effort / fire-and-forget** — it is the low-latency fast path only. Correctness does NOT depend on it: if it fails (network, edge cold-start, transient), the job simply stays `queued` and the poller (§6.6) picks it up on its next tick. Never `raise` on a failed kick — the `document` insert must always succeed.

### 6.6 Dispatcher — `pg_cron` poller (reliability + scale backbone)

A scheduled job (`pg_cron`, every `ocr_poller_interval_s` — default 10 s) is the authoritative drainer. Each tick, in one SECURITY DEFINER function:

1. **Reclaim** stale leases: `update ocr_job set status='queued' where status='processing' and locked_at < now() - (lease interval)` — a crashed/timed-out worker's job returns to the pool.
2. **Budget check**: read the config knobs (§ Scalability); if the global daily cost cap or global in-flight ceiling is already hit, do nothing this tick (backpressure). Otherwise compute the remaining batch budget = `min(ocr_poller_batch_size, ocr_max_concurrent_global − in_flight)`.
3. **Claim** up to the batch budget: `... where status='queued' [and not exceeding ocr_max_per_shop_per_min per shop] order by created_at for update skip lock limit N` → set `status='processing', locked_at=now(), attempts=attempts+1`, returning the ids. `SKIP LOCKED` means many poller ticks / workers never fight over the same row.
4. **Invoke** `ocr-bono` per claimed job via `pg_net` (or one fan-out call). The edge fn does the AI call and writes the result; it does NOT need to re-claim (the poller already leased it).

This gives **natural backpressure** (the poller only pulls what the budget allows, so a burst of thousands of uploads queues cleanly instead of hammering Anthropic), **no stranded jobs** (every `queued`/stale-`processing` row is eventually claimed), and **idempotency** (`ocr_job.document_id` unique + status compare-and-set + re-runnable UPSERT). `pgmq` (Supabase's queue extension) was considered but the shipped `ocr_job` table already has the attempts/lease/status-index columns we need — reuse it, less churn.

---

## 6a. Scalability by configuration

**Design contract:** the initial build handles **thousands of bonos/month**; growing to tens of thousands is a **configuration + provisioning** change, never a re-architecture. There is no code or schema change on the scaling path — the `ocr_job` queue + stateless edge worker scale horizontally, gated only by tunables and the Anthropic org tier.

All knobs live in `platform_config` (migration `0067`, `get_platform_config_for_shop` / `set_platform_config`), with a platform default plus optional per-org / per-shop override, read at runtime by the poller + edge fn (no redeploy to change):

| Knob | Purpose |
|---|---|
| `ocr_poller_interval_s` (10) | poller tick rate |
| `ocr_poller_batch_size` (25) | jobs claimed per tick — the primary throughput dial |
| `ocr_max_concurrent_global` (50) | global in-flight ceiling — protects the Anthropic org rate limit |
| `ocr_max_per_shop_per_min` (10) | per-shop fairness + abuse guard |
| `ocr_job_lease_seconds` (60) | stale-`processing` reclaim window |
| `ocr_max_attempts` (3) | dead-letter after N tries |
| `ocr_backoff_seconds` (`[1,4,12]`) | retry spacing on transient Anthropic errors |
| `ocr_daily_cost_cap_usd` (global + per-shop) | circuit breaker: over budget → jobs stay `queued`, banner never appears, **manual entry is unaffected** |
| `ocr_model` (`claude-haiku-4-5`) + `ocr_model_max_tokens` | model swap by config (see § 5 / § 11) |

**How you scale:** raise `ocr_poller_batch_size` / `ocr_max_concurrent_global`, provision a higher **Anthropic usage tier** (the true RPM/TPM ceiling — an ops lever, not code), and move up the **Supabase plan** for edge-function concurrency + DB headroom. The queue absorbs bursts; the poller meters them to the budget. Nothing above the config layer changes.

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
- **Anthropic API timeout:** edge function sets a 25 s hard timeout on the upstream call; rejected → retry. Anthropic's 429/503/529 (rate-limit / overload) responses also trigger retry with exponential backoff (`ocr_backoff_seconds`, default 1 s / 4 s / 12 s).

### 10.1 Observability

A read-only view `v_ocr_job_stats` (shop-scoped via RLS, aggregate-only for platform staff) exposes, over a rolling window: job counts by `status`, p50/p95 queue→success latency, mean `attempts`, dead-letter rate, and estimated Anthropic spend (jobs × per-model cost). Surfaced in the **system-admin portal**. This is the signal for the cost/accuracy ladder (§ 15.3): the **accuracy proxy** = ratio of review-sheet `?`/unchecked rows to total suggested lines; if it stays high, escalate `ocr_model` config (Haiku 4.5 → Sonnet 5) and re-run the regression corpus. No per-bono audit rows (too noisy — see § 15.5); the aggregate view is the source of truth.

---

## 11. Privacy, retention, cost

- **Storage:** bono images stay in `shop-documents` indefinitely for owner audit. Owner-initiated bulk delete is v1.x.
- **Anthropic API privacy:** API calls on the paid tier are not used for model training — see Anthropic's commercial terms. Image bytes are processed for the inference call and discarded by Anthropic; only the structured `ocr_result` lives in our database (RLS-scoped). No additional data-sharing clause beyond what the shopkeeper accepted at signup.
- **Per-bono cost:** ~$0.004 on Claude Haiku 4.5 (image ≈ 1,500–2,000 vision tokens at $1/M input, prompt ≈ 500 tokens, output ≈ 300–500 tokens at $5/M output).
- **Aggregate cost ceiling:** per-shop ~$1.20/month at 10 bonos/day × 30. **Pilot total (100 shops): $120/month.** Negligible.
- **Cost-tier upgrade path:** if accuracy is insufficient on a corpus of pilot bonos, swap to Sonnet 5 (~$0.012/bono, $360/month total) — pin the new model snapshot, re-run the regression corpus, redeploy. Opus 4.8 is overkill for receipt parsing.
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

> Migration numbers below are next-available from the current head `0100`.

**#260 — Backend schema + RPCs (~1.5 days)**
- [ ] Migration `0101_supplier_item_alias.sql` — new table + indexes.
- [ ] Migration `0102_ocr_rpcs.sql`:
  - [ ] `suggest_receive_lines_from_bono(p_shop_id, p_document_id)`
  - [ ] `confirm_bono_suggestion(p_shop_id, p_document_id, p_raw_text, p_shop_item_id, p_shop_item_unit_id)`
- [ ] Migration `0103_ocr_dispatch.sql`:
  - [ ] `_enqueue_ocr_for_bono()` after-insert trigger on `document` (enqueue `ocr_job` + best-effort pg_net kick — the kick can be a no-op stub until #261 wires the edge URL).
  - [ ] `_drain_ocr_jobs()` SECURITY DEFINER dispatcher (reclaim stale leases → budget check → claim batch `SKIP LOCKED` → pg_net invoke) + `pg_cron` schedule at `ocr_poller_interval_s`.
  - [ ] `platform_config` defaults for the § 6a knobs; `v_ocr_job_stats` view.
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
- [ ] Wire the pg_net kick from the `0103` trigger + `_drain_ocr_jobs()` poller; configure `app.ocr_edge_url` secret; enable `pg_net` + `pg_cron` on the target project.
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

## 15. Resolved decisions

The open questions from the original draft are now resolved (this is the robust + scalable-by-config design):

1. **Dispatch → hybrid.** Trigger's best-effort pg_net kick (fast path) **plus** a `pg_cron` poller with lease/reclaim as the reliability + scale backbone (§ 6.5 / § 6.6). No stranded jobs; bursts absorbed by the queue. Requires `pg_net` + `pg_cron` enabled on the project (both available on Supabase hosted).
2. **Model + regression corpus.** Default `claude-haiku-4-5` (pin the dated snapshot at deploy), swappable via the `ocr_model` config knob. Escalation tier is **Sonnet 5** (`claude-sonnet-5`); Opus 4.8 is overkill for receipts. Corpus = 10–15 representative bono images (printed-clean / printed-skewed / handwritten-clean / handwritten-messy / mixed-script) at a **private Storage test path** (not the repo — real bonos are shop PII), run via the edge fn's `?test=corpus` mode. Any `ocr_model` change MUST pass the corpus first.
3. **Cost/accuracy ladder metric.** `v_ocr_job_stats` (§ 10.1) + the review-sheet `?`/unchecked-row ratio as the accuracy proxy. High ratio → bump `ocr_model` to Sonnet 5 (config) and re-run the corpus.
4. **Currency in the prompt.** Pass `shop.currency_code`; instruct the model to interpret bare numbers in that currency. SLSH (0-decimal, large totals) handled natively; verify with a real Hargeisa bono during #261.
5. **Audit emission.** No per-`confirm_bono_suggestion` audit row (too noisy). Aggregate in `v_ocr_job_stats` + the admin portal.
6. **Hallucination guard.** Baked into the edge fn (§ 6.2 step 7): `abs(sum(line_total) − bono_total)/bono_total > 0.10` → `result_warning` + downgrade all lines to `low`. Only ☑-and-APPLIED lines write `supplier_item_alias`, so a hallucinated line self-corrects on cashier review.

**Still genuinely open (confirm before #261):** the Anthropic **org usage tier** to provision for pilot peak (the true throughput ceiling — an ops decision), and the `platform_config` starting values for the § 6a knobs.
