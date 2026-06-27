-- Retire the per-transaction "learning" write triggers.
--
-- 0014 added triggers that, on every transaction_line insert and every payment,
-- upsert five aggregate tables (shop_item_usage, shop_item_entry_profile,
-- shop_supplier_item_profile, shop_party_usage, shop_suggestion). An end-to-end
-- audit found NONE of them are read by any RPC or by the app — the write
-- pipeline was fully built but never consumed. Meanwhile they:
--   * add ~5 upserts per line on the hot Sale path, and
--   * grow unbounded (shop_item_entry_profile / shop_suggestion mint a row per
--     distinct quantity entered),
-- all for zero value.
--
-- The signals we actually want (recents, supplier baskets, usual quantities)
-- are being wired to compute ON READ from data we already have (txn /
-- local_transaction), so these aggregates stay unread. Drop the two hot
-- triggers to stop the dead writes.
--
-- Left intact on purpose: the trigger FUNCTIONS (harmless, now unused), and the
-- template-apply seeding of shop_suggestion (rebuild_shop_suggestions via
-- template_application_seed_shop_suggestions) — it's rare and off the hot path.

drop trigger if exists transaction_line_learn_from_insert on public.transaction_line;
drop trigger if exists payment_learn_from_insert on public.payment;
