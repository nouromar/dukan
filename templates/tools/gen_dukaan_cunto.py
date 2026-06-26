#!/usr/bin/env python3
"""Generate the Dukaan Cunto seed migration (0017) + JSON template specs
from the reviewed catalog CSV. Single source -> SQL + JSON, no hand-dup."""
import csv, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CSV = f"{ROOT}/templates/dukaan-cunto-catalog-review.csv"
MIG = f"{ROOT}/supabase/migrations/0017_seed_dukaan_cunto.sql"

# CSV category label -> (code, en, so, sort)
CATS = {
    "Raashin (Staples)":   ("raashin",   "Staples",   "Raashin",   1),
    "Cabitaan (Beverages)":("cabitaan",  "Beverages", "Cabitaan",  2),
    "Macmacaan (Snacks)":  ("macmacaan", "Snacks",    "Macmacaan", 3),
    "Xawaash (Spices)":    ("xawaash",   "Spices",    "Xawaash",   4),
    "Qasacado (Canned)":   ("qasacado",  "Canned",    "Qasacado",  5),
    "Guriga (Household)":  ("guriga",    "Household", "Guriga",    6),
    "Caafimaad (Health)":  ("caafimaad", "Health",    "Caafimaad", 7),
}
# units not yet in the global unit table (0002) -> (en, so)
NEW_UNITS = {
    "jerrycan": ("Jerrycan", "Jerigan"),
    "can":      ("Can",      "Qasacad"),
    "tin":      ("Tin",      "Tini"),
    "jar":      ("Jar",      "Jaar"),
}
# template_unit labels for every unit the catalog uses (+ standard)
UNIT_LABELS = {
    "piece": ("Piece", "Xabba"), "kg": ("Kg", "Kiilo"), "gram": ("Gram", "Garaam"),
    "litre": ("Litre", "Liitir"), "ml": ("ml", "ml"), "bag": ("Bag", "Bac"),
    "box": ("Box", "Sanduuq"), "carton": ("Carton", "Kartoon"),
    "bottle": ("Bottle", "Dhalo"), "packet": ("Packet", "Baakad"),
    "jerrycan": ("Jerrycan", "Jerigan"), "can": ("Can", "Qasacad"),
    "tin": ("Tin", "Tini"), "jar": ("Jar", "Jaar"),
}
SETTINGS = [
    ("locale_default", "so"), ("currency_default", "USD"),
    ("timezone_default", "Africa/Mogadishu"), ("sale_payment_default", "cash"),
    ("receive_payment_default", "credit"), ("negative_stock_policy", "warn"),
]
EXPENSE = [
    ("rent", "Rent", "Kiro", 1), ("electricity", "Electricity", "Koronto", 2),
    ("water", "Water", "Biyo", 3), ("salary", "Salary", "Mushahar", 4),
    ("transport", "Transport", "Gaadiid", 5), ("supplies", "Supplies", "Alaab", 6),
    ("other", "Other", "Kale", 7),
]
QUICK = [  # (screen, position, item_code)
    ("sale", 1, "bariis_basmati_25kg"), ("sale", 2, "sonkor_kg"),
    ("sale", 3, "saliid_1l"), ("sale", 4, "baasto_500g"),
    ("sale", 5, "shaah_caleen_250g"), ("sale", 6, "biyo_500ml"),
    ("receive", 1, "bariis_basmati_25kg"), ("receive", 2, "sonkor_kg"),
    ("receive", 3, "saliid_1l"), ("receive", 4, "shaah_caleen_250g"),
]
TEST = "test_dukaan_cunto"
EMPTY = "empty_dukaan_cunto"

def q(s):  # SQL string literal escape
    return "'" + str(s).replace("'", "''") + "'"

# ---- read CSV ----
items = []
with open(CSV) as f:
    for r in csv.DictReader(f):
        code = r["Code"].strip()
        if not code:
            continue
        cat = CATS[r["Category"].strip()]
        aliases = [a.strip() for a in r["Aliases (so; en)"].split(";") if a.strip()]
        items.append({
            "code": code,
            "cat_code": cat[0],
            "name_so": r["Name (Somali)"].strip(),
            "name_en": r["Name (English)"].strip(),
            "base_unit": r["Base unit"].strip(),
            "price": r["Sale price (USD)"].strip(),
            "reorder": r["Reorder threshold"].strip(),
            "aliases": aliases,
        })

