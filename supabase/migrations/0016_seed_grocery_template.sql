-- Seed the grocery starter template using the centralized-catalog design.
-- Per docs/decisions.md Q11 (DECIDED 2026-05-31), shops do NOT bulk-copy
-- the catalog into per-shop item rows; they activate catalog items lazily.
-- This migration seeds:
--   1. Cross-tenant catalog rows that all grocery shops share by reference.
--   2. The grocery template + settings + expense categories.
--   3. template_item rows referencing the catalog (the curated grocery
--      candidate list — what search prefers when a grocery shop is typing).
--   4. template_quick_action rows naming the small subset of items
--      apply_template pre-activates so Home is usable on day one.
--
-- Idempotent: all inserts use on conflict do nothing. Safe to re-run.
-- Authoritative apply path is `supabase db reset`.

----------------------------------------------------------------------
-- 1. Catalog: concepts, items, revisions, units, aliases
----------------------------------------------------------------------

insert into public.catalog_product_concept (code, name_en, description_en)
values
  ('basmati_rice',  'Basmati Rice',  null),
  ('white_sugar',   'White Sugar',   null),
  ('cooking_oil',   'Cooking Oil',   null),
  ('black_tea',     'Black Tea',     null),
  ('milk_powder',   'Milk Powder',   null),
  ('bottled_water', 'Bottled Water', null),
  ('bar_soap',      'Bar Soap',      null),
  ('biscuit',       'Biscuit',       null),
  ('pasta',         'Pasta',         null),
  ('bread',         'Bread',         null)
on conflict (code) do nothing;

insert into public.catalog_product_translation (concept_id, language_code, name, description)
select c.id, t.lang, t.name, null
from public.catalog_product_concept c
join (values
  ('basmati_rice',  'so', 'Bariis Basmati'),
  ('basmati_rice',  'en', 'Basmati Rice'),
  ('white_sugar',   'so', 'Sonkor cad'),
  ('white_sugar',   'en', 'White Sugar'),
  ('cooking_oil',   'so', 'Saliid cuneed'),
  ('cooking_oil',   'en', 'Cooking Oil'),
  ('black_tea',     'so', 'Shaah madow'),
  ('black_tea',     'en', 'Black Tea'),
  ('milk_powder',   'so', 'Caano qalaylan'),
  ('milk_powder',   'en', 'Milk Powder'),
  ('bottled_water', 'so', 'Biyo dhalo'),
  ('bottled_water', 'en', 'Bottled Water'),
  ('bar_soap',      'so', 'Saabuun xabba'),
  ('bar_soap',      'en', 'Bar Soap'),
  ('biscuit',       'so', 'Buskut'),
  ('biscuit',       'en', 'Biscuit'),
  ('pasta',         'so', 'Baasto'),
  ('pasta',         'en', 'Pasta'),
  ('bread',         'so', 'Rooti'),
  ('bread',         'en', 'Bread')
) as t(concept_code, lang, name) on t.concept_code = c.code
on conflict (concept_id, language_code) do nothing;

insert into public.catalog_item (concept_id, code, is_active)
select c.id, i.item_code, true
from public.catalog_product_concept c
join (values
  ('basmati_rice',  'rice_basmati_25kg'),
  ('white_sugar',   'sugar_white_50kg'),
  ('cooking_oil',   'oil_cooking_1l'),
  ('black_tea',     'tea_black_500g'),
  ('milk_powder',   'milk_powder_400g'),
  ('bottled_water', 'water_bottled_500ml'),
  ('bar_soap',      'soap_bar_100g'),
  ('biscuit',       'biscuit_assorted_100g'),
  ('pasta',         'pasta_dry_500g'),
  ('bread',         'bread_loaf')
) as i(concept_code, item_code) on i.concept_code = c.code
on conflict (code) do nothing;

insert into public.catalog_item_revision (
  catalog_item_id, revision_number, name, brand_name,
  package_quantity, package_unit_code, category_code,
  base_unit_code, default_sale_unit_code, default_receive_unit_code,
  suggested_sale_price, reorder_threshold
)
select ci.id, 1, r.name, null,
       r.package_qty, r.package_unit, 'grocery',
       r.base_unit, r.sale_unit, r.receive_unit,
       r.price, r.reorder
