# Full offline-first — local-first thick-client architecture

## Context

User shifted the offline strategy from "light offline" (queue
posts, cache a few reads) to **full offline-first** — every
daily-flow read works without network, and the cashier should
not perceive a difference between online and offline modes.

This is a major architectural change. We're moving from a thin
client that fetches per screen to a **local-first thick client**
that keeps a synchronized mirror of the relevant subset of the
server data on the device and syncs deltas in the background.

The plan also calls for a **per-shop feature flag** so we can
enable this for select shops without forcing it on everyone.

## Target architecture

### High-level

```
   ┌──────────────────────────────────────────────────┐
   │  UI (screens, sheets, pickers)                   │
   │  Read from: LocalRepository.* (always)           │
   │  Write to:  LocalRepository.* + OfflineQueue     │
   └────────┬─────────────────────────────────────────┘
            │
   ┌────────▼─────────────────────────────────────────┐
   │  LocalRepository (Dart layer)                    │
   │  Provides: items, parties, categories, history,  │
   │            stock projections                     │
   │  All synchronous reads from sqflite.             │
   └────────┬─────────────────────────────────────────┘
            │
   ┌────────▼─────────────────────────────────────────┐
   │  sqflite mirror tables                           │
   │  local_shop_item, local_shop_item_unit, ...      │
   │  local_party, local_expense_category, ...        │
   │  local_stock_projection (in-flight queue effect) │
   │  local_sync_state (per-resource last-sync ts)    │
   └────────┬─────────────────────────────────────────┘
            │
   ┌────────▼─────────────────────────────────────────┐
   │  SyncEngine (Dart)                               │
   │  • Initial full sync (one shot per fresh device) │
   │  • Delta sync (periodic + on reconnect)          │
   │  • Realtime subscription → applies to local DB   │
   │  • Conflict resolution (last-write-wins by       │
   │    server updated_at; audit log preserves        │
   │    history)                                      │
   └────────┬─────────────────────────────────────────┘
            │
   ┌────────▼─────────────────────────────────────────┐
   │  Backend (new RPCs + updated_at columns)         │
   │  get_shop_full_sync / *_delta / realtime stream  │
   └──────────────────────────────────────────────────┘
```

UI never calls ShopApi for reads. The READ path always goes:
**screen → LocalRepository → sqflite**. Cashier doesn't see
loading spinners for fresh data; everything is already there.

WRITE path: same posting RPCs as today, but ALSO writes
optimistically to the local DB AND creates a local stock
projection if it affects inventory. Sync engine reconciles
when the server response lands.

### Why local-first beats SWR caching

SWR is "cache → maybe refresh → show fresh". It's read-through
caching with TTL. The cashier still feels a "loading from
network" moment whenever the cache expires or a new screen
opens.

Local-first is "always local; sync in background". No loading
moments unless the user genuinely first-time-syncs. This is the
shape of POS apps that work in remote villages with intermittent
internet — Square, Loyverse, Vend.

### Per-shop feature flag

