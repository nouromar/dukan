// Display-time normalization for item / party names. The shopkeeper's
// typing style varies — "bariis", "Bar Soap", "CAANO" — and the
// catalog seed mixes locales (Somali entries often arrive lowercased).
// Render layers in Sale / Receive / history call this so the UI looks
// consistent without forcing the underlying data into one shape.
//
// Rule: uppercase the first character of the first word. Leaves later
// words alone so "iPhone" / "USB" / acronyms survive. Whitespace-trim
// + null-safe.

String displayName(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trimLeft();
  if (trimmed.isEmpty) return '';
  final first = trimmed[0].toUpperCase();
  return '$first${trimmed.substring(1)}';
}
