-- Seed the grocery starter template against the v2 catalog (no
-- revisions, no concepts). Layout:
--
--   1. category rows (grocery, beverages, staples, household).
--   2. item rows (slim: code + category_id + base_unit_code).
--   3. item_alias rows — one is_display=true per language for the
--      canonical name; additional search aliases.
--   4. item_unit rows — base packaging (conversion_to_base=1) plus
--      receive packagings (bag/box/carton/etc.).
--   5. grocery template + packs + settings + units + expense
--      categories + quick actions.
--   6. template_item rows referencing the new item.id values.
--   7. template_item_alias rows carrying the en/so display labels.
--
-- Idempotent: all inserts use on conflict do nothing / do update.
-- Authoritative apply path is `supabase db reset`.

----------------------------------------------------------------------
-- 1. Categories
----------------------------------------------------------------------

insert into public.category (code, name, name_translations, sort_order)
values
  ('grocery',   'Grocery',   jsonb_build_object('en', 'Grocery',   'so', 'Raashin'),    1),
  ('staples',   'Staples',   jsonb_build_object('en', 'Staples',   'so', 'Raashinka'),  2),
  ('beverages', 'Beverages', jsonb_build_object('en', 'Beverages', 'so', 'Cabbitooyin'), 3),
  ('household', 'Household', jsonb_build_object('en', 'Household', 'so', 'Guriga'),     4)
on conflict (code) do nothing;

----------------------------------------------------------------------
-- 2. Items (global SKUs, slim shape — display name lives in item_alias)
----------------------------------------------------------------------

insert into public.item (code, category_id, base_unit_code, is_active)
select i.item_code, c.id, i.base_unit, true
from (values
  ('rice_basmati_25kg',     'staples',   'kg'),
  ('sugar_white_50kg',      'staples',   'kg'),
  ('oil_cooking_1l',        'grocery',   'litre'),
  ('tea_black_500g',        'grocery',   'packet'),
  ('milk_powder_400g',      'grocery',   'packet'),
  ('water_bottled_500ml',   'beverages', 'bottle'),
  ('soap_bar_100g',         'household', 'piece'),
  ('biscuit_assorted_100g', 'grocery',   'packet'),
  ('pasta_dry_500g',        'grocery',   'packet'),
  ('bread_loaf',            'grocery',   'piece'),
  ('flour_wheat_25kg',      'staples',   'kg'),
  ('coffee_instant_200g',   'grocery',   'packet'),
  ('soda_can_330ml',        'beverages', 'piece')
) as i(item_code, category_code, base_unit)
join public.category c on c.code = i.category_code
on conflict (code) do nothing;

----------------------------------------------------------------------
-- 3. Item aliases (display + search)
----------------------------------------------------------------------

-- Display aliases (one per language per item). is_display=true so the
-- shop's snapshotted alias picks them up.
insert into public.item_alias (
  item_id, alias_text, language_code, is_display, source, weight
)
select i.id, a.alias_text, a.lang, true, 'platform', 0
from public.item i
join (values
  ('rice_basmati_25kg',     'en', 'Basmati Rice'),
  ('rice_basmati_25kg',     'so', 'Bariis Basmati'),
  ('sugar_white_50kg',      'en', 'White Sugar'),
  ('sugar_white_50kg',      'so', 'Sonkor cad'),
  ('oil_cooking_1l',        'en', 'Cooking Oil'),
  ('oil_cooking_1l',        'so', 'Saliid cuneed'),
  ('tea_black_500g',        'en', 'Black Tea'),
  ('tea_black_500g',        'so', 'Shaah madow'),
  ('milk_powder_400g',      'en', 'Milk Powder'),
  ('milk_powder_400g',      'so', 'Caano qalalan'),
  ('water_bottled_500ml',   'en', 'Bottled Water'),
  ('water_bottled_500ml',   'so', 'Biyo dhalo'),
  ('soap_bar_100g',         'en', 'Bar Soap'),
  ('soap_bar_100g',         'so', 'Saabuun xabba'),
  ('biscuit_assorted_100g', 'en', 'Biscuit'),
  ('biscuit_assorted_100g', 'so', 'Buskut'),
  ('pasta_dry_500g',        'en', 'Pasta'),
  ('pasta_dry_500g',        'so', 'Baasto'),
  ('bread_loaf',            'en', 'Bread'),
  ('bread_loaf',            'so', 'Rooti'),
  ('flour_wheat_25kg',      'en', 'Wheat Flour'),
  ('flour_wheat_25kg',      'so', 'Bur'),
  ('coffee_instant_200g',   'en', 'Instant Coffee'),
  ('coffee_instant_200g',   'so', 'Kafee'),
  ('soda_can_330ml',        'en', 'Soda'),
  ('soda_can_330ml',        'so', 'Kuula')
) as a(item_code, lang, alias_text) on a.item_code = i.code
on conflict (item_id, language_code, alias_text_norm) do nothing;

