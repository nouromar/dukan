# Dukan branding — app icon concepts

Open each `.svg` in a browser (drag onto a Chrome / Safari window) to
preview at full size. Resize the window down to ~48 px to test the
mark still reads — that's the only test that actually matters for an
app icon.

## What's here

### First-pass directions (mixed colours, exploratory)

| File                          | Direction                                                                                                          |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `concept-d-letter.svg`        | Bold letterform "D". Most scalable; reads at 48dp. Single colour.                                                  |
| `concept-shop-arch.svg`       | Storefront silhouette with arched doorway. Single colour. Not letter-dependent.                                    |
| `concept-shop-with-d.svg`     | Shop body + canopy + "D" inset in the doorway. Two colours.                                                        |

### Variations around "shop + D" — all in brand green `#005C46`

| File                                | Treatment                                                                                                       |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `v1-d-in-arched-doorway.svg`        | Arched doorway, "D" inset inside. Most figurative — shop reads first, D rewards a second look.                  |
| `v2-d-shaped-doorway-mono.svg`      | The doorway IS a D (upright, curved-right). Single colour, cleanest scaling, fewest moving parts.               |
| `v3-d-on-canopy-sign.svg`           | Flat-roof modern shop; "D" lives on the canopy band like a real shopfront sign. Two-colour.                     |
| `v4-tall-d-in-door.svg`             | Bold "D" almost fills the doorway. D is the hero, shop is the frame. Two-colour.                                |

### Second-pass additions — fill the gaps (warmth, market read, business-not-just-shop, wordmark)

| File                       | Treatment                                                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `new-a-awning.svg`         | Scalloped awning over shop + cream doorway. Warmer/friendlier than the pitched-roof marks. Green + cream.          |
| `new-b-doorway-gold.svg`   | Same geometry as `v1` but the doorway glows **gold** `#F2B441` — "the shop is open". Introduces a warm accent.     |
| `new-c-bag-d.svg`          | Shopping bag with the "D" cut in. Reads as "any business", not only a storefront. Green + cream.                   |
| `new-d-wordmark.svg`       | Lowercase "dukan" wordmark for splash / app-bar / web portal. Outline the `<text>` to paths before shipping.       |

All canvases are 512 × 512 (the wordmark is 360 × 120), paths inside the
**adaptive-icon safe zone** (centre ~66% of canvas) so Android's circular /
squircle / rounded-square masks won't clip the mark.

## Brand colour

Primary `#005C46` (deep forest green) — matches `seedColor` in
`app/dukan/lib/main.dart`. Every shipped variation uses this so the
icon is consistent with the app's primary buttons.

Cream secondary `#F5EFE6` is used only for negative-space affordances
(doorway openings, canopy bands) — never as a brand-bearing colour.

## Next step

1. Pick one of v1 – v4. Refine if you want — a Fiverr / Dribbble
   designer pass (~$50-200) will give you a polished SVG + 1024×1024
   PNG + adaptive-icon foreground / background layers split for
   Android.
2. Save the chosen master as `branding/icon.png` (1024×1024, transparent
   background) plus `branding/icon_foreground.png` and
   `branding/icon_background.png` for Android adaptive icons.
3. Add `flutter_launcher_icons` to `app/dukan/pubspec.yaml`
   dev_dependencies and run `dart run flutter_launcher_icons` —
   generates every Android density + iOS size + web favicons in one go.

When you've picked + have the PNG master, ask me to wire
`flutter_launcher_icons`.
