// Shared responsive grid delegate for the Sale and Receive item results.
//
// Both screens used to hard-code `SliverGridDelegateWithFixedCrossAxisCount(
// crossAxisCount: 2, mainAxisExtent: 110)`, which wastes horizontal space on
// wider phones (fewer favourites per screen → more scrolling → slower 5-item
// sale) and clips the tile content at large system font scales. This delegate:
//
//   * lets the column count grow with width via `maxCrossAxisExtent` — 2
//     columns on a narrow phone, 3+ on a wider one; and
//   * grows the tile height with the OS text scale so a big font never clips
//     the item name + price + stock line.
//
// Keep the two screens calling this one helper so their grids stay identical.

import 'package:flutter/widgets.dart';

/// Baseline tile height (dp) at text-scale 1.0. Matches the previous fixed
/// `mainAxisExtent: 110`.
const double _kBaseTileExtent = 110;

/// Target max tile width (dp). At this cap a ~360dp-wide phone yields 2
/// columns and a ~600dp-wide one yields 3, without any per-screen branching.
const double _kMaxTileWidth = 190;

/// Responsive grid delegate shared by the Sale + Receive result grids.
///
/// Column count is derived from the available width (`maxCrossAxisExtent`);
/// the tile height scales with `MediaQuery.textScaler` (clamped so a huge
/// accessibility font doesn't make each tile fill the screen).
SliverGridDelegate itemGridDelegate(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: _kMaxTileWidth,
    crossAxisSpacing: 8,
    mainAxisSpacing: 8,
    mainAxisExtent: _kBaseTileExtent * scale,
  );
}
