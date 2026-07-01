#!/usr/bin/env python3
"""Apply an approved proposals JSON into app_so.arb — values only, keys untouched.

Replaces each key's Somali value by exact-fragment match ("key": "current" ->
"key": "new"), so ALL file formatting/ordering is preserved and only the changed
lines move. The current value is read from key_roles.json (regenerate it first if
the arb changed). Aborts loudly if any fragment isn't found (drift), changing
nothing.

Usage:  python3 l10n-review/apply_proposals.py l10n-review/proposals_batch1.json
Then:   (cd app/dukan && flutter gen-l10n && flutter test test/l10n/arb_parity_test.dart)
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARB = os.path.join(ROOT, "app", "dukan", "lib", "l10n", "app_so.arb")
ROLES = os.path.join(ROOT, "l10n-review", "key_roles.json")


def frag(key, value):
    # Matches the arb's raw-UTF-8 (ensure_ascii=False) storage exactly.
    return f'{json.dumps(key, ensure_ascii=False)}: {json.dumps(value, ensure_ascii=False)}'


def main(path):
    proposals = {k: v for k, v in json.load(open(path, encoding="utf-8")).items()
                 if not k.startswith("_")}
    roles = json.load(open(ROLES, encoding="utf-8"))
    text = open(ARB, encoding="utf-8").read()

    edits, errors = [], []
    for key, (new_so, _note) in proposals.items():
        if key not in roles:
            errors.append(f"{key}: not in key_roles.json (regenerate?)")
            continue
        cur = roles[key]["so"]
        if new_so == cur:
            continue  # no-op
        old_frag, new_frag = frag(key, cur), frag(key, new_so)
        if text.count(old_frag) != 1:
            errors.append(f"{key}: found {text.count(old_frag)}x (expected 1) — drift")
            continue
        edits.append((old_frag, new_frag, key))

    if errors:
        print("ABORTED — no changes written:")
        print("\n".join("  " + e for e in errors))
        sys.exit(1)

    for old_frag, new_frag, _ in edits:
        text = text.replace(old_frag, new_frag, 1)
    open(ARB, "w", encoding="utf-8").write(text)
    print(f"Applied {len(edits)} Somali value(s) to app_so.arb:")
    for _, _, k in edits:
        print(f"  {k}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "l10n-review/proposals_batch1.json")
