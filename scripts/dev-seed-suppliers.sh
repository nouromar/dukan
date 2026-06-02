#!/usr/bin/env bash
# Dev helper: seed 3 realistic suppliers into a shop on the local
# Supabase stack, so the Receive flow has something to pick from before
# the admin portal (where supplier setup officially lives) is built.
#
# Usage:
#   ./scripts/dev-seed-suppliers.sh                    # default shop
#   ./scripts/dev-seed-suppliers.sh "Shop Name"        # named shop
#
# Idempotent: re-running with the same shop is a no-op (ON CONFLICT
# DO NOTHING). Local-only — points at the Supabase CLI's Postgres on
# 54322. Not safe against the hosted project.

set -euo pipefail

SHOP_NAME="${1:-}"
DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
DB_CONTAINER="${SUPABASE_DB_CONTAINER:-supabase_db_dukan}"

# If no shop name passed, target the lone shop the user most likely
# logged into. Errors out if there are multiple shops on the stack.
if [[ -z "$SHOP_NAME" ]]; then
  SHOP_FILTER="(select id from public.shop limit 2 offset 1) is null"
  SHOP_LOOKUP="(select id from public.shop limit 1)"
else
  SHOP_FILTER="true"
  SHOP_LOOKUP="(select id from public.shop where name = '${SHOP_NAME}')"
fi

# 3 suppliers with realistic Somali-context names. unique(shop_id, name)
# isn't enforced by schema, so we de-dupe via NOT EXISTS to keep this
# safe to re-run.
SQL="
do \$\$
declare
  v_shop_id uuid;
  v_supplier_type_id uuid;
begin
  if not (${SHOP_FILTER}) then
    raise exception 'No shop name given and the stack has multiple shops. Pass a shop name as arg 1.';
  end if;

  v_shop_id := ${SHOP_LOOKUP};
  if v_shop_id is null then
    raise exception 'Shop not found';
  end if;

  v_supplier_type_id := (
    select id from public.party_type where code = 'supplier'
  );

  insert into public.party (shop_id, name, phone, type_id)
  select v_shop_id, n.name, n.phone, v_supplier_type_id
  from (values
    ('Hassan Wholesaler',     '+252611111111'),
    ('Mahad Grains',          '+252622222222'),
    ('Asha Bakery Supplies',  '+252633333333')
  ) as n(name, phone)
  where not exists (
    select 1 from public.party p
    where p.shop_id = v_shop_id and p.name = n.name
  );

  raise notice 'Seeded suppliers for shop %', v_shop_id;
end;
\$\$;

select name, phone, payable
from public.party
where shop_id = ${SHOP_LOOKUP}
  and type_id = (select id from public.party_type where code = 'supplier')
order by name;
"

if command -v psql >/dev/null 2>&1; then
  psql "$DB_URL" -v ON_ERROR_STOP=1 -c "$SQL"
elif docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
  docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres \
    -v ON_ERROR_STOP=1 -c "$SQL"
else
  echo "error: psql not found and container '$DB_CONTAINER' is not running" >&2
  echo "       set SUPABASE_DB_CONTAINER or start 'supabase start'" >&2
  exit 1
fi
