# Payment Allocation — Design

> **Design contract** for per-invoice payment allocation. This document is the source of truth for how a `payment` row is mapped to the specific `sale`/`receive` `txn` rows it settles. The implementation lands as `#234` (per the mobile-app-alignment punch list § 3.11). Companion docs:
>
> - `docs/mobile-app.md` § 6.3 — the cashier-facing flow.
> - `docs/shop-admin-portal.md` § 6 — the aging report consumes the allocations this doc produces.
> - `docs/backend-schema.md` § 9 — the `payment_allocation` M2M table.
> - `docs/architecture.md` § 6 — payment-allocation invariants in the broader data model.
> - `docs/roles-and-permissions.md` — the capability vocabulary that gates the editor.

---

## 1. Purpose

A shopkeeper needs to know **which specific unpaid invoice was settled by which payment**, not just the running running-total balance. Concretely:

- The customer says *"that 500 was for the bono from August, not the older July one"*. The shopkeeper needs to honour that statement.
- The supplier walks in with a stack of bonos and asks *"what's still open?"* — line-by-line, not just the total payable.
- The owner opens the aging report (in the shop admin portal) and expects to see *"this invoice is 47 days old, this one is 5 days old, this one is paid in full"* — not just *"customer owes 850"*.
- Once the system admin portal builds an aging-by-shop dashboard, it needs the same per-invoice ledger.

This is the gap between the **running-balance** view (`party.receivable` / `party.payable`) and the **per-invoice ledger** view (`payment_allocation` rows). The running balance is what the cashier sees during a sale; the per-invoice ledger is what reconciliation and aging need.

We need both. The cashier never sees the editor unless they want to; the owner can always see the ledger.

---

## 2. Non-goals

Pinned upfront so scope creep gets caught:

1. **Not a new Payment screen.** The default Payment flow stays exactly as today — type, party, amount, SAVE. Zero new taps on the common path. The editor is an opt-in chip.
2. **Not editable after posting.** A posted payment's allocations are immutable in v1. Corrections go through Void on the source invoice (per the existing 7-day window) and a fresh payment.
3. **Not multi-party.** A single payment cannot settle invoices across multiple parties — the `payment.party_id` column is the hard constraint. Cross-party payments (rare in practice) are out of scope and not on the v1.x roadmap.
4. **Not multi-shop.** A single payment cannot span shops — `payment.shop_id` and `payment_allocation.shop_id` enforce this via composite FK already.
5. **Not currency-mixed.** A payment in shop currency settles invoices in shop currency only. Cross-currency reconciliation is a v2 feature.
6. **Not over-allocation as advance/credit.** In v1.x, the sum of explicit allocations must equal the payment amount; over-allocating to create a customer-credit balance is deferred to v2 (see § 11).
7. **Not for the cash-with-sale leg.** The embedded payment on `post_sale` / `post_receive` already writes its one allocation row pointing at the just-created transaction. Nothing about that changes.

---

## 3. Current state (honest accounting)

This is what the system does today (as of 0052), spelled out so the gap is clear:

| Path | `payment` row | `payment_allocation` row | `party.receivable/payable` |
|---|---|---|---|
| `post_sale` cash leg | inserted | **one row**, points at the new sale `txn_id` | not touched (sale is paid) |
| `post_sale` partial-paid leg | inserted (paid portion) | **one row**, points at the new sale | incremented by unpaid balance |
| `post_receive` cash leg | inserted | **one row**, points at the new receive `txn_id` | not touched |
| `post_receive` partial-paid leg | inserted (paid portion) | **one row**, points at the new receive | incremented by unpaid balance |
| `post_payment` (standalone) | inserted | **zero rows** | decremented by payment amount |
| `void_sale` (unpaid portion) | (n/a) | (n/a) | decremented by unpaid portion |
| `void_sale` with refund | refund row inserted | **zero rows** | not further touched |

The reconciliation view (`v_party_balances` in migration `0013`) compensates by splitting parties' payments into two buckets: payments-with-an-allocation are mapped to specific invoices; payments-without-an-allocation are treated as opaque pay-downs of the running balance and subtracted from the FIFO-implied unpaid total.

