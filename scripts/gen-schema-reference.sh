#!/usr/bin/env bash
#
# Generate the declarative STRUCTURAL schema reference under supabase/schemas/.
#
# Applies every migration to a throwaway Postgres (reusing the backend
# harness's auth/storage mocks), pg_dumps the resulting public schema, and
# splits the STRUCTURAL objects (tables + constraints/indexes) into two
# always-current reference files:
#
#   supabase/schemas/20_tables.sql              CREATE TABLE / VIEW / defaults
#   supabase/schemas/40_constraints_indexes.sql PK/FK/unique/check + indexes
#
# Functions, triggers, RLS policies, and grants are deliberately NOT included:
# Dukan is RPC-heavy (~134 functions / ~9k lines) and those stay in the
# migration stream as the source of truth (see docs note / commit history).
# This is a READ-ONLY reference — not wired into `supabase db diff`. Re-run it
# after changing migrations to keep the reference in sync.
#
# Usage:  ./scripts/gen-schema-reference.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_NAME="dukan-schema-ref-$$"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:16-alpine}"
DUMP="$(mktemp)"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -f "$DUMP"
}
trap cleanup EXIT

docker run --rm --name "$CONTAINER_NAME" -e POSTGRES_PASSWORD=postgres -d "$POSTGRES_IMAGE" >/dev/null
for _ in $(seq 1 30); do
  docker exec "$CONTAINER_NAME" pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 1
done

# auth/storage mocks (verbatim from scripts/test-backend-migrations.sh)
docker exec -i "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -d postgres <<'SQL'
create role anon nologin;
create role authenticated nologin;
create schema auth;
create schema storage;
create table auth.users (id uuid primary key default gen_random_uuid(), email text, phone text);
create table storage.buckets (id text primary key, name text not null unique, public boolean not null default false, file_size_limit bigint, allowed_mime_types text[], created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text not null references storage.buckets(id), name text not null, owner uuid, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (bucket_id, name));
alter table storage.objects enable row level security;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon;
grant select on auth.users to authenticated, anon;
grant insert, update on auth.users to authenticated;
grant usage on schema storage to authenticated, anon;
SQL

for migration in "$ROOT_DIR"/supabase/migrations/*.sql; do
  docker exec -i "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -d postgres < "$migration" >/dev/null
done

docker exec "$CONTAINER_NAME" pg_dump -U postgres -d postgres \
  --schema-only --schema=public --no-owner --no-privileges > "$DUMP"

OUTDIR="$ROOT_DIR/supabase/schemas" DUMP="$DUMP" python3 - <<'PY'
import os, re, collections
dump = open(os.environ["DUMP"]).read()
outdir = os.environ["OUTDIR"]

# pg_dump Type -> structural reference file (others are skipped on purpose)
KEEP = {
    "TABLE": "20_tables", "DEFAULT": "20_tables", "VIEW": "20_tables",
    "MATERIALIZED VIEW": "20_tables", "TABLE ATTACH": "20_tables",
    "TYPE": "20_tables", "DOMAIN": "20_tables", "SEQUENCE": "20_tables",
    "SEQUENCE OWNED BY": "20_tables", "SEQUENCE SET": "20_tables",
    "CONSTRAINT": "40_constraints_indexes", "FK CONSTRAINT": "40_constraints_indexes",
    "CHECK CONSTRAINT": "40_constraints_indexes", "INDEX": "40_constraints_indexes",
    "INDEX ATTACH": "40_constraints_indexes",
}
hdr = re.compile(
    r"(?m)^--\n-- Name: (?P<name>.*?); Type: (?P<type>.*?); Schema: (?P<schema>.*?)"
    r"(?:; Owner: .*)?\n--\n"
)
matches = list(hdr.finditer(dump))
buckets = collections.defaultdict(list)
counts = collections.Counter()
for i, m in enumerate(matches):
    end = matches[i + 1].start() if i + 1 < len(matches) else len(dump)
    typ = m.group("type").strip()
    f = KEEP.get(typ)
    if not f:
        continue
    buckets[f].append(dump[m.start():end].rstrip() + "\n\n")
    counts[typ] += 1

os.makedirs(outdir, exist_ok=True)
header = (
    "-- GENERATED structural schema reference — DO NOT EDIT.\n"
    "-- Regenerate: ./scripts/gen-schema-reference.sh\n"
    "-- Reflects every migration in supabase/migrations/. Functions, triggers,\n"
    "-- RLS policies, and grants are NOT here — they live in the migrations.\n\n"
)
for f in ("20_tables", "40_constraints_indexes"):
    with open(os.path.join(outdir, f + ".sql"), "w") as fh:
        fh.write(header)
        fh.write("".join(buckets.get(f, [])))

print("Structural reference written to supabase/schemas/:")
print(f"  20_tables.sql              {counts['TABLE']} tables, {counts['VIEW']} views")
print(f"  40_constraints_indexes.sql {counts['CONSTRAINT']+counts['FK CONSTRAINT']} constraints, {counts['INDEX']} indexes")
PY
echo "Done."