units_used = sorted({it["base_unit"] for it in items} | {u for u, _ in SETTINGS if False})
tmpl_units = sorted({it["base_unit"] for it in items})

# ---- emit SQL ----
out = []
W = out.append
W("-- Seed the Dukaan Cunto starter templates (Somali grocery / dukaan cunto).")
W("--")
W("-- Two sibling templates share one global catalog (categories, items,")
W("-- units, aliases):")
W("--   * test_dukaan_cunto  — full: ~%d items + quick actions, for seeded test shops." % len(items))
W("--   * empty_dukaan_cunto — config only (settings + expense categories),")
W("--     no inventory / no quick actions, for onboarding a real shop from scratch.")
W("--")
W("-- Mirrors 0016 (grocery). Idempotent: on conflict do nothing. Authoritative")
W("-- apply path is `supabase db reset`; apply_template(shop, template) materializes.")
W("")
W("--------------------------------------------------------------------")
W("-- 1. Units not yet in the global unit table (0002).")
W("--------------------------------------------------------------------")
W("insert into public.unit (code, default_label, label_translations, is_active)")
W("values")
rows = [f"  ({q(u)}, {q(en)}, jsonb_build_object('so', {q(so)}), true)"
        for u, (en, so) in NEW_UNITS.items()]
W(",\n".join(rows))
W("on conflict (code) do nothing;")
W("")
W("--------------------------------------------------------------------")
W("-- 2. Categories (Somali set for dukaan cunto).")
W("--------------------------------------------------------------------")
W("insert into public.category (code, name, name_translations, sort_order)")
W("values")
rows = []
for label, (code, en, so, sort) in CATS.items():
    rows.append(f"  ({q(code)}, {q(en)}, jsonb_build_object('en', {q(en)}, 'so', {q(so)}), {sort})")
W(",\n".join(rows))
W("on conflict (code) do nothing;")
W("")
W("--------------------------------------------------------------------")
W("-- 3. Items (global SKUs, slim — display name lives in item_alias).")
W("--------------------------------------------------------------------")
W("insert into public.item (code, category_id, base_unit_code, is_active)")
W("select i.item_code, c.id, i.base_unit, true")
W("from (values")
rows = [f"  ({q(it['code'])}, {q(it['cat_code'])}, {q(it['base_unit'])})" for it in items]
W(",\n".join(rows))
W(") as i(item_code, category_code, base_unit)")
W("join public.category c on c.code = i.category_code")
W("on conflict (code) do nothing;")
W("")
W("--------------------------------------------------------------------")
W("-- 4. Item aliases — display (one per language) + search nicknames.")
W("--------------------------------------------------------------------")
W("insert into public.item_alias (item_id, alias_text, language_code, is_display, source, weight)")
W("select i.id, a.alias_text, a.lang, true, 'platform', 0")
W("from public.item i")
W("join (values")
rows = []
for it in items:
    rows.append(f"  ({q(it['code'])}, 'so', {q(it['name_so'])})")
    rows.append(f"  ({q(it['code'])}, 'en', {q(it['name_en'])})")
W(",\n".join(rows))
W(") as a(item_code, lang, alias_text) on a.item_code = i.code")
W("on conflict (item_id, language_code, alias_text_norm) do nothing;")
W("")
W("-- Search nicknames (is_display=false), stored under both languages so")
W("-- type-ahead matches regardless of UI language.")
W("insert into public.item_alias (item_id, alias_text, language_code, is_display, source, weight)")
W("select i.id, a.alias_text, a.lang, false, 'platform', 0")
W("from public.item i")
W("join (values")
rows = []
for it in items:
    for al in it["aliases"]:
        for lang in ("so", "en"):
            rows.append(f"  ({q(it['code'])}, {q(lang)}, {q(al)})")