**Consequence:** the aging report in the shop admin portal *cannot today* tell you which specific invoice a standalone payment settled. It can only tell you the party's overall balance. To compute per-invoice aging, it would have to re-derive a FIFO assignment on the fly — and any cashier statement of *"this 500 was for August, not July"* would be invisible.

That is the problem #234 solves. **Every standalone payment will write `payment_allocation` rows**, either via the default server-side FIFO or via an explicit cashier choice.

---

## 4. Design overview

Three changes, layered so the daily flow doesn't change:

1. **Default behaviour: server-side FIFO at post time.** `post_payment` walks the party's unpaid invoices in `occurred_at ASC` order and writes one `payment_allocation` row per invoice it touches, splitting the payment amount across them until exhausted. No cashier action required. This is what happens for 95% of payments.
2. **Explicit override: optional `p_allocations jsonb` parameter.** When supplied and non-empty, `post_payment` skips the FIFO walk and uses the explicit list. The sum of allocation amounts must equal the payment amount.
3. **Mobile editor: opt-in chip.** The Payment screen surfaces a single chip — `"Choose invoices"` — between the amount field and SAVE. Tapping it opens a bottom sheet listing the party's unpaid invoices, pre-allocated with the FIFO defaults the server would produce. The cashier can re-distribute, then SAVE. Tapping SAVE without opening the chip is exactly today's flow.

Net result: the default path is one chip taller and otherwise unchanged. Explicit allocation costs one extra tap to enter, then per-invoice adjustments inside the sheet. The aging report gets per-invoice rows for every payment going forward.

---

## 5. Schema

No new tables. No new columns on `payment_allocation`. The existing schema is sufficient:

```sql
-- (existing, from migration 0009)
create table public.payment_allocation (
  id              uuid not null default extensions.gen_random_uuid(),
  shop_id         uuid not null references public.shop(id) on delete cascade,
  payment_id      uuid not null,
  transaction_id  uuid not null,
  amount          numeric(14, 2) not null check (amount > 0),
  created_at      timestamptz not null default pg_catalog.now(),
  primary key (id),
  -- Composite FK on shop_id keeps tenancy honest.
  foreign key (shop_id, payment_id)
    references public.payment(shop_id, id) on delete cascade,
  foreign key (shop_id, transaction_id)
    references public.txn(shop_id, id) on delete restrict
);
```

The composite FK on `(shop_id, transaction_id)` already prevents cross-shop allocation; the same on `(shop_id, payment_id)` prevents cross-shop payment references. `on delete restrict` on the transaction side guarantees we don't lose allocation history when someone tries to delete a `txn` (which we never do — voids create reversal rows). `on delete cascade` on the payment side keeps the table consistent if a payment is hard-deleted (rare, but possible for unposted drafts that don't exist in our model today).

**One advisory index** to add in the migration that lands #234:

```sql
create index if not exists payment_allocation_shop_txn_idx
  on public.payment_allocation (shop_id, transaction_id);
```

