// Multi-scan viewfinder for Receive. Stays open across scans —
// the cashier rips through a 20-line bono by pulling the trigger
// or holding the camera over each barcode in turn. Successful
// decodes auto-stage a quantity-1 line; same-code re-scans within
// the 800ms re-arm window are ignored (handles mobile_scanner's
// multi-fire-per-trigger), beyond that increment the staged
// quantity. Unknown codes are queued for review on close.
//
// The sheet is self-contained — it takes a code resolver function
// (typically wired to Receive's searchItems path) and returns the
// aggregated MultiScanResult on close. Receive applies the result
// to its ReceiveController.
//
// Phase 2B (this file): camera-driven multi-scan. HID multi-scan
// is implicit — once the cashier opens this sheet, every HID burst
// also lands here as long as the listener emits to the same callback.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/scanner/scan_event.dart';
import 'package:dukan/scanner/scanner_feedback.dart';
import 'package:dukan/scanner/scanner_sheet.dart' show kDefaultScannerFormats;
import 'package:dukan/shared/l10n.dart';

/// One staged line ready to write into ReceiveController.
class StagedScanLine {
  StagedScanLine({
    required this.shopItemId,
    required this.shopItemUnitId,
    required this.itemId,
    required this.displayName,
    required this.packagingLabel,
    required this.baseUnitLabel,
    required this.quantity,
    required this.perUnitCost,
  });

  final String shopItemId;
  final String shopItemUnitId;
  final String? itemId;
  final String displayName;
  final String packagingLabel;
  final String baseUnitLabel;
  num quantity;

  /// Per-unit last-cost snapshot for the matched packaging. May be
  /// null when the supplier has never delivered this item before;
  /// the cashier fills it in after closing the sheet.
  final num? perUnitCost;

  num get lineTotal => perUnitCost == null ? 0 : perUnitCost! * quantity;
}

/// What the sheet returns when the cashier closes it.
class MultiScanResult {
  const MultiScanResult({
    required this.stagedLines,
    required this.unknownCodes,
  });

  final List<StagedScanLine> stagedLines;
  final List<String> unknownCodes;
}

/// Look up a scanned code. The caller wires this to `searchItems`
/// or any equivalent path. Returning null signals "unknown — queue
/// for review."
typedef MultiScanResolver = Future<ItemSearchResult?> Function(String code);

typedef MultiScanOpener = Future<MultiScanResult?> Function(
  BuildContext context, {
  required MultiScanResolver resolver,
});

/// Static entry point + test override. Same pattern as Scanner.
class MultiScan {
  MultiScan._();

  static MultiScanOpener _opener = _defaultOpen;

  static Future<MultiScanResult?> open(
    BuildContext context, {
    required MultiScanResolver resolver,
  }) =>
      _opener(context, resolver: resolver);

  static VoidCallback overrideOpener(MultiScanOpener opener) {
    final prior = _opener;
    _opener = opener;
    return () => _opener = prior;
  }

  static Future<MultiScanResult?> _defaultOpen(
    BuildContext context, {
    required MultiScanResolver resolver,
  }) {
    return Navigator.of(context).push<MultiScanResult>(
      MaterialPageRoute<MultiScanResult>(
        fullscreenDialog: true,
        builder: (_) => MultiScanSheet(resolver: resolver),
      ),
    );
  }
}

class MultiScanSheet extends StatefulWidget {
  const MultiScanSheet({required this.resolver, super.key});

  final MultiScanResolver resolver;

  @override
  State<MultiScanSheet> createState() => _MultiScanSheetState();
}

class _MultiScanSheetState extends State<MultiScanSheet> {
  late final MobileScannerController _controller;
  final Map<String, StagedScanLine> _staged = <String, StagedScanLine>{};
  final List<StagedScanLine> _stagedOrder = <StagedScanLine>[];
  final List<String> _unknown = <String>[];
  bool _torchOn = false;
  bool _flashGreen = false;
  String? _lastCode;
  DateTime _lastCodeAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(formats: kDefaultScannerFormats);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_resolving) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;

    final now = DateTime.now();
    final isSameCodeReFire = code == _lastCode &&
        now.difference(_lastCodeAt).inMilliseconds < 800;
    if (isSameCodeReFire) return; // dedupe mobile_scanner re-fires
    _lastCode = code;
    _lastCodeAt = now;

    // Bump count on already-staged items without hitting the network.
    final existing = _staged[code];
    if (existing != null) {
      setState(() {
        existing.quantity = existing.quantity + 1;
        _flashGreen = true;
      });
      ScannerFeedback.duplicate();
      _resetFlash();
      return;
    }

    _resolving = true;
    try {
      final match = await widget.resolver(code);
      if (!mounted) return;
      if (match == null ||
          match.shopItemId == null ||
          match.defaultShopItemUnitId == null) {
        setState(() {
          if (!_unknown.contains(code)) _unknown.add(code);
        });
        ScannerFeedback.unknownInMultiScan();
        return;
      }
      final line = StagedScanLine(
        shopItemId: match.shopItemId!,
        shopItemUnitId: match.defaultShopItemUnitId!,
        itemId: match.itemId,
        displayName: match.displayName,
        packagingLabel: match.packagingLabel ??
            match.defaultUnitLabel ??
            match.baseUnitLabel,
        baseUnitLabel: match.baseUnitLabel,
        quantity: 1,
        perUnitCost: match.defaultUnitLastCost,
      );
      // Key by the *scanned code* so re-scanning the same physical
      // package always finds the same staged line, even if two
      // distinct codes happen to resolve to the same shop_item_unit.
      setState(() {
        _staged[code] = line;
        _stagedOrder.add(line);
        _flashGreen = true;
      });
      ScannerFeedback.success();
      _resetFlash();
    } finally {
      _resolving = false;
    }
  }

  void _resetFlash() {
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _flashGreen = false);
    });
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) return;
    setState(() => _torchOn = !_torchOn);
  }

  void _close() {
    Navigator.of(context).pop(
      MultiScanResult(
        stagedLines: List<StagedScanLine>.unmodifiable(_stagedOrder),
        unknownCodes: List<String>.unmodifiable(_unknown),
      ),
    );
  }

  /// Visible-for-testing — drives the scan handler directly so tests
  /// don't need a real camera.
  Future<void> debugIngest(ScanEvent event) {
    return _onDetect(
      BarcodeCapture(
        barcodes: [
          Barcode(
            rawValue: event.code,
            format: BarcodeFormat.unknown,
          ),
        ],
      ),
    );
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
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
        title: Text(
          l.multiScanSheetTitle(_stagedOrder.length),
        ),
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
      body: Column(
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 260,
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _flashGreen
                            ? Colors.greenAccent
                            : Colors.white70,
                        width: _flashGreen ? 4 : 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_unknown.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              color: Colors.amber.shade100,
              child: Text(
                l.multiScanUnknownCount(_unknown.length),
              ),
            ),
          Expanded(
            child: Container(
              color: Colors.white,
              child: _stagedOrder.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l.multiScanEmptyHint,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: _stagedOrder.length,
                      itemBuilder: (_, i) {
                        final line = _stagedOrder[i];
                        return ListTile(
                          dense: true,
                          title: Text(line.displayName),
                          subtitle: Text(line.packagingLabel),
                          trailing: Text(
                            '× ${line.quantity}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium,
                          ),
                        );
                      },
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _close,
                  child: Text(l.multiScanDoneAction),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
