-- Merged into 0011_catalog_activation.sql. The lazy-activation wrapper
-- this file added (`ensure_shop_item`) is now the canonical activation
-- entry point in 0011, alongside `create_shop_item`,
-- `create_shop_item_unit`, and `add_shop_item_alias`. The old
-- `activate_catalog_item(uuid, uuid, uuid, text, numeric, text)` is
-- gone with revisions (data-model-v2 §1).
--
-- File kept as a no-op so migration numbering stays stable.
select 1;