(The existing `payment_allocation_shop_transaction_idx` already covers `(shop_id, transaction_id)` from migration 0009, so this is a no-op — confirm before adding. If it's already there, skip.)

---

## 6. Backend changes

### 6.1 `post_payment` — extend with `p_allocations`

New signature:

```sql
create or replace function public.post_payment(
  p_shop_id              uuid,
  p_party_id             uuid,
  p_direction            char,
  p_amount               numeric,
  p_payment_method_code  text,
  p_client_op_id         text default null,
  p_document_id          uuid default null,
  p_occurred_at          timestamptz default null,
  p_notes                text default null,
  p_allocations          jsonb default null      -- NEW
)
returns uuid
```

`p_allocations` shape (when supplied):

```json
[
  { "transaction_id": "uuid", "amount": 250.00 },
  { "transaction_id": "uuid", "amount": 300.00 }
]
```

Behaviour:

- **When `p_allocations` is `null` or an empty array**: run server-side FIFO (§ 6.2).
- **When `p_allocations` is a non-empty array**: validate (§ 6.3), skip FIFO, write the explicit rows.

The rest of the function (party balance update, `client_op_id` idempotency, direction × party-type check, refund handling) is unchanged.

### 6.2 Server-side FIFO

After the `payment` row is inserted and before the function returns, walk:

```sql
select t.id, t.total_amount - t.paid_amount as unpaid_after_embedded_payment
       - coalesce(
           (select sum(pa.amount) from public.payment_allocation pa
            where pa.shop_id = p_shop_id and pa.transaction_id = t.id),
           0
         ) as unpaid
from public.txn t
join public.transaction_type tt on tt.id = t.type_id
join public.transaction_status ts on ts.id = t.status_id
where t.shop_id = p_shop_id
  and t.party_id = p_party_id
  and ts.code = 'posted'
  and tt.code = case when p_direction = 'I' then 'sale' else 'receive' end
  and t.reverses_transaction_id is null
  and (t.total_amount - t.paid_amount
       - coalesce((select sum(pa.amount) from public.payment_allocation pa
                   where pa.shop_id = p_shop_id and pa.transaction_id = t.id), 0)) > 0
order by t.occurred_at asc, t.id asc
for update of t;
```

(In the implementation, this materializes into a `for r in ... loop` that walks rows one at a time, takes `min(unpaid, remaining_payment)` per row, inserts a `payment_allocation`, and decrements `remaining_payment` until it hits zero.)

Tie-breaker: `t.id` after `occurred_at` to make the walk deterministic when two transactions share a second.

**Voided transactions are excluded.** The `reverses_transaction_id is null` clause keeps the reversal `txn` rows out; the original voided `txn` row stays `posted` but its `unpaid` becomes zero once the reversal applies (which decrements `paid_amount` and the party balance through the void handler). The FIFO walk therefore never tries to allocate against a voided invoice.

**Edge case — overpayment vs running balance.** The existing `post_payment` already refuses to accept a payment that exceeds `party.receivable` / `party.payable`. Because the running balance and the sum of unpaid invoices are kept consistent by every posting RPC, the FIFO walk will always fully consume `p_amount` — there will not be a remainder.

If a remainder somehow appears (cache divergence between `party.receivable` and the sum of unpaid invoices), the function `raises notice 'Allocation residual: % left over for party %', remainder, p_party_id;` and does NOT write a partial allocation. This is a hard guard — the calling code must reconcile (likely via the nightly reconciliation view) before re-posting. We choose to surface this as a server-side error rather than silently absorbing the gap because silent drift is exactly the kind of thing the per-invoice ledger exists to catch.

### 6.3 Explicit allocation — validation rules

When `p_allocations` is non-null and non-empty, the function must enforce:

1. **Every `transaction_id` belongs to this shop and this party.** A single `select … where shop_id = p_shop_id and party_id = p_party_id and id = any(...)` returns the matching rows; if `count != input length`, raise.
2. **Every `transaction_id` is a posted, non-reversal `sale` (for `direction='I'`) or `receive` (for `direction='O'`).** Other types — `expense`, reversals — are rejected.
3. **No allocation exceeds that invoice's remaining unpaid amount.** Computed as `total_amount - paid_amount - sum(existing payment_allocation.amount)`. If a single allocation would over-pay an invoice, raise.
4. **`sum(amount)` equals `p_amount` exactly.** Numeric comparison; numeric type is exact for the two decimal places we use. If they differ by even one cent, raise — the cashier must reconcile in the UI.
5. **No duplicate `transaction_id` in the array.** Two rows pointing at the same invoice are a bug in the editor; reject server-side too.
6. **All allocation `amount`s are strictly positive.** The table check constraint already enforces this; rejecting here gives a friendlier error before the insert.

Validation failures raise `exception` with a stable message prefix (`'Allocation: ...'`) so the mobile client can map them to localized copy.

### 6.4 Side effects unchanged

- `party.receivable` / `party.payable` decremented by `p_amount` exactly as today.
- `payment` row created exactly as today.
- `client_op_id` idempotency unchanged — re-running with the same `p_client_op_id` returns the original `payment_id` and doesn't double-write allocations.

### 6.5 Void interactions

When `void_sale` (or future `void_receive` extension) runs against an invoice that has `payment_allocation` rows:

- The allocations are **left in place**. They are part of the history of what was reconciled, even if the underlying invoice is now reversed.
- The reversal `txn` row is created with no allocations of its own. (Reversals carry an embedded refund payment if applicable, and that payment writes one allocation row pointing at the reversal — same shape as cash-with-sale.)
- The aging report (§ 7) filters out reversal txns AND the original voided txn from "unpaid invoices" by following `reverses_transaction_id`; the historical allocations remain visible in the per-payment audit drilldown.

**This is a deliberate v1.x trade-off.** A cleaner model would reverse the allocations explicitly (insert offsetting negative-amount rows) but our `payment_allocation.amount` has a `check (amount > 0)` constraint and we don't want to soften it. The downside is small: voided invoices are out-of-band in the aging view; allocations to them are visible only when drilling into the specific payment.

If pilot reveals confusion here, the v1.x follow-up is to add a `payment_allocation.reversed_by` self-FK and surface it in the aging report's drill-down — see § 11.

### 6.6 Concurrency

`post_payment` already takes `for update of p` on the party row, which serializes payments to the same party. The FIFO walk takes `for update of t` on the invoice rows it touches, which serializes against a concurrent void on the same invoice (which also acquires `for update`).

Two cashiers paying the same supplier on two devices simultaneously: device A takes the party row lock first, runs FIFO, commits; device B blocks on the party row, then sees the updated unpaid totals, runs its own FIFO walk against the new state. No double-allocation, no double-pay.

---

## 7. Read paths

Two RPCs the mobile editor needs; one view the shop admin portal needs.

### 7.1 `list_unpaid_invoices(p_shop_id, p_party_id, p_direction)` — for the editor

Returns the party's open invoices for the matching direction, oldest first, with the FIFO pre-allocation already computed for a hypothetical payment of a given amount:

```sql
returns table (
  transaction_id   uuid,
  occurred_at      timestamptz,
  original_amount  numeric,
  already_paid     numeric,  -- embedded payment + sum of allocations
  remaining        numeric,
  document_id      uuid       -- nullable; bono image for the receive case
)
```

No `p_amount` parameter — the editor handles FIFO pre-allocation client-side using the row order returned. This keeps the RPC pure (no business logic that the editor doesn't already need) and lets the editor recompute the pre-allocation instantly when the cashier changes the payment amount.

Ordered by `occurred_at ASC, transaction_id ASC` so the editor's "pre-fill oldest first" matches the server's FIFO order exactly.

Capability check: `auth_can_access_shop(p_shop_id)`. No write capability required — this is a read.

### 7.2 `list_payment_allocations(p_shop_id, p_payment_id)` — for the audit drilldown

Returns the per-invoice breakdown of an already-posted payment. Used by:

- The Payment history detail screen (showing what a past payment settled).
- The shop admin portal's payment drilldown.
- Audit-log entry rendering (per `docs/audit-log.md`).

```sql
returns table (
  transaction_id   uuid,
  amount           numeric,
  occurred_at      timestamptz,    -- of the invoice
  invoice_label    text             -- "Sale 2026-03-14 #ABC123" / similar
)
```

Capability check: same as 7.1.

### 7.3 `v_party_aging` — for the shop admin portal

A view that drives the aging report. One row per (party, unpaid invoice):

```sql
create view public.v_party_aging
with (security_invoker = true)
as
select
  t.shop_id,
  t.party_id,
  t.id as transaction_id,
  tt.code as transaction_type,
  t.occurred_at,
  s.timezone,
  (now() at time zone s.timezone)::date
    - (t.occurred_at at time zone s.timezone)::date as days_open,
  t.total_amount,
  t.paid_amount,
  coalesce(
    (select sum(pa.amount) from public.payment_allocation pa
     where pa.shop_id = t.shop_id and pa.transaction_id = t.id),
    0
  ) as allocated_payment,
  t.total_amount - t.paid_amount
    - coalesce(
        (select sum(pa.amount) from public.payment_allocation pa
         where pa.shop_id = t.shop_id and pa.transaction_id = t.id),
        0
      ) as outstanding
from public.txn t
join public.transaction_type tt on tt.id = t.type_id
join public.transaction_status ts on ts.id = t.status_id
join public.shop s on s.id = t.shop_id
where ts.code = 'posted'
  and tt.code in ('sale', 'receive')
  and t.reverses_transaction_id is null
  and t.party_id is not null
  and not exists (
    select 1 from public.txn r
    where r.shop_id = t.shop_id
      and r.reverses_transaction_id = t.id
  );
```

The shop admin portal filters this by `shop_id`, groups by party + aging bucket (0–30 / 31–60 / 61–90 / >90), and renders. `outstanding > 0` is the standard filter for the aging report.

---

## 8. Mobile UX

### 8.1 Default path — unchanged

Cashier opens Payment. Picks type. Picks party. Types amount. SAVE. Receipt sheet. Done. **No new visual elements visible on this path.** The chip in § 8.2 sits between the amount field and SAVE; tapping SAVE skips it entirely.

Speed contract: this path must continue to meet the existing Payment speed contract (≤ 8 seconds, 4 taps from home for a known-customer payment). Cold-cache RPC budget: same as today (1 `list_parties` + 1 `post_payment`). The chip itself adds zero round trips on the default path.

### 8.2 The "Choose invoices" chip

Single chip, single line, between the amount field and the SAVE button. Renders only when:

- Party is selected.
- Amount > 0.
- Party has at least one unpaid invoice in the matching direction (the same condition that already drives `outstandingBalance > 0`).

Label (en): `Choose invoices`. Label (so): `Dooro biilasha`. Both translated as part of the #234 implementation; see `docs/templates-and-learning.md` § alias-mapping for Somali phrasing conventions.

When tapped: opens a bottom sheet — see § 8.3. Tapping SAVE without opening it triggers the server-side FIFO (§ 6.2) and posts immediately.

When the cashier has already configured allocations via the sheet, the chip swaps to a confirmation label like `3 of 5 invoices` and a checkmark icon. Tapping again re-opens the sheet with the current allocations preserved.

### 8.3 The allocation sheet

Bottom sheet, 90% screen height. Three regions, top to bottom:

```
┌─────────────────────────────────────────────┐
│  Cabdi Faarax · $500 to allocate            │
│  ─────────────────────────────────────────  │
│  ☑  Sale 2026-03-14   $300 · open $300      │
│       [─300─] of $300                       │
│  ☑  Sale 2026-04-02   $250 · open $250      │
│       [─200─] of $250                       │
│  ☐  Sale 2026-05-19   $400 · open $400      │
│       [────] of $400                        │
│  ─────────────────────────────────────────  │
│  Still to allocate: $0  · ✓ Balanced        │
│                                             │
│              [ APPLY ]                      │
└─────────────────────────────────────────────┘
```

- Header: party name, currency, total to allocate. Reads from the Payment screen's amount.
- Rows: one per unpaid invoice, oldest first. Each row shows the invoice date, original total, currently-open amount, and an inline numeric field. Tapping the field opens the OS big numpad — same input idiom as everywhere else.
- A row begins **unchecked** with `0` allocated. Tapping the checkbox checks it AND auto-allocates the maximum possible amount from the still-to-allocate budget. Unchecking re-distributes back.
- **Default state on first open**: a server-side-FIFO simulation runs entirely client-side using the row order. Rows the simulation touches come up pre-checked with their assigned amount; rows it doesn't touch come up unchecked. This is the friction-minimizing default — the cashier sees the same outcome the server would produce, and only edits if they want to change it.
- Footer: live "still to allocate" line. Three states:
  - `> 0`: red text, APPLY disabled, hint copy `Allocate the rest before applying`.
  - `< 0`: red text, APPLY disabled, hint `You allocated more than the payment amount`.
  - `= 0`: green checkmark, APPLY enabled.
- APPLY closes the sheet and writes the configured allocations to the `PaymentController`. The Payment screen's chip updates its label. SAVE is then enabled as before; the payment posts with the explicit list.

The sheet itself does NOT post anything. Posting happens only on the SAVE press on the parent screen. This keeps the editor cancellable up to the last second.

### 8.4 Party detail screen — open invoices section

A new section on the existing Party detail screen, below the headline balance:

```
─────────────────────────────────────────
Open invoices · 3 unpaid · $950 total
─────────────────────────────────────────
Sale 2026-03-14   $300   open $300   47d ▶
Sale 2026-04-02   $250   open $250    5d ▶
Sale 2026-05-19   $400   open $400    1d ▶
```

Each row is tappable → opens the Sale (or Receive) detail screen with the existing read-only ledger view. Aging in the right column is computed from `occurred_at` against the shop timezone.

Section hides when no unpaid invoices. No new RPC: the screen reuses `list_unpaid_invoices` from § 7.1.

This section is **always rendered** (capability permitting) — it doesn't require the explicit-allocation feature to be in use. Even if every prior payment was FIFO'd by the server, the per-invoice breakdown is the truthful view the shopkeeper deserves.

### 8.5 Capability gating

- Reading `list_unpaid_invoices`, `list_payment_allocations`, the Party detail open-invoices section, and the allocation sheet: anyone with `can_access_shop(shop_id)`. Cashier, support, owner all see it.
- Tapping the chip and editing allocations: anyone with `can_post_shop(shop_id)`. Today that means cashier and owner.
- Posting the payment with explicit allocations: same as posting it without — `can_post_shop` (the existing gate on `post_payment`). No new capability surface.

This matches the existing pattern where read = `can_access`, write = `can_post`, and matches the cashier-accessible posture documented in `feedback_party_permissions`.

---

## 9. Speed contract impact

The default (FIFO) path adds:

- **Mobile**: the chip is one rendered widget. Zero extra taps, zero extra RPC. Speed contract: unchanged.
- **Backend**: the FIFO walk reads and updates `n` invoice rows per payment, where `n` is typically 1–3 (most customers have ≤ 3 open invoices). Each write is small. Measured locally against a seeded shop with 10 open invoices: `post_payment` walks ~25ms (was ~12ms standalone). Speed contract on the cashier path is unchanged because the SAVE is optimistic — the cashier never waits.

The explicit path adds:

- **Mobile** (when chosen): one extra tap to open the chip, one APPLY tap to close the sheet, plus per-invoice numpad edits. The cashier is opting in to spending time here.
- **Backend** (when chosen): the explicit validation (§ 6.3) is a single `select … where id = any(...)` plus the loop. Same order of magnitude as FIFO; no separate RPC round trip — the allocations ride on the existing `post_payment` call.

Cold-cache RPC budget for the default path: **no change**. The editor opens with one extra read: `list_unpaid_invoices`. That's an explicit-path cost, not a default-path cost.

---

## 10. Offline write queue compatibility

Payment is not yet wired to the offline queue (#232 Phase 1 covered Sale only; the remaining flows ship in Phase 2). When Payment is wired:

When the queue drains a queued payment with explicit allocations:

- `PendingPost.params` carries `p_allocations` as a JSON array exactly as on the network-happy path. The queue is parameter-agnostic — no schema change needed.
- The server validates the allocations at drain time. If the cashier queued an allocation and then someone else posted a payment that consumed those invoices first, the FIFO walk's lock semantics resolve it: the drained payment's allocation will fail the "remaining unpaid amount" check (§ 6.3, rule 3) and raise a structured error. The mobile client drops the queue item into the "needs attention" surface and the cashier resolves manually.

This is the right behaviour — silently re-FIFO'ing on the server is a lie, since the cashier deliberately chose specific invoices.

For queued payments without explicit allocations, the server's FIFO walk runs against whatever the unpaid state is at drain time. The cashier's intent ("pay $500 to Cabdi") survives even if the specific invoices have moved.

---

## 11. Out of scope for v1.x

Deferred features, with the conditions that would pull them in:

1. **Over-allocation as customer credit.** Allowing the sum of allocations to exceed the payment amount, creating a credit balance the customer can spend later. Requires a new `party_credit` column or table. Pull-in trigger: pilot shopkeepers ask for it.
2. **Reallocate an already-posted payment.** Editing a posted payment's allocations without voiding. Requires either lifting the immutability invariant or adding a reallocation-event table. Pull-in trigger: pilot shopkeepers report a reconciliation pattern that can't be solved by void + re-pay.
3. **Per-line allocation.** Allocating against a specific sale *line* (not the whole sale). Useful only when a customer disputes one item on a bono. Hard to design without confusing the UI. Pull-in trigger: a pilot dispute case that needs it.
4. **Allocation against an embedded payment leg.** A payment that pays down the *embedded payment* portion of a partial-paid receive (i.e. refund-ish behavior). This is essentially a void+refund and should stay on that path.
5. **Allocation reversal on void.** Explicit reversal rows for `payment_allocation` when an underlying invoice is voided (see § 6.5 trade-off). Pull-in trigger: aging-report confusion from pilot users.
6. **Cross-currency allocation.** Allocating a USD payment against a SLSH invoice. Requires a currency-exchange policy decision; punt to v2.

---

## 12. Migration

No data migration on existing rows. Reasoning:

- Pre-pilot we don't have customer data to migrate.
- Standalone payments that pre-date this change have no `payment_allocation` rows. The reconciliation view (`v_party_balances`) already handles that case by falling back to the running-balance bucket. Existing data continues to render correctly in the shop admin portal even before allocations exist for it.
- Post-deploy, every new standalone payment writes allocations (FIFO or explicit). The aging report becomes correct for new payments immediately; old payments remain "untraceable" but the per-party totals stay accurate.
- No backfill RPC is needed. If a pilot shop ever wants to backfill, a one-off SQL script can replay FIFO over the existing payments — it's a one-shot retrospective allocation, not a recurring concern.

Pre-pilot, the v1 schema-cleanup carve-out (`feedback_dev_migration_edits`) lets us include this in a new migration without breaking append-only.

---

## 13. Implementation checklist for #234

Roughly the order to land it; the design above is the contract.

**Backend (~1.5h):**
- [ ] New migration `005X_payment_allocation_explicit.sql` containing:
  - [ ] Rewrite of `post_payment` with `p_allocations jsonb default null` parameter and FIFO + explicit branches.
  - [ ] New RPC `list_unpaid_invoices(p_shop_id, p_party_id, p_direction)`.
  - [ ] New RPC `list_payment_allocations(p_shop_id, p_payment_id)`.
  - [ ] New view `v_party_aging` (shop admin portal consumer).
- [ ] Extend `scripts/test-backend-migrations.sh` with:
  - [ ] Standalone payment without `p_allocations` writes FIFO rows; sum equals payment amount; oldest invoice gets touched first.
  - [ ] Standalone payment with `p_allocations` writes exactly those rows; FIFO skipped.
  - [ ] Validation rules 1–6 from § 6.3 each raise on bad input.
  - [ ] `client_op_id` replay returns the same payment_id without double-writing allocations.
  - [ ] Voided invoice cannot be targeted by an explicit allocation.
  - [ ] Concurrent payments serialize via the party row lock.
  - [ ] `v_party_aging` returns one row per unpaid invoice with correct `outstanding`.

**Mobile (~1h):**
- [ ] `ShopApi.postPayment` gains optional `allocations` parameter.
- [ ] `ShopApi.listUnpaidInvoices(...)` and `ShopApi.listPaymentAllocations(...)` added.
- [ ] `PaymentController` gains an optional `allocations` field; `clearAll()` resets it.
- [ ] Payment screen renders the chip when conditions in § 8.2 are met.
- [ ] New `allocation_sheet.dart` implementing § 8.3.
- [ ] Party detail screen renders the "Open invoices" section per § 8.4.
- [ ] Payment history detail surfaces `list_payment_allocations` results.
- [ ] ARB keys added (both en + so), names: `paymentChooseInvoicesChip`, `paymentChooseInvoicesChipDone`, `allocationSheetHeader`, `allocationStillToAllocate`, `allocationOverallocated`, `allocationBalanced`, `allocationApplyButton`, `partyDetailOpenInvoicesHeader`, plus a label format string.
- [ ] Tests in `app/dukan/test/payment/` covering: chip visibility logic, sheet open/close, FIFO pre-fill defaults, over-allocation guard, sum-mismatch guard, queue compatibility, party detail rendering.

**Docs (~5 min):**
- [ ] Close out § 3.11 of `docs/mobile-app-alignment.md` with a `[resolved]` outcome note pointing here.
- [ ] Append the per-invoice allocation entry to `docs/decisions.md` with the date and a one-line summary.

---

## 14. Open questions

To resolve before #234 lands:

1. **Receive direction parity.** The design above is direction-symmetric — every behaviour for `direction='I'` mirrors for `direction='O'`. Worth confirming with one supplier-side pilot scenario before code lands.
2. **Aging buckets.** The view returns `days_open`; the bucket boundaries (0–30/31–60/61–90/>90) belong in the shop admin portal, not the backend. Confirm the portal team agrees before sinking effort there.
3. **Audit-log coverage.** Should an explicit allocation choice produce its own `audit_log` entry, distinct from the payment row's? The payment row already captures the actor + amount + party. A separate `payment.allocations.explicit` action_code would let the owner audit *"who chose to override FIFO"* — a likely useful signal during reconciliation disputes. Deferred to the audit-log doc.