-- Search nicknames (is_display=false). Cashier types "rice" → matches.
insert into public.item_alias (
  item_id, alias_text, language_code, is_display, source, weight
)
select i.id, a.alias_text, a.lang, false, 'platform', 0
from public.item i
join (values
  ('rice_basmati_25kg',     'en', 'rice'),
  ('rice_basmati_25kg',     'en', 'basmati'),
  ('rice_basmati_25kg',     'so', 'bariis'),
  ('sugar_white_50kg',      'en', 'sugar'),
  ('sugar_white_50kg',      'so', 'sonkor'),
  ('oil_cooking_1l',        'en', 'oil'),
  ('oil_cooking_1l',        'en', 'cooking oil'),
  ('oil_cooking_1l',        'so', 'saliid'),
  ('tea_black_500g',        'en', 'tea'),
  ('tea_black_500g',        'so', 'shaah'),
  ('milk_powder_400g',      'en', 'milk'),
  ('milk_powder_400g',      'so', 'caano'),
  ('water_bottled_500ml',   'en', 'water'),
  ('water_bottled_500ml',   'so', 'biyo'),
  ('soap_bar_100g',         'en', 'soap'),
  ('soap_bar_100g',         'so', 'saabuun'),
  ('biscuit_assorted_100g', 'en', 'biscuit'),
  ('biscuit_assorted_100g', 'so', 'buskut'),
  ('pasta_dry_500g',        'en', 'pasta'),
  ('pasta_dry_500g',        'so', 'baasto'),
  ('bread_loaf',            'en', 'bread'),
  ('bread_loaf',            'so', 'rooti'),
  ('flour_wheat_25kg',      'en', 'flour'),
  ('flour_wheat_25kg',      'so', 'bur'),
  ('coffee_instant_200g',   'en', 'coffee'),
  ('coffee_instant_200g',   'so', 'kafee'),
  ('soda_can_330ml',        'en', 'soda'),
  ('soda_can_330ml',        'en', 'cola'),
  ('soda_can_330ml',        'so', 'kuula')
) as a(item_code, lang, alias_text) on a.item_code = i.code
on conflict (item_id, language_code, alias_text_norm) do nothing;

----------------------------------------------------------------------
-- 4. Item units (packagings).
--
--   Base packaging:   conversion_to_base = 1, unit_code = item.base_unit_code.
--   Receive package:  conversion = base units per package (e.g. bag = 25 kg).
--
-- The base-unit guard trigger on item_unit enforces that the
-- conversion=1 row uses item.base_unit_code, so we must seed it
-- first.
----------------------------------------------------------------------

