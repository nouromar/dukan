// Full-screen bono review — the AI-prefilled, accept-or-edit surface that
// replaces the old read-only BonoSuggestionReviewSheet.
//
// Each OCR'd line is a card in one of two states:
//   * GREEN / Ready       — a high-confidence match, cashier-confirmed. Its
//                           category + packaging are the item's REAL data.
//   * AMBER / Needs review — a low/verify match or a NEW item. The AI proposes
//                           the category + packaging (from the suggest RPC).
//
// "Ready" means cashier-confirmed, not "matched" — so Accept can require every
// line green (or removed) and still always be reachable: a new-item line turns
// green by Pick existing (bind to a real item) or Mark ready (create it via the
// new-item sheet, prefilled with the AI category). Accept commits the ready
// lines to the receive (via BonoApplyLine) and closes. See
// docs/bono-ocr-prepopulate.md and .claude/plans/we-want-create-app-happy-toast.md.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/products/item_creator.dart';
import 'package:dukan/receive/add_new_item_sheet.dart';
import 'package:dukan/receive/bono_bind_item_sheet.dart';
import 'package:dukan/receive/bono_suggestion_review_sheet.dart' show BonoApplyLine;
import 'package:dukan/receive/unit_picker_sheet.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/packaging_label.dart';
import 'package:dukan/shared/quantity_chips.dart';

/// Push the full-screen review and resolve with the lines the cashier accepted
/// (or null if they backed out). Same return contract as the old sheet, so the
/// caller's merge + learning loop is unchanged.
Future<List<BonoApplyLine>?> openBonoReview(
  BuildContext context, {
  required List<BonoSuggestion> suggestions,
  required ShopSummary shop,
  String? supplierPartyId,
  VoidCallback? onViewPhoto,
}) {
  return Navigator.of(context).push<List<BonoApplyLine>>(
    MaterialPageRoute(
      builder: (_) => BonoReviewScreen(
        suggestions: suggestions,
        shop: shop,
        supplierPartyId: supplierPartyId,
        onViewPhoto: onViewPhoto,
      ),
    ),
  );
}

class BonoReviewScreen extends StatefulWidget {
  const BonoReviewScreen({
    super.key,
    required this.suggestions,
    required this.shop,
    this.supplierPartyId,
    this.onViewPhoto,
  });

  final List<BonoSuggestion> suggestions;
  final ShopSummary shop;
  final String? supplierPartyId;
  final VoidCallback? onViewPhoto;

  @override
  State<BonoReviewScreen> createState() => _BonoReviewScreenState();
}

class _BonoReviewScreenState extends State<BonoReviewScreen> {
  late final List<_Line> _lines =
      widget.suggestions.map(_Line.fromSuggestion).toList();

  // Unit code → display label, for synthesizing packaging labels when
  // materializing the AI's detected pack (Create / Add packaging). Falls back
  // to raw codes until it loads; the create/add paths work either way.
  Map<String, String> _unitLabels = {};

  Iterable<_Line> get _active => _lines.where((l) => !l.removed);

  @override
  void initState() {
    super.initState();
    _loadUnitLabels();
  }

  Future<void> _loadUnitLabels() async {
    try {
      final units = await context.read<ShopApi>().listUnits();
      if (!mounted) return;
      setState(() {
        _unitLabels = {for (final u in units) u.code: u.label};
      });
    } catch (_) {
      // Raw codes are an acceptable fallback for the label synthesis.
    }
  }

  String _labelFor(String? code) =>
      code == null ? '' : (_unitLabels[code] ?? code);

