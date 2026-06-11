-- 0047_realtime_publication.sql
--
-- Enable Supabase realtime on the tables the mobile app subscribes to
-- so price/stock/alias/barcode edits from the shop admin portal (and
-- eventually owner-on-web flows) propagate to a cashier's open detail
-- or list screen within seconds. RLS still applies — realtime events
-- only fire for rows the subscribed user can SELECT.
--
-- Tables included:
--   * shop_item                — name, category, threshold, current_stock
--   * shop_item_unit           — sale_price, default flags, deactivation
--   * shop_item_alias          — alias add/remove
--   * shop_item_barcode        — barcode add/remove/primary-promotion
--   * party                    — name, phone, receivable/payable
--
-- A separate publication keeps the customer-data tables out of the
-- default `supabase_realtime` publication's blast radius. The Supabase
-- platform listens to `supabase_realtime` automatically; this script
-- adds tables to that publication.
--
-- Idempotent: skip if a table is already in the publication.
--
-- The publication itself is created by Supabase platform setup, but
-- the standalone test harness (scripts/test-backend-migrations.sh)
-- runs on vanilla Postgres where it doesn't exist. The do-block below
-- creates it if absent so the migration is reusable across both.

do $$
declare
  t text;
begin
  if not exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    create publication supabase_realtime;
  end if;

  foreach t in array array[
    'shop_item',
    'shop_item_unit',
    'shop_item_alias',
    'shop_item_barcode',
    'party'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end
$$;
