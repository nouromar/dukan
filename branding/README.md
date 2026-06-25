# Dukan branding — app icon

## Final mark

`vault-d-c-disc-d.svg` — a green **vault/safe** with a gold dial disc and the
**"D" knocked out** of the disc in negative space. It reads as "keep the
business's money safe" while tying back to Dukan via the D.

512 × 512, transparent background, mark inside the Android adaptive-icon
**safe zone** (centre ~66% of canvas) so circular / squircle / rounded-square
masks won't clip it.

### Colours
| Token | Hex | Use |
| ----- | --- | --- |
| Green (primary) | `#005C46` | safe body + D (matches `seedColor`, `app/dukan/lib/main.dart`) |
| Gold (accent)   | `#F2B441` | dial disc / money |
| Cream           | `#F5EFE6` | door seam + handle |

## Next step — ship it

1. Export `vault-d-c-disc-d.svg` to `icon.png` (1024 × 1024, transparent),
   plus `icon_foreground.png` and `icon_background.png` (`#005C46`) for the
   Android adaptive icon.
2. Add `flutter_launcher_icons` to `app/dukan/pubspec.yaml` dev_dependencies
   with a config block, then run `dart run flutter_launcher_icons` to generate
   every Android density + iOS size + web favicon, replacing the default
   Flutter `ic_launcher.png`.

Test: open the SVG in a browser and shrink to ~48 px — the D should stay
legible inside the disc and not fill in.
