// Full-screen bono review — the AI-prefilled "glance and fix" surface.
//
// The OCR already matched, priced and packaged every line, so the shopkeeper's
// job is a binary per line: it LOOKS RIGHT → leave it, or it's WRONG → tap the
// card to fix it in one sheet. There are no per-line buttons, no status menu,
// and no gated Accept — just two glance cues:
//   * green ✓        — matched to a product you already have.
//   * amber "New …"  — a NEW product (unmatched) or a NEW pack (matched item,
//                      packaging it doesn't have yet). Auto-included, flagged.
//
// Nothing is written while reviewing. On Save, each line is materialized in the
// right way — matched → received as-is; new pack → the size is added; new
// product → the item is created with the AI's base + pack — then all lines are
// returned as BonoApplyLine for the receive to merge + learn. Errors are
// warnings (fix later via Void), never blockers. See docs/bono-ocr-prepopulate.md
// and .claude/plans/we-want-create-app-happy-toast.md.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/products/item_creator.dart';
import 'package:dukan/receive/bono_bind_item_sheet.dart';
import 'package:dukan/receive/bono_suggestion_review_sheet.dart' show BonoApplyLine;
import 'package:dukan/receive/unit_picker_sheet.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/packaging_label.dart';
import 'package:dukan/shared/quantity_chips.dart';
import 'package:dukan/sync/use_local_db.dart';

const Color _green = Color(0xFF2E7D32);
const Color _amber = Color(0xFFE65100);

String _fmtNum(double n) =>
    n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();

