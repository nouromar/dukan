# Offline + caching smoke test (iPhone, release build)

Validation pass for the mobile work shipped in `#363`-`#369` —
sqflite foundation, safeguards, hierarchical config, Storage &
sync screen, queue extension to Receive/Payment/Expense,
audit-stamping, and SWR caching for the heaviest read surfaces.

Run end-to-end before each pilot rollout. Each numbered section
is self-contained — you can skip ahead if the prerequisite step
isn't relevant to what you're validating.

## Prerequisites

1. **Deploy the two backend migrations** to the hosted Supabase
   project — both are new files (no in-place edits) so
   `supabase db push` picks them up cleanly:
   - `supabase/migrations/0067_platform_config.sql` (Phase 3)
   - `supabase/migrations/0068_audit_original_actor.sql`
     (Phase 5A)
2. **Build the release IPA** pointed at hosted Supabase:
   ```bash
   cd app/dukan
   flutter build ios --release \
     --dart-define=SUPABASE_URL=... \
     --dart-define=SUPABASE_ANON_KEY=...
   ```
3. **Install on iPhone** via Xcode or TestFlight.
4. **Sign in** to your test shop. Have a few seeded items + a
   customer with a balance + a supplier with a balance handy.

---

## 1. Migration safety (Phase 1)

**Goal:** confirm queued posts from the OLD SharedPreferences
format migrated cleanly to sqlite.

- **If upgrading from a build older than `#363`:** install the
  new build over it. On first launch the app runs the one-shot
  SharedPreferences → sqlite migration. Old pending posts (if
  any) appear in the queue badge; old TodaySummary numbers
  paint instantly on home.
- **If clean install:** no-op for this section.

**Pass:** app opens normally, no crash, no data lost.

---

## 2. Offline write — Sale (the existing path, now backed by sqlite)

**Goal:** confirm offline Sale still works end-to-end after the
sqlite swap.

1. Enable Airplane Mode.
2. Open Sale → pick an item → CONFIRM. Toast says *"Saved ✓"*.
3. Repeat 2 more times — 3 sales queued total.
4. Look at the AppBar — queue badge shows `3` with cloud-off
   icon.
5. Drawer → Storage & sync. Verify:
   - Status reads *"Offline"*.
   - Pending sales: *"3 waiting"*.
   - Storage used: a few KB shown.
6. Disable Airplane Mode.
7. Within ~30 s the badge counts 3 → 2 → 1 → hidden. (Backoff
   is 5 s on first try; immediate drain on reconnect.)
8. Open Sales history → confirm all 3 sales appear at the top
   with the right amounts.

**Pass:** all 3 sales drain successfully and show in history.

---

## 3. Offline write — Receive / Payment / Expense (new in `#367`)

**Goal:** confirm the three other posting flows now queue
(previously they fail-fast'd).

Repeat the same offline → drain → history-check flow for each:

### 3a. Receive
1. Airplane on → tap Receive → pick supplier → add line(s) →
   SAVE. Toast says saved.
2. Repeat once more.
3. Disable airplane. Watch queue drain to 0.
4. Open Receive history → both receives appear.

### 3b. Payment
1. Airplane on → Payment → pick customer with a balance → type
   amount → SAVE. Toast says saved.
2. Repeat once more (same or different customer).
3. Disable airplane. Queue drains.
4. Payment history shows both.

### 3c. Expense
1. Airplane on → Expense → category + amount + SAVE. Toast says
   saved.
2. Repeat once more.
3. Disable airplane. Queue drains.
4. Expense history shows both.

**Pass:** each flow's "saved" toast fires instantly even
offline; queue badge shows the right count; everything drains
and appears in history.

---

## 4. Queue safeguards (Phase 2)

**Goal:** confirm the size cap + failed-permanent transition +
sign-out drain don't break.

### 4a. Sign-out with pending queue
1. Enable airplane, do 1 sale.
2. Drawer → sign out.
3. Confirm dialog appears: *"X posts not yet synced. Sign out
   anyway?"* with Cancel as default. Tap **Cancel** → stays
   signed in.

### 4b. Sign out anyway
1. Tap sign out again, tap *"Sign out anyway"*. Sign-out
   completes.
2. Sign back in. Disable airplane.
3. The queued sale still drains (per-user data; `#368`'s
   audit-stamping preserves the original cashier).

---

## 5. New Item with opening stock (`#368` audit-stamping in action)

**Goal:** confirm new-item opening stock posts work and the
audit row stores the cashier.

1. Drawer → Products → Add new item.
2. Fill name, base unit Kg, category. Add a Bag packaging
   (conversion 25, stock 3, price + cost). SAVE.
3. Open the new item's detail. Verify stock = **75 Kg** (3 bags
   × 25). (Requires migration 0068 deployed.)
