-- Consolidated into 0019_search_items.sql under the v2 schema rewrite.
--
-- The locale parameter is now part of the canonical search_items
-- signature in 0019. Display names are resolved server-side via
-- public.shop_item_display_name(shop_item_id, locale) (declared in
-- 0013) which walks the alias chain:
--   shop_item_alias (display, locale) →
--   shop_item_alias (display, any)    →
--   item_alias      (display, locale) →
--   item_alias      (display, any)    →
--   '(unnamed)'
-- so the picker always renders the most locale-specific name available.
--
-- This file is kept as a no-op so migration ordering stays contiguous.

select 1;