/// Push the full-screen review and resolve with the lines the cashier saved
/// (or null if they backed out). Same return contract as before, so the
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
  // materializing the AI's detected pack. Falls back to raw codes until loaded.
  Map<String, String> _unitLabels = {};
  // Shop categories for the edit sheet's new-item category dropdown.
  List<CategoryOption> _categories = const [];
  bool _loadedCategories = false;
  bool _saving = false;

  Iterable<_Line> get _active => _lines.where((l) => !l.removed);

  @override
  void initState() {
    super.initState();
    _loadUnitLabels();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedCategories) return;
    _loadedCategories = true;
    _loadCategories();
  }

  Future<void> _loadUnitLabels() async {
    try {
      final units = await context.read<ShopApi>().listUnits();
      if (!mounted) return;
      setState(() => _unitLabels = {for (final u in units) u.code: u.label});
    } catch (_) {
      // Raw codes are an acceptable fallback for the label synthesis.
    }
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await loadCategoryOptions(
        context,
        shopId: widget.shop.id,
        locale: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      setState(() => _categories = cats);
    } catch (_) {
      // Category is optional; the dropdown just shows "Uncategorized".
    }
  }

  String _labelFor(String? code) =>
      code == null ? '' : (_unitLabels[code] ?? code);

  // What the line will be received as: the AI's new pack for new-product /
  // new-pack lines, otherwise the matched item's real packaging.
  String _packLabelFor(_Line line) {
    if (line.packSize != null && line.packUnitCode != null) {
      return packagingLabel(
        line.packSize!,
        _labelFor(line.baseUnitCode),
        _labelFor(line.packUnitCode),
      );
    }
    return line.packagingLabel.isNotEmpty
        ? line.packagingLabel
        : _labelFor(line.baseUnitCode);
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final active = _active.toList();
    final newCount = active.where((x) => x.isNew || x.newPackaging).length;
    final newProducts = active.where((x) => x.isNew).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.bonoReviewTitle),
        actions: [
          if (widget.onViewPhoto != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: widget.onViewPhoto,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(l.bonoReviewPhoto),
              ),
            ),
        ],
      ),
      body: active.isEmpty
          ? Center(child: Text(l.bonoSuggestionsUnmatchedSection))
          : Column(
              children: [
                // Lead strip: how many lines, how many are new.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        l.bonoReviewLineCount(active.length),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (newCount > 0) ...[
                        Text('   ·   ',
                            style: Theme.of(context).textTheme.titleSmall),
                        Text(
                          l.bonoReviewLinesNew(newCount),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: _amber, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12, top: 2),
                    itemCount: active.length,
                    itemBuilder: (context, i) => _card(active[i], i + 1),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            height: 60,
            child: FilledButton(
              onPressed: active.isEmpty || _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.bonoReviewSave(active.length),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        if (newProducts > 0)
                          Text(
                            l.bonoReviewSaveNew(newProducts),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(_Line line, int number) {
    final l = tr(context);
    final theme = Theme.of(context);
    final flagged = line.isNew || line.newPackaging;
    final accent = flagged ? _amber : _green;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editLine(line),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Number (matches the paper bono) + the one glance cue,
                      // and a faint pencil hinting the whole card is tappable.
                      Row(
                        children: [
                          _NumberBadge(number: number, color: accent),
                          const SizedBox(width: 8),
                          if (flagged)
                            _NewChip(
                              label: line.isNew
                                  ? l.bonoReviewNewProduct
                                  : l.bonoReviewNewPack,
                            )
                          else
                            const _OkMark(),
                          const Spacer(),
                          Icon(Icons.edit_outlined,
                              size: 16, color: theme.colorScheme.outline),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        line.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(_detailLine(line), style: theme.textTheme.bodyMedium),
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _detailLine(_Line line) {
    final label = _packLabelFor(line);
    final pkg = label.isNotEmpty ? label : '—';
    final qty = '× ${_fmtNum(line.quantity)}';
    final total = line.lineTotal != null
        ? ' · ${formatMoney(line.lineTotal!, widget.shop)}'
        : '';
    return '$pkg   $qty$total';
  }

  // Tap a card → the one edit sheet. It mutates the line in place and pops an
  // action (saved / removed); we just rebuild.
  Future<void> _editLine(_Line line) async {
    final action = await showModalBottomSheet<_EditAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditLineSheet(
        line: line,
        shop: widget.shop,
        unitLabels: _unitLabels,
        categories: _categories,
        supplierPartyId: widget.supplierPartyId,
      ),
    );
    if (!mounted || action == null) return;
    setState(() {
      if (action == _EditAction.removed) line.removed = true;
    });
  }

  // The only write point: materialize each line the right way, then hand the
  // receive well-formed apply lines. Offline-safe (the item_creator helpers
  // queue + return optimistic ids). A hard reject leaves the screen open.
  Future<void> _save() async {
    if (_saving) return;
    final l = tr(context);
    setState(() => _saving = true);
    final out = <BonoApplyLine>[];
    var failed = false;

    for (final line in _active) {
      String? itemId = line.shopItemId;
      String? unitId = line.shopItemUnitId;
      var pkg = line.packagingLabel;
      var baseLbl = line.baseUnitLabel;

      if (line.isNew) {
        final baseCode = line.baseUnitCode ?? 'piece';
        final hasPack = line.packUnitCode != null &&
            line.packSize != null &&
            line.packSize! > 1;
        final r = await createShopItemDraft(
          context,
          shop: widget.shop,
          name: line.displayName,
          categoryId: line.categoryId,
          baseUnitCode: baseCode,
          baseUnitLabel: _labelFor(baseCode),
          soldUnitCode: hasPack ? line.packUnitCode : null,
          soldUnitLabel: hasPack ? _labelFor(line.packUnitCode) : null,
          soldConversion: hasPack ? line.packSize : null,
          languageCode: Localizations.localeOf(context).languageCode,
          defaultSide: 'receive',
          errorMessage: l.addNewItemFailedMessage,
        );
        if (r == null) {
          failed = true;
          break;
        }
        itemId = r.shopItemId;
        unitId = r.shopItemUnitId;
        pkg = r.packagingLabel;
        baseLbl = r.baseUnitLabel;
      } else if (line.newPackaging &&
          line.packUnitCode != null &&
          line.packSize != null) {
        final added = await addShopItemUnitDraft(
          context,
          shop: widget.shop,
          shopItemId: line.shopItemId!,
          unitCode: line.packUnitCode!,
          unitLabel: _labelFor(line.packUnitCode),
          baseUnitLabel: _labelFor(line.baseUnitCode),
          conversionToBase: line.packSize!,
          errorMessage: l.addNewItemFailedMessage,
        );
        if (added == null) {
          failed = true;
          break;
        }
        unitId = added.shopItemUnitId;
        pkg = added.packagingLabel;
      }

      if (itemId == null || unitId == null) continue;
      out.add(BonoApplyLine(
        shopItemId: itemId,
        shopItemUnitId: unitId,
        itemId: line.itemId,
        displayName: line.displayName,
        packagingLabel: pkg,
        baseUnitLabel: baseLbl,
        quantity: line.quantity,
        lineTotal: line.lineTotal ?? 0,
        rawText: line.rawText,
        learnConfidence: line.learnConfidence,
      ));
    }

    if (!mounted) return;
    if (failed) {
      // The helper already surfaced the error; keep the screen so the cashier
      // can Remove/retry the offending line.
      setState(() => _saving = false);
      return;
    }
    Navigator.of(context).pop(out);
  }
}

// Small green tick — the "matched, trust it" cue.
class _OkMark extends StatelessWidget {
  const _OkMark();
  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 15, color: _green),
      );
}

// Amber "New product" / "New pack" chip — the "give this a look" cue.
class _NewChip extends StatelessWidget {
  const _NewChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: _amber, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// Card position (1-based) so the cashier can cross-check against the paper
// bono's line order. Tinted with the card's status accent.
class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.number, required this.color});
  final int number;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color),
      ),
      child: Text(
        '$number',
        style: theme.textTheme.labelMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Mutable per-line draft the review screen edits in place.
class _Line {
  _Line({
    required this.rawText,
    required this.shopItemId,
    required this.shopItemUnitId,
    required this.itemId,
    required this.displayName,
    required this.categoryId,
    required this.packagingLabel,
    required this.baseUnitLabel,
    required this.baseUnitCode,
    required this.packUnitCode,
    required this.packSize,
    required this.quantity,
    required this.lineTotal,
    required this.learnConfidence,
    this.newPackaging = false,
  });

  factory _Line.fromSuggestion(BonoSuggestion s) {
    final total = s.lineTotal ??
        (s.unitPrice != null ? s.unitPrice! * s.quantity : null);
    if (s.isBound) {
      // Matched line whose OCR pack is NEW to the item (0114) carries the AI
      // pack to add; otherwise it's a clean matched line.
      final newPack = s.newPackaging &&
          s.suggestedPackUnitCode != null &&
          s.suggestedPackSize != null;
      return _Line(
        rawText: s.rawText,
        shopItemId: s.suggestedShopItemId,
        shopItemUnitId: s.suggestedShopItemUnitId,
        itemId: s.itemId,
        displayName: s.displayName ?? s.rawText,
        categoryId: s.suggestedCategoryId,
        packagingLabel: s.unitCode ?? s.baseUnitCode ?? '',
        baseUnitLabel: s.baseUnitCode ?? '',
        baseUnitCode: s.baseUnitCode,
        packUnitCode: newPack ? s.suggestedPackUnitCode : null,
        packSize: newPack ? s.suggestedPackSize : null,
        newPackaging: newPack,
        quantity: s.quantity,
        lineTotal: total,
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
      categoryId: s.suggestedCategoryId,
      packagingLabel: s.suggestedPackUnitCode ?? s.suggestedBaseUnitCode ?? '',
      baseUnitLabel: s.suggestedBaseUnitCode ?? '',
      baseUnitCode: s.suggestedBaseUnitCode,
      packUnitCode: s.suggestedPackUnitCode,
      packSize: s.suggestedPackSize,
      quantity: s.quantity,
      lineTotal: total,
      learnConfidence: 1,
    );
  }

  final String rawText;
  String? shopItemId;
  String? shopItemUnitId;
  String? itemId;
  String displayName;
  String? categoryId;
  String packagingLabel;
  String baseUnitLabel;
  final String? baseUnitCode;
  final String? packUnitCode;
  final double? packSize;
  double quantity;
  double? lineTotal;
  bool removed = false;
  double learnConfidence;
  // Matched line whose OCR pack is new to the item — flips false once the
  // cashier picks an existing pack instead.
  bool newPackaging;

  bool get isNew => shopItemId == null;
}

enum _EditAction { saved, removed }

/// One editing surface for EVERY line: product, packaging, quantity, total,
/// remove. Kind-aware rows (a new product also edits name + category), but the
/// same gesture and shell. Mutates the passed [_Line]; pops an [_EditAction].
class _EditLineSheet extends StatefulWidget {
  const _EditLineSheet({
    required this.line,
    required this.shop,
    required this.unitLabels,
    required this.categories,
    this.supplierPartyId,
  });

  final _Line line;
  final ShopSummary shop;
  final Map<String, String> unitLabels;
  final List<CategoryOption> categories;
  final String? supplierPartyId;

  @override
  State<_EditLineSheet> createState() => _EditLineSheetState();
}

class _EditLineSheetState extends State<_EditLineSheet> {
  late final TextEditingController _qty =
      TextEditingController(text: _fmtNum(widget.line.quantity));
  late final TextEditingController _total = TextEditingController(
      text: widget.line.lineTotal != null ? _fmtNum(widget.line.lineTotal!) : '');
  late final TextEditingController _name =
      TextEditingController(text: widget.line.displayName);

  @override
  void dispose() {
    _qty.dispose();
    _total.dispose();
    _name.dispose();
    super.dispose();
  }

  String _labelFor(String? code) =>
      code == null ? '' : (widget.unitLabels[code] ?? code);

  String _packLabel() {
    final line = widget.line;
    if (line.packSize != null && line.packUnitCode != null) {
      return packagingLabel(
        line.packSize!,
        _labelFor(line.baseUnitCode),
        _labelFor(line.packUnitCode),
      );
    }
    return line.packagingLabel.isNotEmpty
        ? line.packagingLabel
        : _labelFor(line.baseUnitCode);
  }

  // Bind this line to an existing product (fixes a wrong/missed match, and
  // converts a new-product line into a matched one).
  Future<void> _changeProduct() async {
    final target = await showBonoBindItemPicker(
      context,
      shop: widget.shop,
      supplierPartyId: widget.supplierPartyId,
      initialQuery: widget.line.rawText,
    );
    if (target == null || !mounted) return;
    setState(() {
      final line = widget.line;
      line.shopItemId = target.shopItemId;
      line.shopItemUnitId = target.shopItemUnitId;
      line.itemId = target.itemId;
      line.displayName = target.displayName;
      line.packagingLabel = target.packagingLabel;
      line.baseUnitLabel = target.baseUnitLabel;
      line.newPackaging = false;
      line.learnConfidence = 1;
      _name.text = target.displayName;
    });
  }

  // Change to a different EXISTING packaging of the matched item (the picker's
  // inline "+ Add packaging" also covers a custom size).
  Future<void> _changePackaging() async {
    final line = widget.line;
    final picked = await showUnitPicker(
      context,
      shopId: widget.shop.id,
      shopItemId: line.shopItemId!,
      screen: 'receive',
      baseUnitCode: line.baseUnitCode,
      baseUnitLabel: _labelFor(line.baseUnitCode),
    );
    if (picked == null || !mounted) return;
    setState(() {
      line.shopItemUnitId = picked.shopItemUnitId;
      line.packagingLabel = picked.packagingLabel;
      line.newPackaging = false;
    });
  }

  void _save() {
    final line = widget.line;
    line.quantity = double.tryParse(_qty.text.trim()) ?? line.quantity;
    final t = _total.text.trim();
    line.lineTotal = t.isEmpty ? null : (double.tryParse(t) ?? line.lineTotal);
    if (line.isNew) {
      final name = _name.text.trim();
      if (name.isNotEmpty) line.displayName = name;
    }
    Navigator.of(context).pop(_EditAction.saved);
  }

  Widget _tapRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Expanded(child: Text(value.isEmpty ? '—' : value)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final line = widget.line;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    // Guard: only pass a category value the dropdown actually has an item for.
    final catValue =
        widget.categories.any((c) => c.id == line.categoryId) ? line.categoryId : null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
        child: SingleChildScrollView(
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
              const SizedBox(height: 8),
              if (line.isNew) ...[
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l.bonoReviewEditName,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _changeProduct,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(l.bonoReviewPickExisting),
                  ),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String?>(
                  initialValue: catValue,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l.bonoReviewEditCategory,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l.bonoReviewUncategorized),
                    ),
                    ...widget.categories.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => line.categoryId = v),
                ),
                const SizedBox(height: 10),
                // A new product's base/pack comes from the AI; not editable
                // inline (rare) — Pick existing or Remove if it's wrong.
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: l.bonoReviewEditPackaging,
                    border: const OutlineInputBorder(),
                  ),
                  child: Text(_packLabel()),
                ),
              ] else ...[
                _tapRow(
                  label: l.bonoReviewEditItem,
                  value: line.displayName,
                  onTap: _changeProduct,
                ),
                const SizedBox(height: 10),
                _tapRow(
                  label: l.bonoReviewEditPackaging,
                  value: _packLabel(),
                  onTap: _changePackaging,
                ),
              ],
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
                    setState(() => _qty.text = _fmtNum(v.toDouble())),
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
                height: 52,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(l.bonoReviewEditSave),
                ),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_EditAction.removed),
                icon: Icon(Icons.delete_outline,
                    size: 18, color: theme.colorScheme.error),
                label: Text(
                  l.bonoReviewRemove,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
