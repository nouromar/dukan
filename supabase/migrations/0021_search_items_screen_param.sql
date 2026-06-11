-- Consolidated into 0019_search_items.sql under the v2 schema rewrite.
--
-- The historical contract for this migration ("extend search_items with
-- p_screen") is now part of the single canonical search_items signature:
--   public.search_items(shop_id, query, screen, locale, party_id, limit)
-- defined in 0019. The screen-specific default packaging is resolved
-- server-side (is_default_sale / is_default_receive) so the caller no
-- longer needs to ask "which unit do I show on this tile?" separately.
--
-- This file is kept as a no-op so migration ordering / numbering stays
-- contiguous with prior commits.

select 1;
