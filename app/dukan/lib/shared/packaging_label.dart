// Mirror of the server's `_format_conversion` SQL helper so the Flutter
// side can derive "25 Kg Bag" / "Kg" labels before the row exists in the
// database (e.g., during the Add packaging / Add new item draft state).
//
// Keep this in sync with `public._format_conversion` (currently in
// 0011_catalog_activation.sql). Server is the source of truth — this is
// the offline echo for previews.

String packagingLabel(num conversion, String baseLabel, String unitLabel) {
  if (conversion == 1) return unitLabel;
  final pretty = conversion == conversion.roundToDouble()
      ? conversion.toInt().toString()
      : conversion.toString();
  return '$pretty $baseLabel $unitLabel';
}
