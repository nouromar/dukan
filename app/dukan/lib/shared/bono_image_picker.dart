// Thin wrapper around `package:image_picker`. Two flavours of caller:
//
//   * Bono (Receive) — uploaded for OCR. Needs enough resolution that
//     Cloud Vision can read prices reliably; lands ~150–300 KB.
//   * Shop item photo (onboarding form) — shown as a small thumbnail
//     in the Products list / detail. Storage + upload time matter more
//     than absolute sharpness; lands ~60–100 KB.
//
// Both go through the same `BonoImagePicker` contract; what differs is
// the `ImageQuality` config passed at construction. Tests inject a
// fake picker that returns pre-canned bytes + a mime type without
// touching platform channels.

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Picked bono image — bytes the screen will upload to Storage plus
/// the mime type the `create_bono_document` RPC expects on
/// `public.document.mime_type` (jpeg / png / webp).
class PickedBono {
  const PickedBono({
    required this.bytes,
    required this.mimeType,
    required this.fileExtension,
  });

  final Uint8List bytes;
  final String mimeType;
  /// File-name suffix the storage key should land with (e.g. "jpg").
  final String fileExtension;
}

/// Compression preset for [DefaultBonoImagePicker]. The `bono` preset
/// is tuned for OCR (~1600 px / quality 70). The `shopItem` preset is
/// tuned for a thumbnail (~800 px / quality 65) — the photo only has
/// to identify the product visually; storage cost scales by every
/// item every shop adds.
class ImageQuality {
  const ImageQuality({required this.maxWidth, required this.quality});

  final int maxWidth;
  final int quality;

  /// Bono / receipt OCR. Cloud Vision wants ≥1200 px on the long edge
  /// to read prices reliably; 1600 leaves headroom. Quality 70 keeps
  /// JPEG artifacts off of digit edges.
  static const bono = ImageQuality(maxWidth: 1600, quality: 70);

  /// Shop-item thumbnail. Half the resolution, slightly tighter
  /// quality — final files ~60–100 KB. Plenty for a list thumbnail
  /// or the detail-screen header.
  static const shopItem = ImageQuality(maxWidth: 800, quality: 65);
}

/// Picker contract — production wires `ImagePicker`, tests inject a
/// pre-built `PickedBono` (or null for "cancelled").
abstract class BonoImagePicker {
  Future<PickedBono?> pickFromCamera();
  Future<PickedBono?> pickFromGallery();
}

class DefaultBonoImagePicker implements BonoImagePicker {
  /// Default config is [ImageQuality.bono] — Receive's bono upload
  /// path. Pass [ImageQuality.shopItem] from the shop-item editor.
  DefaultBonoImagePicker({this.quality = ImageQuality.bono})
      : _picker = ImagePicker();

  final ImagePicker _picker;
  final ImageQuality quality;

  @override
  Future<PickedBono?> pickFromCamera() => _pick(ImageSource.camera);

  @override
  Future<PickedBono?> pickFromGallery() => _pick(ImageSource.gallery);

  Future<PickedBono?> _pick(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: quality.quality,
      maxWidth: quality.maxWidth.toDouble(),
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final mime = _mimeFromName(picked.name);
    final ext = mime == 'image/png'
        ? 'png'
        : mime == 'image/webp'
            ? 'webp'
            : 'jpg';
    return PickedBono(bytes: bytes, mimeType: mime, fileExtension: ext);
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
