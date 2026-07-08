// Full-screen, pinch-to-zoom view of an attached bono photo, loaded from a
// short-lived signed Storage URL (ShopApi.signBonoUrl). Opened from the receive
// detail so the shopkeeper can pull up the original supplier invoice later —
// e.g. to read a handwritten price or settle a dispute.

import 'package:flutter/material.dart';

import 'package:dukan/shared/l10n.dart';

class BonoPhotoView extends StatelessWidget {
  const BonoPhotoView({super.key, required this.imageProvider});

  /// A `FileImage` (offline cache) or `NetworkImage` (signed Storage URL).
  final ImageProvider imageProvider;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l.receiveDetailViewBonoTitle),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image(
            image: imageProvider,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
            errorBuilder: (context, error, stack) => Center(
              child: Text(
                l.receiveDetailBonoUnavailable,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
