// Thin wrapper around `package:image_picker` so the Receive screen
// can call it without importing the package directly. Lets tests
// substitute a fake picker that returns pre-canned bytes + a mime
// type without touching platform channels.

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

/// Picker contract — production wires `ImagePicker`, tests inject a
/// pre-built `PickedBono` (or null for "cancelled").
abstract class BonoImagePicker {
  Future<PickedBono?> pickFromCamera();
  Future<PickedBono?> pickFromGallery();
}

class DefaultBonoImagePicker implements BonoImagePicker {
  DefaultBonoImagePicker() : _picker = ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedBono?> pickFromCamera() => _pick(ImageSource.camera);

  @override
  Future<PickedBono?> pickFromGallery() => _pick(ImageSource.gallery);

  Future<PickedBono?> _pick(ImageSource source) async {
    // Compress aggressively — bonos are A4 receipts, ~1080px wide is
    // enough for OCR + display. 8MB hard cap on `document.size_bytes`.
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1600,
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
