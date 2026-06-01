#!/usr/bin/env bash
# Dev helper: set or null out an item's sale price on the local Supabase
# stack. Lets you exercise the "no usable price → line editor opens in
# price-required mode" tap path in Sale without having to hand-roll SQL.
#
# Updates BOTH layers:
#   * catalog_item_revision.suggested_sale_price (for shops that haven't
#     activated the item yet — pure catalog candidates)
#   * public.item.sale_price for every shop that has already activated
#     this item (activation snapshots the catalog price, so updates here
#     are not propagated automatically)
#
# Usage:
#   ./scripts/dev-set-catalog-price.sh <item_code> <price-or-null>
#
# Examples:
#   ./scripts/dev-set-catalog-price.sh bread_loaf null
#   ./scripts/dev-set-catalog-price.sh bread_loaf 0.25
#
# Item codes (grocery template): rice_basmati_25kg, sugar_white_50kg,
# oil_cooking_1l, tea_black_500g, milk_powder_400g, water_bottled_500ml,
# soap_bar_100g, biscuit_assorted_100g, pasta_dry_500g, bread_loaf.
#
# Local-only — points at the Supabase CLI's Postgres on 54322. Not safe
# against the hosted project.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <item_code> <price-or-null>" >&2
  exit 1
fi

ITEM_CODE="$1"
PRICE_INPUT="$2"
DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
DB_CONTAINER="${SUPABASE_DB_CONTAINER:-supabase_db_dukan}"

if [[ "$PRICE_INPUT" == "null" || "$PRICE_INPUT" == "NULL" ]]; then
  SQL_VALUE="null"
elif [[ "$PRICE_INPUT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  SQL_VALUE="$PRICE_INPUT"
else
  echo "error: price must be a non-negative number or the literal 'null'" >&2
  exit 1
fi

# Update the current catalog revision AND every already-activated item
# row for this catalog item. Historical revisions are left alone.
SQL="update public.catalog_item_revision cir
set suggested_sale_price = ${SQL_VALUE}
from public.catalog_item ci
where ci.id = cir.catalog_item_id
  and ci.code = '${ITEM_CODE}'
  and cir.id = ci.current_revision_id
returning ci.code as catalog_item, cir.suggested_sale_price;

update public.item
set sale_price = ${SQL_VALUE}
from public.catalog_item ci
where ci.id = public.item.catalog_item_id
  and ci.code = '${ITEM_CODE}'
returning public.item.shop_id, ci.code as activated_item, public.item.sale_price;"

# Prefer a local psql; fall back to running psql inside the supabase
# Postgres container so this works on machines without psql installed.
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