  // The packaging the AI wants us to materialize (new item pack, or the new
  // size to add to a matched item), rendered as "Carton (12 pcs)".
  String _newPackLabel(_Line line) {
    if (line.packSize == null || line.packUnitCode == null) return '';
    return packagingLabel(
      line.packSize!,
      _labelFor(line.baseUnitCode),
      _labelFor(line.packUnitCode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final active = _active.toList();
    final needCount = active.where((l) => !l.ready).length;
    final readyCount = active.where((l) => l.ready).length;
    final canAccept = active.isNotEmpty && needCount == 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.bonoReviewTitle),
      ),
      body: Column(
        children: [
          // Summary strip: how many are done vs need you.
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _Dot(color: _green(theme)),
                const SizedBox(width: 6),
                Text(l.bonoReviewReady(readyCount)),
                const SizedBox(width: 16),
                _Dot(color: _amber(theme)),
                const SizedBox(width: 6),
                Text(l.bonoReviewNeedsReview(needCount)),
              ],
            ),
          ),
          Expanded(
            child: active.isEmpty
                ? Center(child: Text(l.bonoSuggestionsUnmatchedSection))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96, top: 4),
                    itemCount: active.length,
                    itemBuilder: (context, i) => _card(active[i]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: canAccept ? _accept : null,
              child: Text(canAccept
                  ? l.bonoReviewAccept(readyCount)
                  : l.bonoReviewAcceptGate(needCount, active.length)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(_Line line) {
    final l = tr(context);
    final theme = Theme.of(context);
    final accent = line.ready ? _green(theme) : _amber(theme);
    final categoryName = line.categoryName ?? l.bonoReviewUncategorized;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: accent),
            Expanded(
              child: InkWell(
                onTap: () => _editLine(line),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Each element gets its own full-width line so long
                      // real-world names + categories never squeeze each other
                      // (a phone can't fit status chip + name + category on one
                      // row). Status chip (▾ menu) first, then name, then the
                      // category chip.
                      _statusMenu(line),
                      const SizedBox(height: 8),
                      Text(
                        line.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _CategoryChip(
                          label: categoryName,
                          ai: line.isNew,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Packaging · qty · price · total.
                      Text(
                        _detailLine(line),
                        style: theme.textTheme.bodyMedium,
                      ),
                      // Raw bono text — only when it differs from the name
                      // (for a new item the name IS the raw text, so it'd dupe).
                      if (line.rawText.isNotEmpty &&
                          line.rawText != line.displayName) ...[
                        const SizedBox(height: 2),
                        Text(
                          '“${line.rawText}”',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (!line.ready) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: _primaryAction(line),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Per-case primary CTA: new item → Create; matched item with a new pack →
  // Add packaging (materialize the AI's size); otherwise a plain confirm.
  Widget _primaryAction(_Line line) {
    final l = tr(context);
    if (line.isNew) {
      return FilledButton.tonalIcon(
        onPressed: () => _createNewItem(line),
        icon: const Icon(Icons.add, size: 18),
        label: Text(
          l.bonoReviewCreateItem(line.displayName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (line.newPackaging) {
      return FilledButton.tonalIcon(
        onPressed: () => _addNewPackaging(line),
        icon: const Icon(Icons.add_box_outlined, size: 18),
        label: Text(
          l.bonoReviewAddPackaging(_newPackLabel(line)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: () => _markReady(line),
      icon: const Icon(Icons.check, size: 18),
      label: Text(l.bonoReviewMarkReady),
    );
  }

  String _detailLine(_Line line) {
    // For a new-size line, show the pack we'll add — more useful than the
    // fallback binding it currently resolves to.
    final labelText =
        line.newPackaging ? _newPackLabel(line) : line.packagingLabel;
    final pkg = labelText.isNotEmpty ? labelText : '—';
    final qty = '× ${_fmtQty(line.quantity)}';
    final total = line.lineTotal != null
        ? ' · ${formatMoney(line.lineTotal!, widget.shop)}'
        : '';
    return '$pkg   $qty$total';
  }

  Widget _statusMenu(_Line line) {
    final l = tr(context);
    final theme = Theme.of(context);
    final ready = line.ready;
    final color = ready ? _green(theme) : _amber(theme);
    final label = ready
        ? l.bonoReviewStatusReady
        : line.isNew
            ? l.bonoReviewStatusNewItem
            : line.newPackaging
                ? l.bonoReviewStatusNewSize
                : l.bonoReviewStatusNeedsReview;
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: (v) => _onMenu(line, v),
      itemBuilder: (context) => [
        if (line.isNew) ...[
          PopupMenuItem(value: 'pick', child: Text(l.bonoReviewPickExisting)),
          PopupMenuItem(value: 'edit_new', child: Text(l.bonoReviewEditNew)),
        ] else ...[
          PopupMenuItem(value: 'change', child: Text(l.bonoReviewChangeItem)),
          if (line.newPackaging)
            PopupMenuItem(
                value: 'keep_pack', child: Text(l.bonoReviewKeepPackaging)),
        ],
        if (widget.onViewPhoto != null)
          PopupMenuItem(value: 'photo', child: Text(l.bonoReviewViewPhoto)),
        if (ready)
          PopupMenuItem(value: 'flag', child: Text(l.bonoReviewFlag)),
        PopupMenuItem(value: 'remove', child: Text(l.bonoReviewRemove)),
      ],
      child: Chip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: color.withValues(alpha: 0.16),
        side: BorderSide(color: color),
        avatar: Icon(ready ? Icons.check_circle : Icons.error_outline,
            size: 16, color: color),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            Icon(Icons.arrow_drop_down, size: 18, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenu(_Line line, String action) async {
    switch (action) {
      case 'pick':
      case 'change':
        await _pickExisting(line);
      case 'edit_new':
        await _editNewInSheet(line);
      case 'keep_pack':
        // Bind to the existing pack the matcher resolved; don't add the size.
        setState(() {
          line.newPackaging = false;
          line.ready = true;
        });
      case 'photo':
        widget.onViewPhoto?.call();
      case 'flag':
        setState(() => line.ready = false);
      case 'remove':
        setState(() => line.removed = true);
    }
  }

  // Tap the card body → edit. Matched lines open the light edit sheet; new
  // lines open the full new-item sheet (base-only override of one-tap Create).
  Future<void> _editLine(_Line line) async {
    if (line.isNew) {
      await _editNewInSheet(line);
      return;
    }
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditLineSheet(line: line, shop: widget.shop),
    );
    if (result == null || !mounted) return;
    setState(() {
      line.quantity = result.quantity;
      line.lineTotal = result.lineTotal;
      if (result.shopItemUnitId != null) {
        line.shopItemUnitId = result.shopItemUnitId;
        line.packagingLabel = result.packagingLabel ?? line.packagingLabel;
        line.baseUnitLabel = result.baseUnitLabel ?? line.baseUnitLabel;
      }
    });
  }

  Future<void> _markReady(_Line line) async {
    // A verify/low match that already resolves to a real item + packaging:
    // confirming is the whole gesture. (New items / new sizes route to their
    // own one-tap actions; this stays a plain confirm.)
    setState(() => line.ready = true);
  }

  // One-tap Create: materialize the AI's item AND its detected pack in a single
  // create_shop_item call (base = small unit, received pack = default-receive).
  // No sheet — the full editor is still reachable via "Edit before creating".
  Future<void> _createNewItem(_Line line) async {
    final l = tr(context);
    final baseCode = line.baseUnitCode;
    if (baseCode == null) {
      // OCR gave no base unit to build on — fall back to the full sheet.
      await _editNewInSheet(line);
      return;
    }
    final hasPack = line.packUnitCode != null &&
        line.packSize != null &&
        line.packSize! > 1;
    final result = await createShopItemDraft(
      context,
      shop: widget.shop,
      name: line.displayName,
      categoryId: line.suggestedCategoryId,
      baseUnitCode: baseCode,
      baseUnitLabel: _labelFor(baseCode),
      soldUnitCode: hasPack ? line.packUnitCode : null,
      soldUnitLabel: hasPack ? _labelFor(line.packUnitCode) : null,
      soldConversion: hasPack ? line.packSize : null,
      languageCode: Localizations.localeOf(context).languageCode,
      defaultSide: 'receive',
      errorMessage: l.addNewItemFailedMessage,
    );
    if (result == null || !mounted) return;
    setState(() {
      line.shopItemId = result.shopItemId;
      line.shopItemUnitId = result.shopItemUnitId;
      line.itemId = null; // shop-local new item
      line.displayName = result.displayName;
      line.packagingLabel = result.packagingLabel;
      line.baseUnitLabel = result.baseUnitLabel;
      line.newPackaging = false;
      line.learnConfidence = 1; // explicit cashier creation
      line.ready = true;
    });
  }

  // Full new-item sheet — the base-only override of one-tap Create (and the
  // fallback when OCR gave no base unit).
  Future<void> _editNewInSheet(_Line line) async {
    final result = await AddNewItemSheet.show(
      context,
      widget.shop,
      initialName: line.displayName,
      initialCategoryId: line.suggestedCategoryId,
      initialBaseUnitCode: line.baseUnitCode,
      initialPackUnitCode: line.packUnitCode,
      initialPackSize: line.packSize,
    );
    if (result == null || !mounted) return;
    setState(() {
      line.shopItemId = result.shopItemId;
      line.shopItemUnitId = result.shopItemUnitId;
      line.itemId = null; // shop-local new item
      line.displayName = result.displayName;
      line.packagingLabel = result.packagingLabel;
      line.baseUnitLabel = result.baseUnitLabel;
      line.newPackaging = false;
      line.learnConfidence = 1; // explicit cashier creation
      line.ready = true;
    });
  }

  // One-tap Add packaging: add the AI's detected size to the matched item and
  // rebind the line to it (as a NON-default unit; the learned alias resolves
  // future bonos to it).
  Future<void> _addNewPackaging(_Line line) async {
    final l = tr(context);
    final packCode = line.packUnitCode;
    final size = line.packSize;
    if (line.shopItemId == null || packCode == null || size == null) return;
    final added = await addShopItemUnitDraft(
      context,
      shop: widget.shop,
      shopItemId: line.shopItemId!,
      unitCode: packCode,
      unitLabel: _labelFor(packCode),
      baseUnitLabel: _labelFor(line.baseUnitCode),
      conversionToBase: size,
      errorMessage: l.addNewItemFailedMessage,
    );
    if (added == null || !mounted) return;
    setState(() {
      line.shopItemUnitId = added.shopItemUnitId;
      line.packagingLabel = added.packagingLabel;
      line.newPackaging = false;
      line.learnConfidence = 1; // explicit cashier add
      line.ready = true;
    });
  }

  Future<void> _pickExisting(_Line line) async {
    final target = await showBonoBindItemPicker(
      context,
      shop: widget.shop,
      supplierPartyId: widget.supplierPartyId,
      initialQuery: line.rawText,
    );
    if (target == null || !mounted) return;
    setState(() {
      line.shopItemId = target.shopItemId;
      line.shopItemUnitId = target.shopItemUnitId;
      line.itemId = target.itemId;
      line.displayName = target.displayName;
      line.packagingLabel = target.packagingLabel;
      line.baseUnitLabel = target.baseUnitLabel;
      line.learnConfidence = 1; // explicit cashier binding
      line.ready = true;
    });
  }

  void _accept() {
    final out = <BonoApplyLine>[];
    for (final line in _active) {
      if (line.shopItemId == null || line.shopItemUnitId == null) continue;
      out.add(BonoApplyLine(
        shopItemId: line.shopItemId!,
        shopItemUnitId: line.shopItemUnitId!,
        itemId: line.itemId,
        displayName: line.displayName,
        packagingLabel: line.packagingLabel,
        baseUnitLabel: line.baseUnitLabel,
        quantity: line.quantity,
        lineTotal: line.lineTotal ?? 0,
        rawText: line.rawText,
        learnConfidence: line.learnConfidence,
      ));
    }
    Navigator.of(context).pop(out);
  }

  Color _green(ThemeData t) => const Color(0xFF2E7D32);
  Color _amber(ThemeData t) => const Color(0xFFE65100);
  String _fmtQty(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
}

/// Mutable per-line draft the review screen edits in place.
class _Line {
  _Line({
    required this.rawText,
    required this.shopItemId,
    required this.shopItemUnitId,
    required this.itemId,
    required this.displayName,
    required this.categoryName,
    required this.suggestedCategoryId,
    required this.packagingLabel,
    required this.baseUnitLabel,
    required this.baseUnitCode,
    required this.packUnitCode,
    required this.packSize,
    required this.quantity,
    required this.lineTotal,
    required this.ready,
    required this.learnConfidence,
    this.newPackaging = false,
  });

  factory _Line.fromSuggestion(BonoSuggestion s) {
    final total = s.lineTotal ??
        (s.unitPrice != null ? s.unitPrice! * s.quantity : null);
    if (s.isBound) {
      // A matched line whose OCR pack is NEW to the item (0114) carries the
      // AI pack to add and can't be "Ready" until the cashier resolves it
      // (Add packaging, or Keep current packaging) — regardless of match
      // confidence, because the resolved fallback unit is the wrong size.
      final newPack = s.newPackaging &&
          s.suggestedPackUnitCode != null &&
          s.suggestedPackSize != null;
      return _Line(
        rawText: s.rawText,
        shopItemId: s.suggestedShopItemId,
        shopItemUnitId: s.suggestedShopItemUnitId,
        itemId: s.itemId,
        displayName: s.displayName ?? s.rawText,
        categoryName: s.suggestedCategoryName,
        suggestedCategoryId: s.suggestedCategoryId,
        packagingLabel: s.unitCode ?? s.baseUnitCode ?? '',
        baseUnitLabel: s.baseUnitCode ?? '',
        baseUnitCode: s.baseUnitCode,
        packUnitCode: newPack ? s.suggestedPackUnitCode : null,
        packSize: newPack ? s.suggestedPackSize : null,
        newPackaging: newPack,
        quantity: s.quantity,
        lineTotal: total,
        ready: s.confidence == 'high' && !newPack,
        learnConfidence: s.confidence == 'high' ? 0.9 : 0.6,
      );
    }
    // Unmatched / new item — AI proposal, snapped server-side.
    return _Line(
      rawText: s.rawText,
      shopItemId: null,
      shopItemUnitId: null,
      itemId: null,
      displayName: s.rawText,
      categoryName: s.suggestedCategoryName,
      suggestedCategoryId: s.suggestedCategoryId,
      packagingLabel: s.suggestedPackUnitCode ?? s.suggestedBaseUnitCode ?? '',
      baseUnitLabel: s.suggestedBaseUnitCode ?? '',
      baseUnitCode: s.suggestedBaseUnitCode,
      packUnitCode: s.suggestedPackUnitCode,
      packSize: s.suggestedPackSize,
      quantity: s.quantity,
      lineTotal: total,
      ready: false,
      learnConfidence: 1,
    );
  }

  final String rawText;
  String? shopItemId;
  String? shopItemUnitId;
  String? itemId;
  String displayName;
  String? categoryName;
  final String? suggestedCategoryId;
  String packagingLabel;
  String baseUnitLabel;
  final String? baseUnitCode;
  final String? packUnitCode;
  final double? packSize;
  double quantity;
  double? lineTotal;
  bool ready;
  bool removed = false;
  double learnConfidence;
  // Matched line whose OCR pack is new to the item — flips false once the
  // cashier adds the packaging or keeps the existing binding.
  bool newPackaging;

  bool get isNew => shopItemId == null;
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.ai});
  final String label;
  final bool ai;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        ai ? '$label · ${tr(context).bonoReviewNewItem}' : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

/// Result of the Edit-line sheet for a MATCHED line.
class _EditResult {
  const _EditResult({
    required this.quantity,
    required this.lineTotal,
    this.shopItemUnitId,
    this.packagingLabel,
    this.baseUnitLabel,
  });
  final double quantity;
  final double? lineTotal;
  final String? shopItemUnitId;
  final String? packagingLabel;
  final String? baseUnitLabel;
}

/// One editing surface for a matched line: quantity, packaging, total. Reuses
/// the OS numpad + QuantityChips + the existing unit picker.
class _EditLineSheet extends StatefulWidget {
  const _EditLineSheet({required this.line, required this.shop});
  final _Line line;
  final ShopSummary shop;

  @override
  State<_EditLineSheet> createState() => _EditLineSheetState();
}

class _EditLineSheetState extends State<_EditLineSheet> {
  late final TextEditingController _qty =
      TextEditingController(text: _fmt(widget.line.quantity));
  late final TextEditingController _total = TextEditingController(
      text: widget.line.lineTotal != null ? _fmt(widget.line.lineTotal!) : '');

  String? _unitId;
  String? _pkgLabel;
  String? _baseLabel;

  @override
  void dispose() {
    _qty.dispose();
    _total.dispose();
    super.dispose();
  }

  double get _q => double.tryParse(_qty.text.trim()) ?? widget.line.quantity;
  double? get _t {
    final raw = _total.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _changePackaging() async {
    final line = widget.line;
    final picked = await showUnitPicker(
      context,
      shopId: widget.shop.id,
      shopItemId: line.shopItemId!,
      screen: 'receive',
      baseUnitCode: line.baseUnitCode,
      baseUnitLabel: line.baseUnitLabel,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _unitId = picked.shopItemUnitId;
      _pkgLabel = picked.packagingLabel;
      _baseLabel = picked.packagingLabel;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final line = widget.line;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final pkgLabel = _pkgLabel ??
        (line.packagingLabel.isNotEmpty
            ? line.packagingLabel
            : l.bonoReviewPickPackaging);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.bonoReviewEditTitle,
                      style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(line.displayName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            // Packaging
            InkWell(
              onTap: line.shopItemId == null ? null : _changePackaging,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l.bonoReviewEditPackaging,
                  border: const OutlineInputBorder(),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(pkgLabel)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l.quantity,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            QuantityChips(
              onSelected: (v) =>
                  setState(() => _qty.text = _fmt(v.toDouble())),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _total,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l.bonoReviewEditTotal,
                prefixText: '${widget.shop.currencyCode} ',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_EditResult(
                  quantity: _q,
                  lineTotal: _t,
                  shopItemUnitId: _unitId,
                  packagingLabel: _pkgLabel,
                  baseUnitLabel: _baseLabel,
                )),
                child: Text(l.bonoReviewEditSave),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
}