4. If shop-admin web is set up, check the audit log for that
   opening adjustment — `actor_user_id` AND
   `original_actor_user_id` are both your user_id (same person,
   direct call; no-op visually but the column is populated and
   the path is verified).

**Pass:** stock shows 75 Kg, no error toast.

---

## 6. Storage & sync screen (Phase 4a)

**Goal:** confirm every surface on the screen works.

1. Drawer → Storage & sync.
2. **Status section** with empty queue: *"Connected"* + a
   "Last synced" stamp.
3. **Storage breakdown**: pending KB + cache KB + a fill bar.
4. Tap **Sync now** — spinner runs briefly. Toast:
   - *"Already up to date"* if queue empty
   - *"Synced N posts"* if queue had pending
5. Tap **Free up space** — confirm dialog explains it'll clear
   caches, not sales. Confirm. Toast says *"Cache cleared"*.
   Cached data byte count drops to 0.
6. Back to home → today summary refetches from server (no
   cached value). After ~300 ms the 4 numbers appear.
7. Back to Storage & sync. Toggle *"Sync only on Wi-Fi"* on.
   Kill + reopen the app — toggle stays on.
   - Note: Wi-Fi enforcement itself is TODO; toggle persists
     the preference but doesn't yet gate sync. Flagged in the
     `#366` commit body.

**Pass:** every button does what its label says, no crashes,
Wi-Fi toggle persists across app restart.

---

## 7. SWR caching (Phase 5C)

**Goal:** confirm screens paint instantly from cache and refresh
in background.

### 7a. Products list
1. Open Products → wait for first load.
2. Kill the app.
3. Reopen → tap Products.
4. Paints in <100 ms (cache hit), then subtly updates if
   anything changed server-side.

### 7b. Customers list
Same shape: open → close app → reopen → tap Customers. Instant
paint.

### 7c. Sale history
Same shape: open Sales history → kill → reopen → tap Sales
history. Instant paint of the first page.

### 7d. Cache invalidation by TTL
Wait 30+ min between visits to Products → next open does a
fresh fetch (cache TTL expired). Should still feel fast (~300
ms vs ~1500 ms without any caching).

**Pass:** cached screens visibly snap faster on second open
compared to first; data is correct.

---

## 8. Failed posts drill-in

Hard to trigger naturally — a post must fail 50 times in a row.
Skip unless you want to manually corrupt a payload via Storage
& sync → tap *"Failed permanently"* if it shows up. Normally
this section reads `0` and is hidden.

---

## Known gaps you might notice

- **Wi-Fi-only toggle has no effect yet** — UI persists the
  preference; queue doesn't honor it (Phase 5 follow-up).
- **No invalidation on post → cached screens are stale up to
  TTL.** First Products open after a Sale might still show the
  old stock count for up to 30 min. Pull-to-refresh forces
  fresh.
- **Audit log UI** doesn't yet display "Posted by X (drained by
  Y)" — backend stamps both columns; web UI surfacing is a
  Phase 4b follow-up.

## What to report back

If anything in the above smoke test fails or feels wrong, file
the symptom with:
- Which section (e.g., "Section 3b step 3")
- What you expected vs what happened
- Screenshot of the queue badge / Storage & sync screen at the
  time
- iOS version + iPhone model (low-end vs high-end behaves
  differently for cache TTL feel)

Otherwise, the mobile offline + caching work is ready for
pilot.
