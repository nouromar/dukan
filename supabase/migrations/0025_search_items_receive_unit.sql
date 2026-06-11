-- Consolidated into 0019_search_items.sql under the v2 schema rewrite.
--
-- The Receive screen's "show me the receive packaging on each tile"
-- contract is now satisfied by default_shop_item_unit_id + the derived
-- packaging_label that 0019 returns. The label format is:
--   conversion=1 → just the unit label ("kg")
--   otherwise    → "{conversion} {base_unit_label} {unit_label}"
--                  e.g. "25 kg bag"
-- with trailing zeros trimmed off the conversion. No client formatting
-- needed.
--
-- This file is kept as a no-op so migration ordering stays contiguous.

select 1;
