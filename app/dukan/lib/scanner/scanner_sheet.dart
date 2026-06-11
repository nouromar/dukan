// Full-screen camera viewfinder for one-off ("single-scan") barcode
// capture. Tapping the camera icon in a search bar opens this; the
// first successful decode plays a haptic, briefly flashes the reticle
// green, and pops with the ScanEvent. The caller hands the event to
// search_items and routes per docs/scanner.md §4.
//
// Multi-scan mode (Receive screen) lives in a future Phase 2 sheet
// — this file is single-scan only.
//
// Tests can substitute the camera path via Scanner.overrideOpener so
// the Sale screen's tap-to-scan flow is exercisable without a real
// camera or ML Kit binary.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:dukan/scanner/scan_event.dart';
import 'package:dukan/scanner/scanner_feedback.dart';
import 'package:dukan/shared/l10n.dart';

/// V1 default symbologies. Mirrors docs/scanner.md §6.
const List<BarcodeFormat> kDefaultScannerFormats = <BarcodeFormat>[
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
];

typedef ScannerSheetOpener = Future<ScanEvent?> Function(BuildContext context);

/// Static entry point for "open the single-scan viewfinder." Tests
/// can replace the default opener with [overrideOpener] so widget
/// tests can simulate scans without spinning up a camera.
class Scanner {
  Scanner._();

  static ScannerSheetOpener _opener = _defaultOpen;

  static Future<ScanEvent?> open(BuildContext context) => _opener(context);

  /// Replace the default `Navigator.push -> MobileScanner` path with
  /// a test stub. Returns a disposer that restores the prior opener.
  static VoidCallback overrideOpener(ScannerSheetOpener opener) {
    final prior = _opener;
    _opener = opener;
    return () => _opener = prior;
  }

  static Future<ScanEvent?> _defaultOpen(BuildContext context) {
    return Navigator.of(context).push<ScanEvent>(
      MaterialPageRoute<ScanEvent>(
        fullscreenDialog: true,
        builder: (_) => const ScannerSheet(),
      ),
    );
  }
}

class ScannerSheet extends StatefulWidget {
  const ScannerSheet({super.key});

  @override
  State<ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<ScannerSheet> {
  late final MobileScannerController _controller;
  bool _decoded = false;
  bool _torchOn = false;
  bool _showHint = false;
  Timer? _hintTimer;
  bool _flashGreen = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(formats: kDefaultScannerFormats);
    // After 3s with no decode, surface a "hold steady" hint per
    // docs/scanner.md §9.5. Disappears on first decoded payload.
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _decoded) return;
      setState(() => _showHint = true);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_decoded) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;
    final format = capture.barcodes.first.format;
    _decoded = true;
    ScannerFeedback.success();
    setState(() => _flashGreen = true);
    // Brief green confirmation before popping. Keeps the cashier from
    // wondering whether the scan landed.
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      Navigator.of(context).pop(
        ScanEvent(
          code: code,
          source: ScanSource.camera,
          symbology: format.name,
        ),
      );
    });
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) return;
    setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(l.scannerSheetTitle),
        actions: [
          IconButton(
            tooltip: l.scannerTorchTooltip,
            icon: Icon(
              _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
            ),
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Reticle — a centred rectangle with a glowing border. Flashes
          // green for 250ms on successful decode (see _onDetect).
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 280,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _flashGreen ? Colors.greenAccent : Colors.white70,
                  width: _flashGreen ? 4 : 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Hint surfaces after 3s with no decode.
          if (_showHint && !_decoded)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l.scannerHoldSteady,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
