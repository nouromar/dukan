# Audit Log — Design

> **Design contract** for the audit-log subsystem. This document is the source of truth for what gets logged, where it lives, how long it survives, how it's read, and how it's protected. The implementation lands as part of `#231 Phase B` and the offline write queue (`#232`) — both share this foundation.
>
> Companion documents:
> - `docs/system-admin-portal.md` § 9 + § 13 — the platform-staff audit feed.
> - `docs/shop-admin-portal.md` § 6.7 — the owner-facing audit feed.
> - `docs/mobile-app.md` § 12 — the inline cues this design powers.
> - `docs/roles-and-permissions.md` — the capability vocabulary that gates reads.
> - `docs/backend-schema.md` — the shared backend.

---

## 1. Purpose

We need an append-only record of **who did what, to which entity, when, and why** for every mutation that affects business state. The audit log exists because:

- Mobile needs inline cues — "voided by Asha 10 min ago" on a sale row, "last edited by Cabdi yesterday" on a price tile.
- The shop admin portal needs a searchable feed for reconciliation, payroll disputes, and onboarding follow-ups.
- The system admin portal needs a tamper-resistant trail of impersonation-era actions for security and compliance.
- Compliance (informal in Hargeisa today; formal in future jurisdictions) requires a record we can produce on request.

What it is **not**: a backup. We don't recover state from the audit log; we observe it.

---

## 2. Non-goals

Pinned upfront so scope creep gets caught:

1. **Not a backup.** Don't try to reconstruct a posted sale from `before_state` — go to the `transaction` row.
2. **Not a tamper-proof chain.** No cryptographic linking or HMAC signing in v1. The DB is the trust boundary.
3. **Not a search index.** No full-text search across `before_state` jsonb. Filtering is structured.
4. **Not for reads.** We don't log "user viewed sale #123." Too noisy, no operational value.
5. **Not for telemetry.** Performance traces go to Sentry, not here.
6. **Not for support transcripts.** Free-form chat with platform staff lives in its own system (future).
7. **Not user-editable.** Append-only. No DELETE or UPDATE from any role.

---

## 3. Schema

### 3.1 Main table — `audit_log`

```sql
create table public.audit_log (
  id                uuid not null default extensions.gen_random_uuid(),
  shop_id           uuid not null references public.shop(id) on delete cascade,
  actor_user_id     uuid references auth.users(id) on delete set null,
  action_code       text not null
    references public.audit_action_code(code) on delete restrict,
  entity_type       text not null,
  entity_id         uuid,                -- single-entity case
  entity_ids        uuid[],              -- bulk-action case; null otherwise
  before_state      jsonb,               -- per-action policy decides
  after_state       jsonb,
  reason            text,                -- required for high-risk actions
  client_op_id      text,                -- ties to originating action
  source            text not null
    check (source in ('mobile','shop_admin_web','system_admin_web','rpc','system')),
  impersonation_session_id uuid,         -- non-null when platform staff acted
  occurred_at       timestamptz not null default now(),
  primary key (occurred_at, id)
) partition by range (occurred_at);
```

Notes on the shape:

- **PK is `(occurred_at, id)`** — Postgres partitioned tables require the partition key (`occurred_at`) to be part of the PK.
- **`entity_id` + `entity_ids`** — one or the other, never both. Single-entity is the common case; bulk operations (admin portal "change category on 50 SKUs") write one row carrying the affected list.
- **`actor_user_id` is nullable** — covers system-triggered actions (cron jobs, trigger-internal writes) and legitimately deleted users.
- **`source` is enforced** — populated from session context, not from a client-supplied parameter. Distinguishes "edited via web by Cabdi" from "edited via mobile by Cabdi."
- **`impersonation_session_id`** — when platform staff act under impersonation (per `docs/system-admin-portal.md` § 9), the audit row records both who *appeared* to act (impersonated user) via `actor_user_id` and which staff session was active. Future RLS can flag impersonation rows specifically.

