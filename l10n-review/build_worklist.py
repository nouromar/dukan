#!/usr/bin/env python3
"""Build the Somali-rewrite worklist + role/budget map from the live ARBs.

Outputs (under l10n-review/):
  key_roles.json   {key: {role, max_chars, area, en, so}}  — feeds the budget lint
  worklist.csv     Area,Key,Role,MaxChars,English,Somali (current),
                   Somali (AI),Reviewer notes  — the AI fills the last two cols

Role is derived from the key-name suffix (which the codebase keeps tightly aligned
with the render site — *Button, *Title, *Hint, *Toast, *ConfirmTitle/Body, *Label,
*Tab/Badge, *EmptyMessage), plus a small home-tile override set. max_chars is the
per-role length budget; flexible roles (bodies, errors, toasts) carry null = no
lint. Regenerate any time the ARBs change:  python3 l10n-review/build_worklist.py
"""

import json
import csv
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARB_DIR = os.path.join(ROOT, "app", "dukan", "lib", "l10n")
OUT_DIR = os.path.join(ROOT, "l10n-review")

# Home action tiles — tightest budget (1 word, wraps on long Somali words).
HOME_TILES = {
    "sale", "receive", "expense", "paymentInLabel", "paymentOutLabel",
    "drawerProducts", "reportsTitle",
}

# (suffix, role, max_chars). Checked in order; first match wins. max_chars None
# means "flexible — skip the length lint" (bodies, errors, hints, toasts).
SUFFIX_RULES = [
    ("ConfirmTitle", "dialog_title", 30),
    ("ConfirmBody", "dialog_body", None),
    ("ConfirmYes", "button", 14),
    ("ConfirmNo", "button", 14),
    ("SaveButton", "button_save", 12),
    ("Button", "button", 18),
    ("Tab", "chip", 12),
    ("Badge", "chip", 12),
    ("Title", "title", 20),
    ("Hint", "hint", None),
    ("Helper", "helper", None),
    ("Header", "header", 24),
    ("Label", "label", 24),
    ("Toast", "toast", None),
    ("EmptyMessage", "empty_error", None),
    ("LoadFailedMessage", "empty_error", None),
    ("FailedMessage", "empty_error", None),
    ("Message", "empty_error", None),
]

# Feature area from key prefix (longest prefix wins). Drives batching + the CSV.
AREA_PREFIXES = [
    ("shopItem", "Products"), ("products", "Products"), ("catalogPicker", "Products"),
    ("stockAdjust", "Products"), ("deactivateItem", "Products"),
    ("sale", "Sale"), ("cart", "Sale"), ("addNewItem", "Sale"), ("lineEditor", "Sale"),
    ("receive", "Receive"), ("supplier", "Receive"), ("unitPicker", "Receive"),
    ("addPackaging", "Receive"), ("bono", "Receive"),
    ("payment", "Payment"),
    ("expense", "Expense"),
    ("party", "Parties"), ("parties", "Parties"),
    ("reports", "Reports"),
    ("settings", "Settings"), ("manageCategories", "Settings"),
    ("storageSync", "Settings"), ("scanner", "Settings"),
    ("onboarding", "Onboarding"), ("owner", "Onboarding"), ("otp", "Onboarding"),
    ("login", "Onboarding"), ("createShop", "Onboarding"), ("shopType", "Onboarding"),
    ("setup", "Onboarding"), ("phone", "Onboarding"), ("email", "Onboarding"),
    ("drawer", "Menu"), ("home", "Home"), ("today", "Home"),
    ("dateRange", "Filters"), ("filter", "Filters"),
    ("relativeTime", "Common"), ("history", "History"),
]


def load_arb(name):
    with open(os.path.join(ARB_DIR, name), encoding="utf-8") as f:
        data = json.load(f)
    # Real message keys only — drop @@locale and @meta blocks.
    return {k: v for k, v in data.items()
            if not k.startswith("@") and isinstance(v, str)}


def role_for(key):
    if key in HOME_TILES:
        return ("home_tile", 14)
    if "dateRange" in key:
        return ("chip", 12)
    for suffix, role, mx in SUFFIX_RULES:
        if key.endswith(suffix):
            return (role, mx)
    return ("body", None)


def area_for(key):
    best = ("Common", -1)
    for prefix, area in AREA_PREFIXES:
        if key.startswith(prefix) and len(prefix) > best[1]:
            best = (area, len(prefix))
    return best[0]


def main():
    en = load_arb("app_en.arb")
    so = load_arb("app_so.arb")
    keys = list(en.keys())  # template order = feature-grouped

    roles = {}
    for k in keys:
        role, mx = role_for(k)
        roles[k] = {
            "role": role, "max_chars": mx, "area": area_for(k),
            "en": en[k], "so": so.get(k, ""),
        }

    with open(os.path.join(OUT_DIR, "key_roles.json"), "w", encoding="utf-8") as f:
        json.dump(roles, f, ensure_ascii=False, indent=2)

    with open(os.path.join(OUT_DIR, "worklist.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Area", "Key", "Role", "MaxChars", "English",
                    "Somali (current)", "Somali (AI)", "Reviewer notes"])
        for k in keys:
            r = roles[k]
            w.writerow([r["area"], k, r["role"],
                        r["max_chars"] if r["max_chars"] is not None else "",
                        r["en"], r["so"], "", ""])

    # Summary to stdout.
    from collections import Counter
    areas = Counter(roles[k]["area"] for k in keys)
    print(f"{len(keys)} keys → key_roles.json + worklist.csv")
    print("by area:", dict(areas.most_common()))

    # Budget overflow report (advisory lint): Somali values over their role
    # budget. The rewrite drives this toward zero; once near zero, promote it to
    # a hard test (see test/l10n/arb_parity_test.dart).
    over = [(k, roles[k]) for k in keys
            if roles[k]["max_chars"] and "{" not in roles[k]["so"]
            and len(roles[k]["so"]) > roles[k]["max_chars"]]
    print(f"\n{len(over)} Somali values exceed their role budget:")
    for k, r in sorted(over, key=lambda x: -len(x[1]["so"])):
        print(f"  {r['role']:12} {r['max_chars']:>3} < {len(r['so']):>3}  "
              f"{k:34} {r['so']!r}")


if __name__ == "__main__":
    main()