W(",\n".join(rows))
W(") as a(item_code, lang, alias_text) on a.item_code = i.code")
W("on conflict (item_id, language_code, alias_text_norm) do nothing;")
W("")
W("--------------------------------------------------------------------")
W("-- 5. Item units — single base packaging per SKU (conversion=1,")
W("--    default for both sale and receive).")
W("--------------------------------------------------------------------")
W("insert into public.item_unit (item_id, unit_code, conversion_to_base,")
W("  is_default_sale, is_default_receive, sort_order, is_active)")
W("select i.id, u.unit_code, 1, true, true, 1, true")
W("from public.item i")
W("join (values")
rows = [f"  ({q(it['code'])}, {q(it['base_unit'])})" for it in items]
W(",\n".join(rows))
W(") as u(item_code, unit_code) on u.item_code = i.code")
W("on conflict (item_id, unit_code, conversion_to_base) do nothing;")
W("")
W("--------------------------------------------------------------------")
W("-- 6. Templates (both siblings).")
W("--------------------------------------------------------------------")
W("insert into public.template (code, kind, name, locale_default, currency_default, version, is_active)")
W("values")
W(f"  ({q(TEST)},  'shop_starter', 'Test Dukaan Cunto',  'so', 'USD', 1, true),")
W(f"  ({q(EMPTY)}, 'shop_starter', 'Empty Dukaan Cunto', 'so', 'USD', 1, true)")
W("on conflict (code, version) do nothing;")
W("")

def per_template(code, packs):
    W(f"-- ---- {code} ----")
    # packs
    W("insert into public.template_pack (template_id, code, version, is_required, file_path)")
    W("select t.id, p.code, p.version, p.is_required, p.file_path")
    W("from public.template t")
    W("cross join (values")
    prows = [f"  ({q(pc)}, 1, {str(req).lower()}, {q(f'templates/{code}/{fn}')})"
             for pc, req, fn in packs]
    W(",\n".join(prows))
    W(") as p(code, version, is_required, file_path)")
    W(f"where t.code = {q(code)} and t.version = 1")
    W("on conflict (template_id, code, version) do nothing;")
    W("")
    # settings
    W("insert into public.template_setting (template_id, key, value)")
    W("select t.id, s.key, s.value")
    W("from public.template t")
    W("cross join (values")
    srows = [f"  ({q(k)}, to_jsonb({q(v)}::text))" for k, v in SETTINGS]
    W(",\n".join(srows))
    W(") as s(key, value)")
    W(f"where t.code = {q(code)} and t.version = 1")
    W("on conflict (template_id, key) do nothing;")
    W("")
    # units
    W("insert into public.template_unit (template_id, unit_code, label, sort_order)")
    W("select t.id, u.unit_code, u.label, u.sort_order")
    W("from public.template t")
    W("cross join (values")
    urows = []
    for i, u in enumerate(tmpl_units, 1):
        en, so = UNIT_LABELS[u]
        urows.append(f"  ({q(u)}, jsonb_build_object('en', {q(en)}, 'so', {q(so)}), {i})")
    W(",\n".join(urows))
    W(") as u(unit_code, label, sort_order)")
    W(f"where t.code = {q(code)} and t.version = 1")
    W("on conflict (template_id, unit_code) do nothing;")
    W("")
    # expense categories
    W("insert into public.template_expense_category (template_id, code, name, name_translations, sort_order)")
    W("select t.id, c.code, c.name, c.translations, c.sort_order")
    W("from public.template t")
    W("cross join (values")
    erows = [f"  ({q(c)}, {q(en)}, jsonb_build_object('en', {q(en)}, 'so', {q(so)}), {s})"
             for c, en, so, s in EXPENSE]
    W(",\n".join(erows))
    W(") as c(code, name, translations, sort_order)")
    W(f"where t.code = {q(code)} and t.version = 1")
    W("on conflict (template_id, code) do nothing;")
    W("")

per_template(EMPTY, [
    ("settings", True, "settings.json"),
    ("expense_categories", True, "expense-categories.json"),
])
per_template(TEST, [
    ("catalog", True, "catalog.json"),
    ("settings", True, "settings.json"),
    ("expense_categories", True, "expense-categories.json"),
    ("quick_actions", False, "quick-actions.json"),
])

W("--------------------------------------------------------------------")
W("-- 7. Template items + item aliases + quick actions (TEST only).")
W("--------------------------------------------------------------------")
W("insert into public.template_item (template_id, item_code, item_id,")
W("  suggested_sale_price, reorder_threshold, sort_order)")
W("select t.id, i.code, i.id, p.price, p.reorder, p.sort_order")
W("from public.template t")
W("join (values")
rows = [f"  ({q(it['code'])}, {it['price']}::numeric, {it['reorder']}::numeric, {i})"
        for i, it in enumerate(items, 1)]
