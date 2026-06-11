// A single scanned-barcode event. Source-agnostic — the same shape
// describes a camera viewfinder hit, a Bluetooth HID burst, or a
// future BLE scanner — so the downstream search_items / cart-add
// logic doesn't care how the code arrived.

/// Where the scan came from. Used by telemetry and feedback policy
/// (camera scans get the green-frame flash; HID scans don't have a
/// viewfinder to flash).
enum ScanSource { camera, hid }

class ScanEvent {
  const ScanEvent({
    required this.code,
    required this.source,
    this.symbology,
  });

  /// The decoded payload as a string. We never strip leading zeros or
  /// normalise the format — `search_items` does any matching shape on
  /// the server side.
  final String code;

  final ScanSource source;

  /// Optional symbology name (e.g. `ean13`, `code128`). Used for
  /// telemetry only; the search index doesn't care.
  final String? symbology;

  @override
  String toString() =>
      'ScanEvent(code: $code, source: ${source.name}, symbology: $symbology)';

  @override
  bool operator ==(Object other) =>
      other is ScanEvent &&
      other.code == code &&
      other.source == source &&
      other.symbology == symbology;

  @override
  int get hashCode => Object.hash(code, source, symbology);
}