### 3.2 Action-code registry — `audit_action_code`

```sql
create table public.audit_action_code (
  code              text primary key
    check (code = lower(code) and code ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'),
  area              text not null,       -- 'sale', 'inventory', etc.
  description       text,
  captures_before   boolean not null default false,
  captures_after    boolean not null default false,
  requires_reason   boolean not null default false,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now()
);
```

A reference table of every legal `action_code`. The `_audit_log` helper validates writes against this catalog. Adding a new action code is a migration; foreign-key to `audit_log` ensures no row ever carries an unknown code.

### 3.3 Summary rollup — `audit_summary`

```sql
create table public.audit_summary (
  shop_id           uuid not null,
  day               date not null,
  action_code       text not null,
  actor_user_id     uuid,
  source            text not null,
  count             int not null,
  primary key (shop_id, day, action_code, actor_user_id, source)
);
```

Daily aggregates that survive cold-tier deletion. Powers compliance reports — "how many price edits did Cabdi do in March?" — without keeping individual rows forever.

### 3.4 Partitioning

`audit_log` is partitioned **by month on `occurred_at`**. Pattern:

- Partitions named `audit_log_YYYY_MM`.
- Migration creates **3 partitions ahead** (current + 2 future) so writes never hit "no partition exists."
- Daily maintenance function creates the next month if missing and drops anything older than retention.

### 3.5 Indexes

On the **partitioned parent** (inherited by every partition):

```sql
create index audit_log_shop_recent
  on public.audit_log (shop_id, occurred_at desc);

create index audit_log_entity
  on public.audit_log (shop_id, entity_type, entity_id, occurred_at desc)
  where entity_id is not null;
```

The second index drives "last edit on this row" lookups — the common mobile read pattern. The `WHERE entity_id IS NOT NULL` predicate skips bulk-action rows that would otherwise NULL-pollute the index.

For warm tier (90+ days old), we'll drop the entity-id index per partition once that tier exists — see § 7.

---

## 4. Action codes — v1 registry

Seed in the migration. Grouped by area. Naming: `area.action`. All cashier-facing actions are gated by capability (see `docs/roles-and-permissions.md`) before the audit row is even written.