W(",\n".join(rows))
W(") as p(item_code, price, reorder, sort_order) on true")
W("join public.item i on i.code = p.item_code")
W(f"where t.code = {q(TEST)} and t.version = 1")
W("on conflict (template_id, item_code) do nothing;")
W("")
W("insert into public.template_item_alias (template_id, item_code, language_code, alias_text, is_display, weight)")
W("select t.id, a.item_code, a.lang, a.alias_text, true, 0")
W("from public.template t")
W("cross join (values")
rows = []
for it in items:
    rows.append(f"  ({q(it['code'])}, 'so', {q(it['name_so'])})")
    rows.append(f"  ({q(it['code'])}, 'en', {q(it['name_en'])})")
W(",\n".join(rows))
W(") as a(item_code, lang, alias_text)")
W(f"where t.code = {q(TEST)} and t.version = 1")
W("on conflict (template_id, item_code, language_code, alias_text_norm) do nothing;")
W("")
W("insert into public.template_quick_action (template_id, screen, position, item_code, label)")
W("select t.id, q.screen, q.position, q.item_code, null")
W("from public.template t")
W("cross join (values")
rows = [f"  ({q(s)}, {p}, {q(ic)})" for s, p, ic in QUICK]
W(",\n".join(rows))
W(") as q(screen, position, item_code)")
W(f"where t.code = {q(TEST)} and t.version = 1")
W("on conflict (template_id, screen, position) do nothing;")
W("")

with open(MIG, "w") as f:
    f.write("\n".join(out))
print(f"Wrote {MIG} ({len(out)} lines, {len(items)} items)")

# ---- emit JSON specs ----
def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")

for code, name_en, name_so, full in [
    (TEST, "Test Dukaan Cunto", "Dukaan Cunto (Tijaabo)", True),
    (EMPTY, "Empty Dukaan Cunto", "Dukaan Cunto (Madhan)", False),
]:
    d = f"{ROOT}/templates/{code}"
    packs = [{"code": "settings", "file": "settings.json", "required": True},
             {"code": "expense_categories", "file": "expense-categories.json", "required": True}]
    if full:
        packs = ([{"code": "catalog", "file": "catalog.json", "required": True}] + packs +
                 [{"code": "quick_actions", "file": "quick-actions.json", "required": False}])
    write_json(f"{d}/manifest.json", {
        "kind": "shop_starter", "code": code,
        "name_en": name_en, "name_so": name_so, "version": 1,
        "locale_default": "so", "currency_default": "USD",
        "description": ("Somali dukaan cunto starter — full catalog." if full
                        else "Somali dukaan cunto starter — config only, no inventory."),
        "packs": packs,
    })
    write_json(f"{d}/settings.json", {
        "kind": "configuration_pack", "pack": "settings", "template_code": code,
        "version": 1, "settings": {k: v for k, v in SETTINGS},
    })
    write_json(f"{d}/expense-categories.json", {
        "kind": "configuration_pack", "pack": "expense_categories", "template_code": code,
        "version": 1,
        "expense_categories": [{"code": c, "name_en": en, "name_so": so}
                               for c, en, so, _ in EXPENSE],
    })
    if full:
        write_json(f"{d}/catalog.json", {
            "kind": "configuration_pack", "pack": "catalog", "template_code": code,
            "version": 1,
            "units": [{"code": u} for u in tmpl_units],
            "items": [{
                "code": it["code"], "category": it["cat_code"],
                "display_name_en": it["name_en"], "display_name_so": it["name_so"],
                "base_unit_code": it["base_unit"],
                "default_sale_unit_code": it["base_unit"],
                "default_receive_unit_code": it["base_unit"],
                "suggested_sale_price_usd": float(it["price"]),
                "reorder_threshold": float(it["reorder"]),
                "sort_order": i,
                "aliases_so": it["aliases"], "aliases_en": it["aliases"],
                "unit_conversions": [{"unit_code": it["base_unit"], "conversion_to_base": 1,
                                      "allow_sale": True, "allow_receive": True, "sort_order": 1}],
            } for i, it in enumerate(items, 1)],
        })
        write_json(f"{d}/quick-actions.json", {
            "kind": "configuration_pack", "pack": "quick_actions", "template_code": code,
            "version": 1,
            "favorites": [{"screen": s, "position": p, "item_code": ic} for s, p, ic in QUICK],
        })
    print(f"Wrote templates/{code}/ ({len(packs)} packs)")