-- Base packagings (conversion=1). is_default_sale=true so the search
-- result row's default packaging is the loose / per-piece unit; default
-- receive picks the larger package below.
insert into public.item_unit (
  item_id, unit_code, conversion_to_base,
  is_default_sale, is_default_receive, sort_order, is_active
)
select i.id, u.unit_code, 1, u.is_default_sale, u.is_default_receive, u.sort_order, true
from public.item i
join (values
  ('rice_basmati_25kg',     'kg',     true,  false, 1),
  ('sugar_white_50kg',      'kg',     true,  false, 1),
  ('oil_cooking_1l',        'litre',  true,  false, 1),
  ('tea_black_500g',        'packet', true,  true,  1),
  ('milk_powder_400g',      'packet', true,  true,  1),
  ('water_bottled_500ml',   'bottle', true,  false, 1),
  ('soap_bar_100g',         'piece',  true,  false, 1),
  ('biscuit_assorted_100g', 'packet', true,  false, 1),
  ('pasta_dry_500g',        'packet', true,  false, 1),
  ('bread_loaf',            'piece',  true,  true,  1),
  ('flour_wheat_25kg',      'kg',     true,  false, 1),
  ('coffee_instant_200g',   'packet', true,  false, 1),
  ('soda_can_330ml',        'piece',  true,  false, 1)
) as u(item_code, unit_code, is_default_sale, is_default_receive, sort_order)
  on u.item_code = i.code
on conflict (item_id, unit_code, conversion_to_base) do nothing;

-- Receive packagings (conversion > 1). Base-unit guard trigger
-- forbids conversion=1 with a unit_code that doesn't match
-- item.base_unit_code, so all rows here have conversion > 1.
insert into public.item_unit (
  item_id, unit_code, conversion_to_base,
  is_default_sale, is_default_receive, sort_order, is_active
)
select i.id, u.unit_code, u.conversion, false, u.is_default_receive, u.sort_order, true
from public.item i
join (values
  ('rice_basmati_25kg',     'bag',    25::numeric,  true,  2),
  ('sugar_white_50kg',      'bag',    50::numeric,  true,  2),
  ('oil_cooking_1l',        'carton', 12::numeric,  true,  2),
  ('tea_black_500g',        'box',    24::numeric,  false, 2),
  ('milk_powder_400g',      'carton', 12::numeric,  false, 2),
  ('water_bottled_500ml',   'carton', 12::numeric,  true,  2),
  ('soap_bar_100g',         'box',    50::numeric,  true,  2),
  ('biscuit_assorted_100g', 'carton', 24::numeric,  true,  2),
  ('pasta_dry_500g',        'box',    20::numeric,  true,  2),
  ('flour_wheat_25kg',      'bag',    25::numeric,  true,  2),
  ('coffee_instant_200g',   'box',    12::numeric,  true,  2),
  ('soda_can_330ml',        'carton', 24::numeric,  true,  2)
) as u(item_code, unit_code, conversion, is_default_receive, sort_order)
  on u.item_code = i.code
on conflict (item_id, unit_code, conversion_to_base) do nothing;

----------------------------------------------------------------------
-- 5. Template + packs + settings + units
----------------------------------------------------------------------

insert into public.template (
  code, kind, name, locale_default, currency_default, version, is_active
)
values ('grocery', 'shop_starter', 'Grocery', 'so', 'USD', 1, true)
on conflict (code, version) do nothing;

insert into public.template_pack (
  template_id, code, version, is_required, file_path
)
select t.id, p.code, p.version, p.is_required, p.file_path
from public.template t
cross join (values
  ('settings',           1, true,  'templates/grocery/settings.json'),
  ('catalog',            1, true,  'templates/grocery/catalog.json'),
  ('expense_categories', 1, true,  'templates/grocery/expense-categories.json'),
  ('quick_actions',      1, false, 'templates/grocery/quick-actions.json')
) as p(code, version, is_required, file_path)
where t.code = 'grocery' and t.version = 1
on conflict (template_id, code, version) do nothing;

