# Structural schema reference (generated)

These files are an **always-current, human-readable picture of the database
structure** — the thing `docs/backend-schema.md` keeps drifting away from.

```
supabase/schemas/
  20_tables.sql               CREATE TABLE / VIEW + column defaults
  40_constraints_indexes.sql  PK / FK / unique / check constraints + indexes
```

## What this is (and isn't)

- **Generated, not authored.** Produced by applying every migration in
  `supabase/migrations/` to a throwaway Postgres and dumping the result. The
  **migrations remain the source of truth**; these files are a derived reference.
- **Read-only.** Do not hand-edit — your change would be overwritten on the next
  regen and would never reach a real database. To change the schema, write a
  migration.
- **Not wired into `supabase db diff` / `db reset`.** This is a reference
  artifact, not part of the build. Deleting it changes nothing operationally.

## Hybrid on purpose — structure only

Functions, triggers, RLS policies, and grants are **deliberately excluded**.
Dukan is RPC-heavy (~134 functions ≈ 9k lines), and declarative diffing of
function bodies is noisy and low-value, so those stay in the migration stream.
What's worth seeing at a glance — the **table/relational structure** — lives
here; the imperative logic lives in `supabase/migrations/`.

## Regenerate after changing migrations

```bash
./scripts/gen-schema-reference.sh
```

Requires Docker (spins up `postgres:16-alpine`, applies all migrations, dumps
+ splits). Re-run it whenever you add/change a migration so the reference stays
honest, and commit the result alongside the migration.

## If you later want full declarative schemas

This is the structural slice of a full declarative setup. To go further you'd
add the remaining object types (functions/RLS/grants), order them for
dependencies, list the files under `[db.migrations] schema_paths` in
`config.toml`, and let `supabase db diff` generate migrations from them — at
which point these files would become the source of truth instead of a reference.
For now the hybrid (declarative structure reference + imperative migrations) is
the recommended fit.
