-- Consolidated into 0019_search_items.sql under the v2 schema rewrite.
--
-- p_party_id is now part of the canonical search_items signature in
-- 0019. When supplied with p_screen='receive' the search reads
-- public.supplier_item_unit_cost(shop_id, party_id, shop_item_unit_id)
-- to surface the per-supplier per-packaging last cost in
-- default_unit_last_cost — which mirrors the per-supplier learning
-- that the old version emulated via transaction_line scans.
--
-- This file is kept as a no-op so migration ordering stays contiguous.

select 1;