from public.catalog_item ci
join (values
  ('rice_basmati_25kg',     'Basmati Rice 25kg',     25::numeric,    'bag',    'kg',     'kg',     'bag',     1.50::numeric,  10::numeric),
  ('sugar_white_50kg',      'White Sugar 50kg',      50::numeric,    'bag',    'kg',     'kg',     'bag',     1.00::numeric,  10::numeric),
  ('oil_cooking_1l',        'Cooking Oil 1L',        1::numeric,     'bottle', 'litre',  'litre',  'bottle',  2.50::numeric,  6::numeric),
  ('tea_black_500g',        'Black Tea 500g',        500::numeric,   'packet', 'packet', 'packet', 'box',     1.20::numeric,  5::numeric),
  ('milk_powder_400g',      'Milk Powder 400g',      400::numeric,   'packet', 'packet', 'packet', 'carton',  3.00::numeric,  6::numeric),
  ('water_bottled_500ml',   'Bottled Water 500ml',   500::numeric,   'bottle', 'bottle', 'bottle', 'carton',  0.50::numeric,  24::numeric),
  ('soap_bar_100g',         'Bar Soap 100g',         100::numeric,   'piece',  'piece',  'piece',  'box',     0.50::numeric,  10::numeric),
  ('biscuit_assorted_100g', 'Assorted Biscuit 100g', 100::numeric,   'packet', 'packet', 'packet', 'carton',  0.30::numeric,  12::numeric),
  ('pasta_dry_500g',        'Dry Pasta 500g',        500::numeric,   'packet', 'packet', 'packet', 'box',     0.80::numeric,  8::numeric),
  ('bread_loaf',            'Bread Loaf',            1::numeric,     'piece',  'piece',  'piece',  'piece',   0.25::numeric,  6::numeric)
) as r(item_code, name, package_qty, package_unit, base_unit, sale_unit, receive_unit, price, reorder)
  on r.item_code = ci.code
on conflict (catalog_item_id, revision_number) do nothing;

update public.catalog_item ci
set current_revision_id = cir.id
from public.catalog_item_revision cir
where cir.catalog_item_id = ci.id
  and cir.revision_number = 1
  and ci.current_revision_id is null;

-- Per-item unit conversions. Each item gets its base unit (conversion 1)
-- plus its receive package (conversion = how many base units per package).
-- bread is single-unit so it has only its base.
insert into public.catalog_item_unit (
  catalog_item_id, revision_id, unit_code, conversion_to_base,
  is_base_unit, allow_sale, allow_receive, sort_order
)
select cir.catalog_item_id, cir.id, u.unit_code, u.conversion,
       u.is_base, u.allow_sale, u.allow_receive, u.sort_order
from public.catalog_item_revision cir
join public.catalog_item ci on ci.id = cir.catalog_item_id
join (values
  ('rice_basmati_25kg',     'kg',     1::numeric,   true,  true,  true,  1),
  ('rice_basmati_25kg',     'bag',    25::numeric,  false, false, true,  2),
  ('sugar_white_50kg',      'kg',     1::numeric,   true,  true,  true,  1),
  ('sugar_white_50kg',      'bag',    50::numeric,  false, false, true,  2),
  ('oil_cooking_1l',        'litre',  1::numeric,   true,  true,  true,  1),
  ('oil_cooking_1l',        'bottle', 1::numeric,   false, true,  true,  2),
  ('tea_black_500g',        'packet', 1::numeric,   true,  true,  true,  1),
  ('tea_black_500g',        'box',    24::numeric,  false, false, true,  2),
  ('milk_powder_400g',      'packet', 1::numeric,   true,  true,  true,  1),
  ('milk_powder_400g',      'carton', 12::numeric,  false, false, true,  2),
  ('water_bottled_500ml',   'bottle', 1::numeric,   true,  true,  true,  1),
  ('water_bottled_500ml',   'carton', 12::numeric,  false, false, true,  2),
  ('soap_bar_100g',         'piece',  1::numeric,   true,  true,  true,  1),
  ('soap_bar_100g',         'box',    50::numeric,  false, false, true,  2),
  ('biscuit_assorted_100g', 'packet', 1::numeric,   true,  true,  true,  1),
  ('biscuit_assorted_100g', 'carton', 24::numeric,  false, false, true,  2),
  ('pasta_dry_500g',        'packet', 1::numeric,   true,  true,  true,  1),
  ('pasta_dry_500g',        'box',    20::numeric,  false, false, true,  2),
  ('bread_loaf',            'piece',  1::numeric,   true,  true,  true,  1)
) as u(item_code, unit_code, conversion, is_base, allow_sale, allow_receive, sort_order)
  on u.item_code = ci.code