insert into public.template_setting (template_id, key, value)
select t.id, s.key, s.value
from public.template t
cross join (values
  ('locale_default',          to_jsonb('so'::text)),
  ('currency_default',        to_jsonb('USD'::text)),
  ('timezone_default',        to_jsonb('Africa/Mogadishu'::text)),
  ('sale_payment_default',    to_jsonb('cash'::text)),
  ('receive_payment_default', to_jsonb('credit'::text)),
  ('negative_stock_policy',   to_jsonb('warn'::text))
) as s(key, value)
where t.code = 'grocery' and t.version = 1
on conflict (template_id, key) do nothing;

insert into public.template_unit (template_id, unit_code, label, sort_order)
select t.id, u.unit_code, u.label, u.sort_order
from public.template t
cross join (values
  ('piece',  jsonb_build_object('en', 'Piece',  'so', 'Xabba'),    1),
  ('kg',     jsonb_build_object('en', 'Kg',     'so', 'Kg'),       2),
  ('gram',   jsonb_build_object('en', 'Gram',   'so', 'Garaam'),   3),
  ('litre',  jsonb_build_object('en', 'Litre',  'so', 'Litir'),    4),
  ('ml',     jsonb_build_object('en', 'ml',     'so', 'ml'),       5),
  ('bag',    jsonb_build_object('en', 'Bag',    'so', 'Bac'),      6),
  ('box',    jsonb_build_object('en', 'Box',    'so', 'Sanduuq'),  7),
  ('carton', jsonb_build_object('en', 'Carton', 'so', 'Kartoon'),  8),
  ('bottle', jsonb_build_object('en', 'Bottle', 'so', 'Dhalo'),    9),
  ('packet', jsonb_build_object('en', 'Packet', 'so', 'Baakad'),  10)
) as u(unit_code, label, sort_order)
where t.code = 'grocery' and t.version = 1
on conflict (template_id, unit_code) do nothing;

----------------------------------------------------------------------
-- 6. Template items (the curated grocery candidate list).
--    Each row references a global item by id; apply_template /
--    ensure_shop_item handles activation.
----------------------------------------------------------------------

insert into public.template_item (
  template_id, item_code, item_id,
  suggested_sale_price, reorder_threshold, sort_order
)
select t.id, i.code, i.id, p.price, p.reorder, p.sort_order
from public.template t
join (values
  ('rice_basmati_25kg',      1.50::numeric, 10::numeric,    1),
  ('sugar_white_50kg',       1.00::numeric, 10::numeric,    2),
  ('oil_cooking_1l',         2.50::numeric, 6::numeric,     3),
  ('tea_black_500g',         1.20::numeric, 5::numeric,     4),
  ('milk_powder_400g',       3.00::numeric, 6::numeric,     5),
  ('water_bottled_500ml',    0.50::numeric, 24::numeric,    6),
  ('soap_bar_100g',          0.50::numeric, 10::numeric,    7),
  ('biscuit_assorted_100g',  0.30::numeric, 12::numeric,    8),
  ('pasta_dry_500g',         0.80::numeric, 8::numeric,     9),
  ('bread_loaf',             0.25::numeric, 6::numeric,    10),
  ('flour_wheat_25kg',       1.20::numeric, 10::numeric,   11),
  ('coffee_instant_200g',    2.20::numeric, 6::numeric,    12),
  ('soda_can_330ml',         0.75::numeric, 24::numeric,   13)
) as p(item_code, price, reorder, sort_order) on true
join public.item i on i.code = p.item_code
where t.code = 'grocery' and t.version = 1
on conflict (template_id, item_code) do nothing;

----------------------------------------------------------------------
-- 7. Template item aliases (display labels carried into the shop on
--    apply, so each activated shop_item has its name overridden by the
--    template's preferred wording — currently identical to the global
--    item_alias display rows, but kept explicit for future curation).
----------------------------------------------------------------------