| Code | Area | before | after | reason? | Notes |
|---|---|---|---|---|---|
| `sale.post` | sale | — | ✅ | — | The `txn` row id; after_state = lines + totals snapshot. |
| `sale.void` | sale | ✅ | ✅ | ✅ | Owner-only; reason required (≥ 20 chars). |
| `receive.post` | receive | — | ✅ | — | |
| `receive.void` | receive | ✅ | ✅ | ✅ | Owner-only; same-shift / 7-day window applies. |
| `payment.post` | payment | — | ✅ | — | |
| `payment.reallocate` | payment | ✅ | ✅ | ✅ | Owner-only; allocation rebalance (#234). |
| `expense.post` | expense | — | ✅ | — | |
| `inventory.product.create` | inventory | — | ✅ | — | shop_item row. |
| `inventory.product.edit` | inventory | ✅ | ✅ | — | Name, category, threshold. |
| `inventory.product.activate` | inventory | — | ✅ | — | Pull from global catalog. |
| `inventory.unit.create` | inventory | — | ✅ | — | New packaging. |
| `inventory.unit.deactivate` | inventory | ✅ | — | — | Soft delete. |
| `inventory.unit.price_edit` | inventory | — | ✅ | — | High-frequency; only after_state. |
| `inventory.unit.default_flag_change` | inventory | ✅ | ✅ | — | Default sale/receive toggle. |
| `inventory.alias.add` | inventory | — | ✅ | — | |
| `inventory.alias.remove` | inventory | ✅ | — | — | |
| `inventory.barcode.add` | inventory | — | ✅ | — | |
| `inventory.barcode.remove` | inventory | ✅ | — | — | |
| `inventory.barcode.set_primary` | inventory | ✅ | ✅ | — | |
| `inventory.adjustment.post` | inventory | — | ✅ | ✅ | Opening / correction / spoilage. |
| `people.party.create` | people | — | ✅ | — | |
| `people.party.edit` | people | ✅ | ✅ | — | Name, phone. |
| `people.party.opening_balance` | people | — | ✅ | ✅ | One-time during onboarding. |
| `setup.shop.edit` | setup | ✅ | ✅ | — | Currency, language, timezone, etc. |
| `setup.staff.invite` | setup | — | ✅ | — | Phone + role. |
| `setup.staff.role_change` | setup | ✅ | ✅ | ✅ | Owner-only; reason required. |
| `setup.staff.revoke` | setup | ✅ | — | ✅ | |
| `auth.session.start` | auth | — | — | — | Sign-in. No snapshot. |
| `auth.impersonation.start` | auth | — | ✅ | ✅ | Platform staff only; reason in subject. |
| `auth.impersonation.end` | auth | — | — | — | |

**Snapshot policy is enforced** — the `_audit_log` helper checks the registry and discards `before_state` / `after_state` arguments the action code doesn't allow. Caller passes everything; the writer drops what's not authorised. Keeps the call-site terse.

---

## 5. The write path

### 5.1 Helper function

Every posting RPC and mutation function calls a single helper:

```sql
create or replace function public._audit_log(
  p_shop_id          uuid,
  p_action_code      text,
  p_entity_type      text,
  p_entity_id        uuid    default null,
  p_entity_ids       uuid[]  default null,
  p_before           jsonb   default null,
  p_after            jsonb   default null,
  p_reason           text    default null,
  p_client_op_id     text    default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meta   public.audit_action_code%rowtype;
  v_source text;
  v_id     uuid;
begin
  select * into v_meta from public.audit_action_code where code = p_action_code;
  if not found then
    raise exception 'unknown audit action_code: %', p_action_code;
  end if;
  if v_meta.requires_reason
     and (p_reason is null or length(btrim(p_reason)) < 20) then
    raise exception 'audit action % requires a reason of at least 20 chars',
      p_action_code;
  end if;
  -- Source resolved from JWT custom claim populated by the client SDK;
  -- defaults to 'rpc' when no claim is present (server-internal writes).
  v_source := coalesce(
    current_setting('request.jwt.claim.source', true),
    'rpc'
  );
  insert into public.audit_log (
    shop_id, actor_user_id, action_code, entity_type,
    entity_id, entity_ids,
    before_state, after_state,
    reason, client_op_id, source
  ) values (
    p_shop_id,
    auth.uid(),
    p_action_code,
    p_entity_type,
    p_entity_id,
    p_entity_ids,
    case when v_meta.captures_before then p_before else null end,
    case when v_meta.captures_after  then p_after  else null end,
    p_reason,
    p_client_op_id,
    v_source
  ) returning id into v_id;
  return v_id;
end;
$$;
```

Idempotency: the `_audit_log` helper does **not** dedupe on `client_op_id`. The posting RPC's own idempotency check (return-early on duplicate `client_op_id`) ensures `_audit_log` is called at most once per action.

### 5.2 Where it's called

The migration that adds `_audit_log` (0050) is followed by 0051 that **instruments every existing posting / mutation RPC**:

- `post_sale`, `post_receive`, `post_payment`, `post_expense`, `post_inventory_adjustment`, `post_opening_party_balance`
- `void_sale`, `void_receive`
- Catalog mutations: `set_shop_item_unit_sale_price`, `set_shop_item_category`, `set_shop_item_reorder_threshold`, `set_shop_item_unit_default_flags`, `deactivate_shop_item_unit`, `add_shop_item_alias`, `remove_shop_item_alias`, `add_shop_item_barcode`, `remove_shop_item_barcode`, `set_primary_shop_item_barcode`, `ensure_shop_item`, `create_shop_item`, `create_shop_item_unit`
- People mutations: `create_party`, `update_party`, `post_opening_party_balance`
- Setup mutations: future `update_shop_defaults`, the planned admin-portal-driven mutations.

Adding the call is a one-liner per RPC. No business logic changes.

### 5.3 Failure behaviour

The audit insert runs in the **same transaction** as the mutation it audits. If the audit insert fails (unknown action code, missing partition, etc.) the mutation rolls back. This is correct — we'd rather refuse a write than lose the audit row. The only writes that bypass audit are explicitly server-internal triggers that update cached projections (`shop_item.current_stock`, etc.), which aren't user-attributable in the first place.

---

## 6. The read path

### 6.1 Mobile entity-scoped read

Used by the Sale detail screen, Product detail packaging tile, Party detail. Returns the last N entries for a specific row, joined with `auth.users` for the actor's name:

```sql
create or replace function public.list_audit_entries_for_entity(
  p_shop_id       uuid,
  p_entity_type   text,
  p_entity_id     uuid,
  p_limit         int default 5
)
returns table (
  id              uuid,
  actor_name      text,
  action_code     text,
  occurred_at     timestamptz,
  reason          text,
  source          text
)
language sql
security definer
stable
...
$$
  select
    a.id,
    coalesce(u.raw_user_meta_data ->> 'display_name', '...'),
    a.action_code,
    a.occurred_at,
    a.reason,
    a.source
  from public.audit_log a
  left join auth.users u on u.id = a.actor_user_id
  where a.shop_id = p_shop_id
    and a.entity_type = p_entity_type
    and a.entity_id = p_entity_id
  order by a.occurred_at desc
  limit p_limit;
$$;
```

The mobile UI only consumes `actor_name`, `action_code`, `occurred_at`, and (occasionally) `reason`. It deliberately does **not** receive `before_state` / `after_state` — those are heavy and rarely actionable for the cashier.

### 6.2 Web admin feed read

Lives outside this design — `docs/shop-admin-portal.md` § 6.7. Returns the filterable feed with snapshots inflated. Drives the audit module's UI.

### 6.3 Inline display patterns

Mobile surfaces audit entries in three places per `docs/mobile-app.md` § 12:

| Surface | Source | Display |
|---|---|---|
| Sale history row (voided) | `sale.void` for the txn | subtitle: "voided by Asha · 10 min ago" |
| Sale detail header (voided) | `sale.void` | banner: same as above, plus reason on tap |
| Product detail price tile | latest `inventory.unit.price_edit` for the packaging | tap-tooltip: "last edited by Cabdi yesterday" |
| Party detail header | latest `people.party.edit` for the party | tap-tooltip: "contact info edited by Asha last week" |

Always read-only on mobile. Never reveals the snapshot. Never lets the cashier filter.

---

## 7. Retention

### 7.1 Tiers (and what we ship for v1)

| Tier | Where | Span | Detail | v1? |
|---|---|---|---|---|
| **Hot** | Postgres, monthly partitions, full indexes | 90 days | full `before` / `after` | ✅ |
| **Warm** | Postgres, partitions stay; entity-id index dropped | 91–365 days | full snapshots, TOAST-compressed | ❌ v1.x at ~500 shops |
| **Cold** | Parquet on object storage | > 12 months | snapshots preserved | ❌ v2 at ~5,000 shops |
| **Summary** | `audit_summary` rollup table | forever | counts only | ✅ |

**v1 ships Tier 1 + Tier 4 only.** That gives us a bounded operational tier and a compliance trail that survives forever.

### 7.2 Maintenance function

Daily, via `pg_cron` (or an Edge Function on a schedule when `pg_cron` isn't enabled — Supabase managed environment supports it):

```sql
create or replace function public._audit_log_maintain_partitions()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_table      text;
  v_partition  text;
  v_drop_before date := current_date - interval '90 days';
  v_create_through date := current_date + interval '60 days';
  v_month      date;
begin
  -- Create future partitions if missing
  v_month := date_trunc('month', current_date);
  while v_month <= v_create_through loop
    v_partition := 'audit_log_' || to_char(v_month, 'YYYY_MM');
    if not exists (
      select 1 from pg_class where relname = v_partition
    ) then
      execute format(
        'create table public.%I partition of public.audit_log
         for values from (%L) to (%L)',
        v_partition,
        v_month,
        v_month + interval '1 month'
      );
    end if;
    v_month := v_month + interval '1 month';
  end loop;

  -- Roll up and drop expired partitions
  for v_partition in
    select tablename
    from pg_tables
    where schemaname = 'public'
      and tablename ~ '^audit_log_\d{4}_\d{2}$'
      and to_date(substring(tablename from 'audit_log_(\d{4}_\d{2})'), 'YYYY_MM')
          < date_trunc('month', v_drop_before)
  loop
    execute format(
      'insert into public.audit_summary
         (shop_id, day, action_code, actor_user_id, source, count)
       select shop_id, date_trunc(''day'', occurred_at)::date, action_code,
              actor_user_id, source, count(*)
         from public.%I
         group by shop_id, date_trunc(''day'', occurred_at)::date,
                  action_code, actor_user_id, source
       on conflict (shop_id, day, action_code, actor_user_id, source)
         do update set count = public.audit_summary.count + excluded.count',
      v_partition
    );
    execute format('drop table public.%I', v_partition);
  end loop;
end;
$$;
```

Idempotent — running it twice in the same day creates no extra partitions and drops nothing more.

### 7.3 Why the summary rollup matters

A pure 90-day window would leave us unable to answer "how many price edits did Cabdi do in Q1?" once the window passes. The `audit_summary` table is tiny (~10 KB per shop per year), survives partition drops, and powers compliance + payroll-discrepancy reports without keeping snapshots.

Trade-off: we lose the *what* (snapshot detail) at 90 days but keep the *who, what-action, when* forever. This matches the typical compliance ask.

---

## 8. Storage estimates

For sanity-checking the design at scale. Numbers from § 1 of the prior conversation, refined:

| Scale | Hot-tier size | Summary-tier size (1 yr) | Notes |
|---|---|---|---|
| 100 shops × 60 events/day × 1 KB | ~540 MB | ~1 MB | pilot |
| 1,000 shops | ~5.4 GB | ~10 MB | early GA |
| 10,000 shops | ~54 GB | ~100 MB | mature GA |
| 100,000 shops | ~540 GB | ~1 GB | needs cold tier |

Row-size dominators:
- `before_state` + `after_state` on sale voids — full line snapshot ~3 KB each.
- TOAST + LZ4 (PG14 default) cuts this by 60–80% on average — so effective hot footprint is ~30–40% of the raw number.

Per-action snapshot policy (§ 4) means most rows have **no** before/after — only the money mutations and rare edits do. Most rows are 200–400 bytes.

---

## 9. Storage optimization knobs

Applied in this design, in addition to the tiers in § 7:

1. **TOAST + LZ4 compression** — automatic on jsonb > 2 KB (PG14+).
2. **No `before_state` unless justified** — registered per action code; the helper enforces.
3. **`entity_ids` array for bulk operations** — one row per batch, not per affected entity. Future-proofs the admin portal's bulk operations.
4. **Coalesce sequential edits** — *deferred* to a v1.x optimization. When implemented: same `(shop_id, action_code, entity_id, actor_user_id)` tuple within 5 min of the previous row overwrites the `after_state` and increments a `coalesced_count int default 1` column instead of inserting a new row. Cuts the price-edit category ~80%.
5. **Partition-level VACUUM tuning** — set `autovacuum_vacuum_scale_factor = 0.01` on the active month's partition (cheap, frequent); leave defaults on older partitions.
6. **No `before_state` for create events** — by definition the "before" is "did not exist." The helper enforces via the `captures_before` flag.
7. **Drop `actor_name` denormalisation** — we resolve the name on read via the auth.users join. Saves text storage at the cost of one join per read.

---

## 10. RLS and capability gating

### 10.1 Row-Level Security

`audit_log` has `enable row level security`. The SELECT policy:

```sql
create policy audit_log_select_member on public.audit_log
  for select using (
    public.auth_can_access_shop(audit_log.shop_id)
  );
```

INSERT, UPDATE, DELETE policies all `false` for regular users — writes happen only through `_audit_log` (security_definer). Append-only by design.

Platform staff override the SELECT policy via `auth_is_platform_staff(null)` — they read everything for support and incident response, audit-logged (`auth.impersonation.start`).

### 10.2 Capability gating

| Capability | Effect |
|---|---|
| `audit.view` | Required for any read (mobile inline cues + web admin feed). Cashier baseline includes it — they need to see "voided by X" on their own sales. |
| `audit.export` | Required for CSV/PDF download from the shop admin portal. Owner-only by default. |
| `audit.view_org` | Required for org-wide audit reads across multiple shops. Org owner only. |
| `audit.staff_actions` | Required to read `auth.impersonation.*` rows. Platform staff only. |

These extend the catalog in `docs/roles-and-permissions.md` and ship with the migration that seeds the action codes.

### 10.3 PII redaction

`before_state` / `after_state` for `people.party.*` actions may carry phone numbers. The web admin portal's audit module redacts phone digits past the last 3 by default; the platform staff role gets the unredacted view with the read logged.

Mobile never sees snapshots, so no redaction logic needed there.

---

## 11. Source-of-action attribution

The `source` column distinguishes `mobile` vs `shop_admin_web` vs `system_admin_web` vs `rpc` vs `system`. Populated server-side from a custom JWT claim that each client SDK sets:

- Flutter app: `request.jwt.claim.source = 'mobile'`.
- Shop admin portal: `request.jwt.claim.source = 'shop_admin_web'`.
- System admin portal: `request.jwt.claim.source = 'system_admin_web'`.

Trustable because Supabase signs the JWT — the client can't forge it. Fallback to `'rpc'` when no claim is present (server-side cron, internal calls).

Why it matters: "edited via web by Cabdi" vs "edited via mobile by Cabdi" is information the audit reader cares about (which device? did the cashier have physical access to the phone?).

---

## 12. Impersonation

When platform staff act under an impersonation session (per `docs/system-admin-portal.md` § 9):

- `actor_user_id` = the impersonated user (so the audit looks "natural" from the shop's perspective).
- `impersonation_session_id` = the staff session id (always populated for impersonation rows).
- `source` = `system_admin_web`.

The shop admin portal's audit module shows the impersonation badge inline. The system admin portal's audit module groups all rows for a session into one expandable view.

This is **not** hiding the impersonation — it's surfacing it correctly. The session id is queryable.

---

## 13. Migration plan

### 13.1 Migration 0050 — schema + helpers

- Create `audit_action_code` reference table; seed the v1 codes.
- Create `audit_log` partitioned table.
- Create `audit_summary` rollup table.
- Create `_audit_log` helper function.
- Create `_audit_log_maintain_partitions` function.
- Create initial 3 monthly partitions.
- Set up `pg_cron` job to call `_audit_log_maintain_partitions` daily at 02:00 shop-timezone-equivalent (UTC for now; refine later).
- RLS policies + capability seeds.

### 13.2 Migration 0051 — instrument posting RPCs

- Add `_audit_log` call to each existing posting / mutation RPC (~30 functions).
- One-liner per RPC. No business logic changes.
- Harness §HH asserts at least one audit row lands per posting RPC, with correct `action_code` + entity_id.

### 13.3 Migration 0052 — read RPCs

- `list_audit_entries_for_entity(p_shop_id, p_entity_type, p_entity_id, p_limit)`.
- Web admin paginated read RPC (`list_audit_entries`) — out of scope for #231 Phase B, but the contract is locked here.

### 13.4 Mobile changes (`#231 Phase B`)

- `ShopApi.listAuditEntriesForEntity(...)`.
- `AuditEntry` type with `actor_name`, `action_code`, `occurred_at`, `reason`, `source`.
- Inline display surfaces per § 6.3 — Sale history voided row, Sale detail header, Product detail price tile, Party detail header.
- Tests cover: empty audit (no rows yet), latest void row renders the actor name + relative time, price edit on packaging surfaces last editor.

Estimate: 6 hours for backend (0050–0052), 3 hours for mobile, including tests.

---

## 14. Tests

### 14.1 Harness assertions (§HH)

1. `_audit_log` rejects unknown action codes.
2. `_audit_log` rejects empty / short reasons on actions with `requires_reason = true`.
3. `_audit_log` drops `before_state` / `after_state` per the policy table.
4. `post_sale` writes exactly one `sale.post` audit row with the correct entity_id.
5. `void_sale` writes one `sale.void` row with the original sale's id as entity_id.
6. `set_shop_item_unit_sale_price` writes one `inventory.unit.price_edit` row with `before_state` null.
7. SELECT from `audit_log` as a non-member returns zero rows.
8. SELECT from `audit_log` as a member returns rows for own shop only.
9. INSERT into `audit_log` directly (as authenticated user, not via `_audit_log`) is refused by RLS.
10. `_audit_log_maintain_partitions` creates next month's partition idempotently.
11. `_audit_log_maintain_partitions` drops expired partitions and rolls up to `audit_summary`.
12. After roll-up, `audit_summary` returns correct counts per (shop_id, day, action_code, actor).

### 14.2 Mobile tests

- AuditEntry parse from RPC response.
- "voided by Asha 10 min ago" subtitle renders from a fresh `sale.void` row.
- "last edited by Cabdi yesterday" tooltip renders from latest `inventory.unit.price_edit` row.
- Empty audit returns null subtitle (no "voided by null").
- Capability gating: cashier role calling `listAuditEntriesForEntity` with missing `audit.view` returns rejection (when capability is enforced server-side; v1 ships `audit.view` to cashier baseline anyway).

---

## 15. What this deliberately does NOT cover

Pinned again at the end so scope creep gets caught a second time:

1. Tamper-proof / cryptographic chaining of rows.
2. Backup / state recovery from audit data.
3. Free-text search over snapshots.
4. Read-event logging.
5. UI for "edit audit" / "delete audit" — append-only.
6. Telemetry rollups (those go to Sentry).
7. Cold-tier archival to object storage (v2).
8. Streaming audit to external SIEM (v2 if compliance demands).
9. Real-time audit subscription on the mobile side (the realtime channel is for state changes, not the audit log itself — too noisy).

---

## 16. Open questions

Three calls that need to be made before the migration lands:

1. **Reason-required threshold.** I set ≥ 20 chars in § 5.1. Too short forces "ok" responses; too long is unfair to legit voids. Worth a pilot-shopkeeper check.
2. **`auth.session.start` logging.** Useful for security investigations but ~2 rows per cashier per shift = 60+/day per shop. Drops volume estimates noticeably. Keep, or move to Sentry-only? My default: keep, drop the snapshot, ride the no-snapshot-policy.
3. **PII in `after_state` for party.create / party.edit.** Phone numbers and names. The redaction discipline in § 10.3 is on the read side. Should the write side also strip? My default: write full, redact on read — gives platform staff the option with audit, but keeps PII out of standard reads.

---

## 17. Companion documents

- `docs/system-admin-portal.md` § 9 — impersonation contract.
- `docs/system-admin-portal.md` § 13 — full audit-log requirements doc.
- `docs/shop-admin-portal.md` § 6.7 — owner-facing audit module.
- `docs/mobile-app.md` § 12 — inline cues this design powers.
- `docs/roles-and-permissions.md` — capability vocabulary for audit reads.
- `docs/backend-schema.md` — shared backend schema rules.

---

## 18. Change log

| Date | Change | Author |
|---|---|---|
| 2026-06-11 | Initial draft. | — |