where cir.revision_number = 1
on conflict (catalog_item_id, revision_id, unit_code) do nothing;

insert into public.catalog_item_alias (catalog_item_id, language_code, alias_text, source)
select ci.id, a.lang, a.alias_text, 'platform'
from public.catalog_item ci
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
  ('bread_loaf',            'so', 'rooti')
) as a(item_code, lang, alias_text) on a.item_code = ci.code
on conflict (catalog_item_id, language_code, alias_text) do nothing;

----------------------------------------------------------------------
-- 2. Template + packs + settings + units
----------------------------------------------------------------------

insert into public.template (code, kind, name, locale_default, currency_default, version, is_active)
values ('grocery', 'shop_starter', 'Grocery', 'so', 'USD', 1, true)
on conflict (code, version) do nothing;

insert into public.template_pack (template_id, code, version, is_required, file_path)
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
  ('piece',  jsonb_build_object('en','Piece',  'so','Xabba'),    1),
  ('kg',     jsonb_build_object('en','Kg',     'so','Kg'),       2),
  ('gram',   jsonb_build_object('en','Gram',   'so','Garaam'),   3),
  ('litre',  jsonb_build_object('en','Litre',  'so','Litir'),    4),
  ('ml',     jsonb_build_object('en','ml',     'so','ml'),       5),
  ('bag',    jsonb_build_object('en','Bag',    'so','Bac'),      6),
  ('box',    jsonb_build_object('en','Box',    'so','Sanduuq'),  7),
  ('carton', jsonb_build_object('en','Carton', 'so','Kartoon'),  8),
  ('bottle', jsonb_build_object('en','Bottle', 'so','Dhalo'),    9),
  ('packet', jsonb_build_object('en','Packet', 'so','Baakad'),  10)
) as u(unit_code, label, sort_order)
where t.code = 'grocery' and t.version = 1
on conflict (template_id, unit_code) do nothing;

----------------------------------------------------------------------
-- 3. Template items (candidate list, linked to catalog).
--    These rows do NOT cause materialization on apply_template — they
--    are the curated grocery candidate set search prefers when ranking.
----------------------------------------------------------------------

insert into public.template_item (
  template_id, item_code, catalog_item_id, catalog_revision_id,
  suggested_sale_price_override, reorder_threshold_override, sort_order
)
select t.id, ci.code, ci.id, cir.id, null, null, ord.sort_order
from public.template t
join (values
  ('rice_basmati_25kg',      1),
  ('sugar_white_50kg',       2),
  ('oil_cooking_1l',         3),
  ('tea_black_500g',         4),
  ('milk_powder_400g',       5),
  ('water_bottled_500ml',    6),
  ('soap_bar_100g',          7),
  ('biscuit_assorted_100g',  8),
  ('pasta_dry_500g',         9),
  ('bread_loaf',            10)
) as ord(item_code, sort_order) on true
join public.catalog_item ci on ci.code = ord.item_code
join public.catalog_item_revision cir
  on cir.catalog_item_id = ci.id and cir.revision_number = 1
where t.code = 'grocery' and t.version = 1
on conflict (template_id, item_code) do nothing;

----------------------------------------------------------------------
-- 4. Expense categories
----------------------------------------------------------------------

insert into public.template_expense_category (template_id, code, name, name_translations, sort_order)
select t.id, c.code, c.name, c.translations, c.sort_order
from public.template t
cross join (values
  ('rent',        'Rent',        jsonb_build_object('en','Rent',        'so','Kiro'),     1),
  ('electricity', 'Electricity', jsonb_build_object('en','Electricity', 'so','Koronto'),  2),
  ('salary',      'Salary',      jsonb_build_object('en','Salary',      'so','Mushahar'), 3),
  ('transport',   'Transport',   jsonb_build_object('en','Transport',   'so','Gaadiid'),  4),
  ('other',       'Other',       jsonb_build_object('en','Other',       'so','Kale'),     5)
) as c(code, name, translations, sort_order)
where t.code = 'grocery' and t.version = 1
on conflict (template_id, code) do nothing;

----------------------------------------------------------------------
-- 5. Starter favorites. THESE are the only items apply_template
--    pre-activates. Everything else stays catalog-only until first use.
--    Five items × Sale + Receive screens = ten quick-action rows.
----------------------------------------------------------------------

insert into public.template_quick_action (template_id, screen, position, item_code, label)
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