`platform_config` already exists (#365). The feature toggle is
`use_local_db` (bool, default `true`). Per `#382`:

- `true` (default): LocalRepository + SyncEngine active; reads
  from sqflite mirror, writes queue for background drain.
- `false`: thin-client mode — every read/write goes to the
  server directly. No queue, no local mirror writes. (Future
  `#383` work — current code still queues writes when this
  flag is false; the behavioral change ships separately.)

**Vocabulary discipline.** "useLocalDb" names the feature
toggle. "Offline" elsewhere refers strictly to phone
connectivity state (the device has no internet) — a separate
axis from the toggle. The app's response to connectivity loss
varies based on the flag, but the flag itself does not mean
"offline."

`useLocalDb(BuildContext)` from `lib/sync/use_local_db.dart` is
the canonical resolver. The app's read paths branch at the
`LocalRepository` layer:
- `useLocalDb == true`: read from sqflite, sync engine maintains it.
- `useLocalDb == false`: read from network (legacy SWR-cache
  path); local caches per #369 still work as a small win.

**Backwards compatibility (one release).** The resolver also
accepts legacy `offline_mode` rows in `platform_config` /
`shop_setting`:

| Legacy value | Resolves to |
|---|---|
| `offline_mode = 'full'` | `useLocalDb = true` |
| `offline_mode = 'light'` | `useLocalDb = false` |

Drop the legacy mapping in `#385` after rows in the wild have
been migrated to the new key.

Default for v1: `useLocalDb = true`. Set `false` per shop via
the shop-admin web Setup tab (planned in `#384`) or directly
via `set_platform_config` SQL.

## What goes into the local mirror

### Schema (new sqflite tables, migration `0002_local_mirror.dart`)

```sql
-- Items
CREATE TABLE local_shop_item (
  shop_item_id  TEXT PRIMARY KEY,
  shop_id       TEXT NOT NULL,
  item_id       TEXT,
  display_name  TEXT NOT NULL,
  category_id   TEXT,
  base_unit_code TEXT NOT NULL,
  current_stock REAL NOT NULL DEFAULT 0,
  avg_cost      REAL NOT NULL DEFAULT 0,
  reorder_threshold REAL,
  is_active     INTEGER NOT NULL DEFAULT 1,
  updated_at    INTEGER NOT NULL,
  server_updated_at INTEGER NOT NULL  -- for conflict resolution
);
CREATE INDEX idx_local_shop_item_shop ON local_shop_item(shop_id, is_active);
CREATE INDEX idx_local_shop_item_name ON local_shop_item(display_name COLLATE NOCASE);

-- Packagings
CREATE TABLE local_shop_item_unit (
  shop_item_unit_id  TEXT PRIMARY KEY,
  shop_item_id       TEXT NOT NULL,
  unit_code          TEXT NOT NULL,
  packaging_label    TEXT NOT NULL,
  conversion_to_base REAL NOT NULL,
  sale_price         REAL,
  last_cost          REAL,
  is_default_sale    INTEGER NOT NULL DEFAULT 0,
  is_default_receive INTEGER NOT NULL DEFAULT 0,
  is_active          INTEGER NOT NULL DEFAULT 1,
  server_updated_at  INTEGER NOT NULL,
  FOREIGN KEY(shop_item_id) REFERENCES local_shop_item(shop_item_id)
);
CREATE INDEX idx_local_unit_item ON local_shop_item_unit(shop_item_id, is_active);

-- Aliases for fuzzy search
CREATE TABLE local_shop_item_alias (
  shop_item_id  TEXT NOT NULL,
  alias         TEXT NOT NULL,
  is_display    INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (shop_item_id, alias)
);
CREATE INDEX idx_local_alias ON local_shop_item_alias(alias COLLATE NOCASE);

-- Barcode index (O(1) scan lookup)
CREATE TABLE local_shop_item_barcode (
  barcode            TEXT PRIMARY KEY,
  shop_item_unit_id  TEXT NOT NULL,
  is_primary         INTEGER NOT NULL DEFAULT 0
);

-- Parties
CREATE TABLE local_party (
  party_id     TEXT PRIMARY KEY,
  shop_id      TEXT NOT NULL,
  name         TEXT NOT NULL,
  phone        TEXT,
  type_code    TEXT NOT NULL,
  receivable   REAL NOT NULL DEFAULT 0,
  payable      REAL NOT NULL DEFAULT 0,
  is_active    INTEGER NOT NULL DEFAULT 1,
  server_updated_at INTEGER NOT NULL
);
CREATE INDEX idx_local_party_type ON local_party(shop_id, type_code, is_active);
CREATE INDEX idx_local_party_name ON local_party(name COLLATE NOCASE);

-- Categories (small; rarely changes)
CREATE TABLE local_expense_category (
  category_id  TEXT PRIMARY KEY,
  shop_id      TEXT NOT NULL,
  code         TEXT NOT NULL,
  name         TEXT NOT NULL,
  is_active    INTEGER NOT NULL DEFAULT 1
);

-- Reference data (units, product categories): same shape, small.
CREATE TABLE local_unit (...);
CREATE TABLE local_category (...);

-- Recent transactions for history offline
CREATE TABLE local_transaction (
  txn_id       TEXT PRIMARY KEY,
  shop_id      TEXT NOT NULL,
  type_code    TEXT NOT NULL,   -- 'sale', 'receive', 'payment', 'expense'
  occurred_at  INTEGER NOT NULL,
  total        REAL NOT NULL,
  party_id     TEXT,
  is_voided    INTEGER NOT NULL DEFAULT 0,
  server_updated_at INTEGER NOT NULL,
  payload_json TEXT NOT NULL    -- denormalized for display
);
CREATE INDEX idx_local_txn_shop_time ON local_transaction(shop_id, type_code, occurred_at DESC);

-- Stock projection from in-flight queued posts (deducted from
-- local_shop_item.current_stock when the cashier looks up an
-- item, until the post syncs and the projection clears).
CREATE TABLE local_stock_projection (
  pending_post_id  TEXT NOT NULL,
  shop_item_id     TEXT NOT NULL,
  delta            REAL NOT NULL,
  PRIMARY KEY (pending_post_id, shop_item_id)
);
CREATE INDEX idx_proj_item ON local_stock_projection(shop_item_id);

-- Per-resource sync bookkeeping
CREATE TABLE local_sync_state (
  shop_id       TEXT NOT NULL,
  resource      TEXT NOT NULL,
  last_synced_at INTEGER NOT NULL,
  full_sync_done INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (shop_id, resource)
);
```

Sizes for a typical 500-item shop with 50 active parties:
- Items + packagings + aliases + barcodes: ~1 MB
- Parties: ~50 KB
- Categories + units + reference: ~10 KB
- 30 days of transactions (200 txn × 1 KB): ~200 KB
- Total: ~1.5 MB per shop. Trivial.

For a 5,000-item shop: ~10 MB. Still fine.

### Server-side requirements

Each mirrored table needs:
- `updated_at TIMESTAMPTZ` column (we have most; need to add to
  a few)
- Trigger to bump `updated_at` on UPDATE
- Index on `(shop_id, updated_at)`

New RPCs (migration `0069_full_sync_rpcs.sql`):

```sql
get_shop_full_sync(p_shop_id)
  RETURNS jsonb
  -- One mega-call: items + units + aliases + barcodes + parties
  -- + categories + reference data + last 30 days of txns.
  -- Used on first sync of a fresh device.

get_shop_items_delta(p_shop_id, p_since timestamptz)
  RETURNS jsonb
  -- Same payload shape as full_sync but filtered to rows where
  -- updated_at > p_since. Includes tombstones (is_active = false
  -- rows) so deletions propagate.

get_parties_delta(p_shop_id, p_since timestamptz)
get_categories_delta(p_shop_id, p_since timestamptz)
get_transactions_delta(p_shop_id, p_since timestamptz, p_limit int)
```

All RLS-gated by `auth_can_access_shop`.

### Realtime channel

Subscribe to `postgres_changes` for the 4 most-changing tables
(`shop_item`, `shop_item_unit`, `party`, `transaction`)
filtered by `shop_id`. Apply changes to the local DB as they
land. This gives near-realtime updates without polling.

Fall back to periodic delta sync if realtime disconnects.

#### Realtime scope: what it captures

Supabase Realtime listens to Postgres WAL events. It does NOT
filter by who made the change — every write to a subscribed
table fires an event, from any source:

- Another mobile cashier on the same shop
- Owner editing in shop-admin web
- Platform staff in system-admin portal
- Direct SQL / backend cron jobs
- The mobile app's own posts (echoed back)

This is the design intent — the cashier should see a price the
owner just changed in the web portal without pulling-to-refresh.
RLS still applies: the cashier only receives events for shops
they have access to. No cross-shop leakage.

Non-DB changes (Storage uploads, auth events) do NOT fire
realtime. The bono photo upload, for example, isn't visible
to realtime — the `transaction.bono_document_id` field-change
on the underlying row is, though, so the next sync picks it up.

#### Self-echo handling

When the mobile app posts a sale, the resulting `INSERT` into
`transaction` fires a realtime event that comes back to the
same device. The sync engine MUST de-duplicate:

```dart
// On receiving a realtime event for `transaction`:
final clientOpId = event.newRecord['client_op_id'] as String?;
if (clientOpId != null && _isOwnWrite(clientOpId)) {
  // Our own write coming back. Already optimistically
  // applied locally; just clear any pending projection.
  _clearProjectionForClientOpId(clientOpId);
  return;
}
// Foreign write — apply to local DB.
_applyRemoteChange(event);
```

The check against pending/drained queue entries by
`client_op_id` is O(log n) — fast even with a long queue.

#### Bulk burst debouncing

If an owner CSV-imports 200 products through shop-admin web,
200 realtime events fire in rapid succession. Naive
per-event sqflite writes would thrash the DB and the UI.

The sync engine accumulates events into a buffer with a
**200 ms debounce window**, then applies them as one sqflite
transaction + one `notifyListeners()`. Throughput stays high
while individual events still arrive fast enough for the
cashier to see live activity.

When realtime is firing > 50 events/sec sustained (e.g., a
mass update), the engine SHOULD give up on realtime and
schedule a full delta sync instead — bulk events are better
batched server-side via the delta RPC.

## Sync engine

### States

```
                  ┌──────────────┐
                  │  Cold start  │
                  └──────┬───────┘
                         │
            ┌────────────┴────────────┐
            │                         │
       no_local                  has_local
            │                         │
       ┌────▼─────┐               ┌───▼────┐
       │ Full sync│ ◄─── retry ───│ Delta  │
       │  (block) │               │  sync  │
       └────┬─────┘               └───┬────┘
            │                         │
            └──────────┬──────────────┘
                       │
                  ┌────▼──────┐
                  │  Live     │  ← realtime + periodic delta
                  └───────────┘
```

- **Cold start with no local data**: blocking full-sync banner.
  User must connect once before working. "Loading your shop's
  data... 47%". If they cancel, app falls back to light-mode
  for this session.
- **Cold start with local data**: enter live mode immediately;
  fire a background delta sync to catch up. Cashier doesn't
  wait.
- **Live mode**: realtime + every 5 min delta sync as backup.
- **Lose connection**: silent. UI keeps working from local DB.
- **Regain connection**: queued posts drain (existing #367),
  delta sync runs, realtime resubscribes.

### Conflict resolution

Posts: idempotency via `client_op_id` (existing).

Item / party edits: **last-write-wins by `server_updated_at`**.
If the local row has a queued edit that hasn't synced and the
server reports a newer row, we DROP the local edit + log it for
the user to redo. Audit log preserves both.

Per-field merge is the "right" answer but adds 3× complexity.
For pilot, LWW with audit log is acceptable; small shops rarely
have two cashiers editing the same item simultaneously.

### Stock projection

When the cashier rings a sale offline:
1. Sale post → `OfflineQueue.enqueue(pending_post)` (existing).
2. For each line: insert row into `local_stock_projection`
   with `delta = -line.base_quantity`.
3. UI shows `current_stock - SUM(projection.delta)` as the
   effective stock.

When the post drains successfully:
1. Server's new stock value comes back via realtime / next
   delta sync.
2. `local_shop_item.current_stock` updated.
3. Projection rows for that `pending_post_id` deleted.

When the post fails permanently:
1. Projection rows for that `pending_post_id` deleted.
2. Local stock reverts to pre-projection.
3. Cashier sees the failed post in Storage & sync, can
   manually retry or discard.

## Wiring the daily flows

### Sale screen
- Item grid + search: `LocalRepository.searchItems(query)`.
  Returns matches from sqflite via the FTS-like search over
  `display_name + aliases`. Instant.
- Barcode scan: `LocalRepository.lookupBarcode(code)` →
  hash-table-like lookup in `local_shop_item_barcode`.
- Stock display: stock − sum(projection deltas).
- Default sale unit per item: read from local
  `shop_item_unit` rows.
- Customer (optional): `LocalRepository.searchParties(query,
  type: 'customer')`.
- POST: writes to local_transaction + local_stock_projection;
  enqueues to OfflineQueue.

### Receive screen
Mirror of Sale: local items, local supplier (party type =
'supplier'), POST queues with stock-add projection.

Bono image upload: still requires online (Storage). Queued
posts that depend on a bono image hold the bytes locally until
upload succeeds; upload retries on the next online cycle.

### Payment screen
Party picker: local search over `local_party`.
Outstanding invoices: cached at sync time as part of
`local_party.payload_json` (denormalized). Stale-but-good for
allocation purposes. Pull-to-refresh forces a sync.
POST: queues.

### Expense screen
Category picker: local read from `local_expense_category`.
POST: queues.

### Products list / Product detail
List: local query, instant.
Detail: same. Stock adjustments queue.

### History screens
Last 30 days from `local_transaction`. Pull-to-refresh extends
the window via `get_transactions_delta`. Older history hits
the network on demand.

### New Item editor
Local search: matches against `local_shop_item` (existing
items on this shop) for dup detection.
Global catalog suggestions: still online-only (cross-shop;
not worth mirroring). Graceful degradation: when offline, hide
the suggestions chip and show "Suggestions need internet —
keep typing to add manually."
POST: queues.

## Graceful UX states (per screen)

The four states from the previous plan now collapse to three
in local-first mode (because local DB is always present after
first sync):

- **First-time setup (no local data, offline)**: blocking
  "Connect to load your shop's data" card with Retry.
- **Working** (online or offline, has local data): screens
  render instantly. No loading spinners on regular reads.
- **Sync issue** (offline > 24 h, pending queue > N posts,
  realtime disconnected for > 10 min): subtle banner at top
  *"Working offline since [time]. Tap to sync."* Non-blocking.

Connection state is shown in the existing AppBar via the queue
status pill — extended to also show "offline since X" when
realtime is down.

## Feature flag

`platform_config` / `shop_setting` key `use_local_db` (bool):
- `true` (default): LocalRepository + sync engine active.
  Reads from local sqflite mirror; writes queue for background
  drain.
- `false`: thin-client mode. Reads hit the network; SWR caches
  per #369 accelerate. Writes — see `#383` — will go direct to
  server (no queue) once that commit lands.

Resolution: `useLocalDb(context)` / `resolveUseLocalDb(resolver)`
from `lib/sync/use_local_db.dart`. Read at session load + on
shop switch.

**Legacy `offline_mode` rows** set before `#382` continue to
resolve via the dual-key parser (`'full'` → true, `'light'` →
false) for one release. Drop in `#385`.

UI surfaces the choice in two places:
- **Shop-admin web** (owner-tunable, planned in `#384`):
  Setup tab → "Use local DB: On / Off". Defaults to On.
- **System-admin portal** (per-org overrides): platform staff
  can flip for an entire org for staged rollout (future).

The app's read paths branch at `LocalRepository`:
```dart
Future<List<ShopItemRow>> searchItems(String q) {
  if (useLocalDb(context)) {
    return _local.searchItems(q);  // sqflite
  }
  return _api.searchItems(q);       // network
}
```

Mutations: queued + drained in `useLocalDb=true`; direct +
fail-fast in `useLocalDb=false` (per `#383`).

## Phased delivery

This is too big for one commit. Three commits, in order.

### `#373` — Foundation: schema + sync engine + feature flag (medium)

- Migration `0002_local_mirror.dart` adds the mirror tables.
- Backend migration `0069_full_sync_rpcs.sql` adds the new
  RPCs + the missing `updated_at` columns + triggers.
- `lib/sync/sync_engine.dart` — full-sync + delta-sync logic.
- `lib/sync/local_repository.dart` — abstraction over the
  mirror tables.
- `ConfigKeys.offlineMode` added; defaults to `light`. Existing
  behavior unchanged when the flag is off.
- No UI wiring yet. Sync engine runs when flag is on but
  screens still read from network.

This commit is **invisible to the user** unless they're a test
shop with the flag flipped on. Lets us land + test the
plumbing without disrupting pilot.

### `#374` — Wire daily-flow reads to LocalRepository

When flag is `full`:
- Sale + Receive search → LocalRepository.
- Sale + Receive barcode → LocalRepository.lookupBarcode.
- Payment + Receive party pickers → LocalRepository.
- Expense category picker → LocalRepository.
- Product list + detail → LocalRepository.
- Stock projection wiring for queued sales/receives.

When flag is `light` → existing behavior; no regression.

### `#375` — History + UX polish + sale receipt offline

When flag is `full`:
- Sale / Receive / Payment / Expense history → LocalRepository.
- Sale receipt sheet → render from local data, no get_sale call.
  Also fixes the `#371` bug.
- Three UX states (first-sync card, working, sync issue
  banner) implemented via a small shared widget.

## Out of scope (for now)

- **Per-field merge conflict resolution**: pilot uses LWW.
- **Schema evolution mid-session**: if the server changes its
  schema, clients re-do full sync on next launch. Acceptable
  for v1.
- **Multi-shop offline**: each shop has its own local mirror.
  Switching shops triggers a quick sync. Already handled by
  the shop-keyed schema.
- **Background sync via iOS silent push**: nice-to-have for
  freshness. Pilot uses foreground-only.
- **Bono OCR offline**: server-side; stays online. Matching
  layer reuses local catalog.

## Reused utilities

- `OfflineQueueController` (existing) — posts.
- `CacheDao` (existing) — repurposed as legacy fallback for
  `light` mode.
- `ConfigResolver` — flag resolution.
- Existing realtime watcher infrastructure on
  `ProductsScreen` / `PeopleScreen` — extended to drive sync
  engine when flag is `full`.

## Risk

This is a meaningful undertaking. Risks:

- **Server load from full sync**: a 500-item shop's
  `get_shop_full_sync` is ~1 MB JSON. Fine for occasional use
  (first sync), but a cascade of full syncs across many
  devices could spike DB load. Mitigation: enforce
  `get_shop_full_sync` to once per device per 24 h
  server-side; force delta otherwise.

- **Conflict on multi-device edits**: LWW data loss in
  pathological cases. Mitigation: audit log preserves
  history; we can iterate to per-field merge if pilot data
  shows this is a real problem.

- **Storage growth**: capped at ~10 MB for big shops. The
  existing `cache_budget_mb` config key (default 100 MB) is
  the upper bound. Old transactions evict first.

- **Schema drift**: server adds a column the client doesn't
  know about. Mitigation: client reads return shape is
  versioned; client ignores unknown columns; full re-sync on
  major version bumps.

- **Realtime channel limits**: Supabase Realtime has
  per-project channel limits (~500 on Pro). Each device opens
  one channel per shop — fine for pilot but worth monitoring.

## Estimated effort

- `#373` (foundation): ~3-4 days. Mostly backend RPC + Dart
  sync engine + tests.
- `#374` (daily-flow wiring): ~2-3 days. Per-screen
  swapping. Lots of small changes; medium complexity overall.
- `#375` (history + polish): ~1-2 days.

Total: ~7-10 days of focused work. Significantly more than
any prior commit in this conversation, justified by the
scope.

## Verification

Per commit, with a test shop where the flag is enabled:

### `#373`
- Sync engine runs at session start. First time: full sync.
- Toggle airplane mode after full sync. App keeps running.
- Local DB rows present. Existing test suite still passes
  (flag defaults to light = no change).

### `#374`
- Open Sale offline. Items load from local. Add to cart,
  CONFIRM, post queues, stock projection updates. Receipt
  sheet shows the sale.
- Same for Receive, Payment, Expense, Products.
- Re-enable network: queue drains, stock projections clear,
  local DB updates via realtime/delta sync.

### `#375`
- Open Sales History offline. Last 30 days visible.
- Cold start with no local data + offline: first-sync card
  appears.

Plus existing 400-test suite stays green throughout.
