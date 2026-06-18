/// Global multiplier applied to every declared font size in the app.
///
/// Lowered to bring text back near Material 3 defaults — the custom
/// textTheme in `main.dart` historically ran ~13 % larger than M3 stock
/// (titleLarge 24 px vs M3's 22, bodyLarge 18 vs 16, labelLarge 18 vs
/// 14). On a real iPhone 14 that landed "a bit big" everywhere. 0.92
/// shaves ~8 % uniformly without going below comfortable thresholds:
/// the smallest live size (cart line packaging label, originally
/// 11 px) lands at ~10.1 px, still above the iOS readable floor.
///
/// Used by `_buildTheme()` in `main.dart` and by the daily-flow
/// screens (`sale_screen.dart`, `receive_screen.dart`) that bypass the
/// textTheme with hardcoded `fontSize:` values on product-card grids.
///
/// Tune up (closer to 1.0) if pilot shopkeepers find any size too
/// small; tune down (0.90 / 0.88) for a more obvious shrink. Single
/// number to change.
const double kFontScale = 0.92;