insert into public.template_item_alias (
  template_id, item_code, language_code, alias_text, is_display, weight
)
select t.id, a.item_code, a.lang, a.alias_text, true, 0
from public.template t
cross join (values
  ('rice_basmati_25kg',     'en', 'Basmati Rice'),
  ('rice_basmati_25kg',     'so', 'Bariis Basmati'),
  ('sugar_white_50kg',      'en', 'White Sugar'),
  ('sugar_white_50kg',      'so', 'Sonkor cad'),
  ('oil_cooking_1l',        'en', 'Cooking Oil'),
  ('oil_cooking_1l',        'so', 'Saliid cuneed'),
  ('tea_black_500g',        'en', 'Black Tea'),
  ('tea_black_500g',        'so', 'Shaah madow'),
  ('milk_powder_400g',      'en', 'Milk Powder'),
  ('milk_powder_400g',      'so', 'Caano qalalan'),
  ('water_bottled_500ml',   'en', 'Bottled Water'),
  ('water_bottled_500ml',   'so', 'Biyo dhalo'),
  ('soap_bar_100g',         'en', 'Bar Soap'),
  ('soap_bar_100g',         'so', 'Saabuun xabba'),
  ('biscuit_assorted_100g', 'en', 'Biscuit'),
  ('biscuit_assorted_100g', 'so', 'Buskut'),
  ('pasta_dry_500g',        'en', 'Pasta'),
  ('pasta_dry_500g',        'so', 'Baasto'),
  ('bread_loaf',            'en', 'Bread'),
  ('bread_loaf',            'so', 'Rooti'),
  ('flour_wheat_25kg',      'en', 'Wheat Flour'),
  ('flour_wheat_25kg',      'so', 'Bur'),
  ('coffee_instant_200g',   'en', 'Instant Coffee'),
  ('coffee_instant_200g',   'so', 'Kafee'),
  ('soda_can_330ml',        'en', 'Soda'),
  ('soda_can_330ml',        'so', 'Kuula')
) as a(item_code, lang, alias_text)
where t.code = 'grocery' and t.version = 1
on conflict (template_id, item_code, language_code, alias_text_norm) do nothing;

----------------------------------------------------------------------
-- 8. Expense categories
----------------------------------------------------------------------

insert into public.template_expense_category (
  template_id, code, name, name_translations, sort_order
)
select t.id, c.code, c.name, c.translations, c.sort_order
from public.template t
cross join (values
  ('rent',        'Rent',        jsonb_build_object('en', 'Rent',        'so', 'Kiro'),     1),
  ('electricity', 'Electricity', jsonb_build_object('en', 'Electricity', 'so', 'Koronto'),  2),
  ('salary',      'Salary',      jsonb_build_object('en', 'Salary',      'so', 'Mushahar'), 3),
  ('transport',   'Transport',   jsonb_build_object('en', 'Transport',   'so', 'Gaadiid'),  4),
  ('other',       'Other',       jsonb_build_object('en', 'Other',       'so', 'Kale'),     5)
) as c(code, name, translations, sort_order)
where t.code = 'grocery' and t.version = 1
on conflict (template_id, code) do nothing;

----------------------------------------------------------------------
-- 9. Quick actions (Home favorites for Sale + Receive).
----------------------------------------------------------------------

insert into public.template_quick_action (
  template_id, screen, position, item_code, label
)
select t.id, q.screen, q.position, q.item_code, null
from public.template t
cross join (values
  ('sale',    1, 'rice_basmati_25kg'),
  ('sale',    2, 'sugar_white_50kg'),
  ('sale',    3, 'oil_cooking_1l'),
  ('sale',    4, 'tea_black_500g'),
  ('sale',    5, 'soap_bar_100g'),
  ('receive', 1, 'rice_basmati_25kg'),
  ('receive', 2, 'sugar_white_50kg'),
  ('receive', 3, 'oil_cooking_1l'),
  ('receive', 4, 'tea_black_500g'),
  ('receive', 5, 'soap_bar_100g')
) as q(screen, position, item_code)
where t.code = 'grocery' and t.version = 1
on conflict (template_id, screen, position) do nothing;
